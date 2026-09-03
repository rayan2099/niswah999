// Supabase Edge Function: dr-niswah-chat
//
// Owns the "طبيبة" persona system prompt and the Gemini call server-side —
// the prompt is versioned here (via git) and never shipped to the client.
// Also derives the pregnancy/postpartum context by reading the user's own
// rows (recompute-on-read: week/trimester are always computed from dates,
// never trusted from a cached value) and runs the red-flag keyword check
// before the Gemini call so the urgent flag is correct even if Gemini
// fails or times out.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getPregnancyStatus, PregnancyProfileRow, PregnancyStatus } from './pregnancy_status.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const GEMINI_ENDPOINT =
  'https://generativelanguage.googleapis.com/v1beta/interactions';
const GEMINI_MODELS = ['gemini-3.5-flash-lite', 'gemini-3.6-flash'];

const SYSTEM_PROMPT = `أنتِ "طبيبة"، مرافقة رقمية للحمل داخل تطبيق طبيبة الحمل الذكية.
أسلوبك دافئ، مطمئن، مباشر، وباللهجة العربية الفصحى المبسطة.

ادخلي في صلب الإجابة مباشرة دون مقدمات مثل "من المهم أن أذكر" أو
"في الواقع" أو "تجدر الإشارة إلى". كوني محددة وملموسة (مثال: بدل
"من المفيد الراحة"، قولي "استلقي على جانبك الأيسر لعشر دقائق").
لا تنهي إجابتك بجملة ختامية استعراضية أو حكمة عامة؛ توقفي عند آخر
نقطة مفيدة. تجنبي الإيموجي والتنسيق الزائد والقوائم النقطية إلا إذا
كانت الإجابة تتطلب خطوات فعلاً. لا تستخدمي رموز الماركداون إطلاقاً
مثل # أو ## أو ** أو * — التطبيق يعرض النص كما هو دون تنسيق.

السياق الحالي للمستخدمة يصلك في كتلة [CONTEXT] مع كل رسالة. استخدميه
دائمًا لتخصيص إجابتك:
- إن كان mode=pregnant، اربطي إجابتك بالأسبوع/الشهر/الثلث الحالي
  بشكل طبيعي (مثال: "في الأسبوع 23 من الشائع أن..."), لا تكرري رقم
  الأسبوع في كل جملة، فقط عندما يفيد ذلك السياق الطبي.
- إن كان mode=postpartum، تحدثي عن مرحلة النفاس، لا عن الحمل.
- إن كان mode=unknown، لا تفترضي أسبوعًا. اسألي بلطف عن تاريخ آخر
  دورة أو الأسبوع التقريبي قبل تقديم نصيحة مرتبطة بمرحلة محددة.
  يمكنك إعطاء معلومة عامة غير مرتبطة بأسبوع بينما تسألين.
- راعي fasting_status عند الحديث عن الصيام أو الصلاة (وضعيات
  السجود المتغيرة حسب الثلث، الاستطاعة الجسدية، إلخ).
- إن وُجدت high_risk_flags، لا تتجاهليها، لكن لا تحوّلي الحديث إلى
  تشخيص — ذكّري المستخدمة بمتابعة هذه النقطة مع طبيبها.

حدود صارمة:
- لست بديلاً عن الطبيبة ولا تشخّصي حالات ولا تصفي أدوية أو جرعات.
- عند أي علامة خطر (نزيف، ألم حاد، تقلص حركة الجنين بشكل ملحوظ،
  صداع شديد مع تشوش رؤية، حمى مرتفعة، تسرب سائل) — توقفي فورًا عن
  الاسترسال وانصحي بالتواصل مع الطبيب أو الطوارئ الآن، بجملة واضحة
  ومباشرة، دون تهويل.
- لا تؤكدي معلومة طبية لست متأكدة أنها صحيحة لهذا الأسبوع تحديدًا؛
  إن لم تكوني متأكدة، وجّهي المستخدمة لطبيبها بدل التخمين.
- أجوبتك مختصرة (3-5 جمل عادة) إلا إن طلبت المستخدمة تفصيلاً أكبر.`;

const URGENT_BANNER_AR =
  'قد يكون هذا من علامات الخطر. يُرجى التواصل مع طبيبتك أو الطوارئ الآن.';

type RedFlagCategory =
  | 'bleeding'
  | 'severe_pain'
  | 'reduced_fetal_movement'
  | 'headache_with_vision_change'
  | 'fever'
  | 'fluid_leak';

const RED_FLAG_KEYWORDS: Record<Exclude<RedFlagCategory, 'headache_with_vision_change'>, string[]> = {
  bleeding: ['نزيف', 'دم كثير', 'bleeding', 'hemorrhage'],
  severe_pain: ['ألم حاد', 'ألم شديد', 'severe pain', 'sharp pain'],
  reduced_fetal_movement: [
    'تقلص حركة الجنين',
    'الجنين لا يتحرك',
    'حركة الجنين قلت',
    'reduced fetal movement',
    'baby not moving',
    'baby stopped moving',
  ],
  fever: ['حمى مرتفعة', 'حمى شديدة', 'high fever', 'severe fever'],
  fluid_leak: [
    'تسرب سائل',
    'نزول ماء',
    'الماء نزل',
    'fluid leakage',
    'water broke',
    'my water broke',
  ],
};
const HEADACHE_KEYWORDS = ['صداع شديد', 'severe headache'];
const VISION_KEYWORDS = ['تشوش رؤية', 'رؤية ضبابية', 'blurred vision', 'vision changes'];

function detectRedFlags(message: string): RedFlagCategory[] {
  const text = message.toLowerCase();
  const any = (keywords: string[]) =>
    keywords.some((keyword) => text.includes(keyword.toLowerCase()));

  const matched: RedFlagCategory[] = [];
  for (const [category, keywords] of Object.entries(RED_FLAG_KEYWORDS)) {
    if (any(keywords)) matched.push(category as RedFlagCategory);
  }
  if (any(HEADACHE_KEYWORDS) && any(VISION_KEYWORDS)) {
    matched.push('headache_with_vision_change');
  }
  return matched;
}

// Recomputes mode/week/trimester on every call from the stored profile —
// never trusts a cached "current_week" value, so the answer is always
// fresh. pregnancy_profile is the single source of truth for chat
// personalization (see supabase/migrations/20260824130000_pregnancy_profile.sql);
// pregnancy_milestones/nifas_records back other, unrelated features and are
// intentionally not read here.
async function loadPregnancyProfile(
  userClient: ReturnType<typeof createClient>,
  userId: string,
): Promise<PregnancyProfileRow | null> {
  const { data } = await userClient
    .from('pregnancy_profile')
    .select(
      'tracking_basis, reference_date, manual_week_value, manual_week_set_at, is_postpartum, postpartum_start_date, high_risk_flags, fasting_status, locale',
    )
    .eq('user_id', userId)
    .maybeSingle();

  return (data as PregnancyProfileRow | null) ?? null;
}

function buildContextBlock(
  status: PregnancyStatus,
  profile: PregnancyProfileRow | null,
): string {
  const lines = [`mode: ${status.mode}`];
  if (status.mode === 'pregnant') {
    lines.push(`pregnancy_week: ${status.week}`);
    lines.push(`trimester: ${status.trimester}`);
    lines.push(`approx_month: ${status.month}`);
    lines.push(`weeks_to_due: ${status.weeksToDue}`);
  } else if (status.mode === 'postpartum') {
    lines.push(`days_postpartum: ${status.daysPostpartum}`);
  }
  lines.push(`fasting_status: ${profile?.fasting_status ?? 'not_applicable'}`);
  const highRiskFlags = profile?.high_risk_flags ?? [];
  lines.push(
    `high_risk_flags: ${highRiskFlags.length ? highRiskFlags.join(', ') : '[]'}`,
  );
  lines.push(`locale: ${profile?.locale ?? 'ar'}`);
  return `[CONTEXT — internal, do not repeat verbatim to the user]\n${lines.join('\n')}\n[END CONTEXT]`;
}

async function callGemini(prompt: string, systemInstruction: string): Promise<string> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) throw new Error('GEMINI_API_KEY is not configured.');

  let lastError: unknown;
  for (const model of GEMINI_MODELS) {
    try {
      const response = await fetch(GEMINI_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify({
          model,
          input: prompt,
          system_instruction: systemInstruction,
        }),
      });
      if (!response.ok) {
        if ([429, 500, 503].includes(response.status)) {
          lastError = new Error(`Gemini request failed (${response.status}).`);
          continue;
        }
        const body = await response.json().catch(() => null);
        throw new Error(body?.error?.message ?? `Gemini request failed (${response.status}).`);
      }
      const decoded = await response.json();
      const blocks: Array<{ text?: string }> = [
        ...(decoded.steps ?? []),
        ...(decoded.outputs ?? []),
      ]
        .filter((step: { type?: string }) => step.type === 'model_output')
        .flatMap((step: { content?: unknown[] }) => step.content ?? []);
      const text = blocks
        .map((block) => block.text ?? '')
        .filter(Boolean)
        .join('\n')
        .trim();
      if (!text) throw new Error('Gemini returned no text.');
      return text;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError instanceof Error ? lastError : new Error('Gemini request failed.');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header.' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // Scoped to the calling user's JWT — every read/write below is subject
    // to that user's own RLS policies.
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData?.user) {
      return new Response(JSON.stringify({ error: 'Invalid session.' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const userId = userData.user.id;

    const { threadId, content } = await req.json();
    if (!threadId || typeof content !== 'string' || !content.trim()) {
      return new Response(JSON.stringify({ error: 'threadId and content are required.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const redFlags = detectRedFlags(content);
    const urgent = redFlags.length > 0;

    // Logged independently of the Gemini call below via the service role
    // (flagged_conversations has no client-facing RLS policy).
    if (urgent) {
      const serviceClient = createClient(supabaseUrl, serviceRoleKey);
      await serviceClient.from('flagged_conversations').insert({
        user_id: userId,
        thread_id: threadId,
        message_excerpt: content.slice(0, 500),
        matched_categories: redFlags,
      });
    }

    await userClient.from('chat_messages').insert({
      thread_id: threadId,
      user_id: userId,
      role: 'user',
      content,
      metadata: {},
    });

    const pregnancyProfile = await loadPregnancyProfile(userClient, userId);
    const pregnancyStatus = getPregnancyStatus(pregnancyProfile, new Date());
    const systemInstruction = `${SYSTEM_PROMPT}\n\n${buildContextBlock(pregnancyStatus, pregnancyProfile)}`;

    let reply: string;
    try {
      reply = await callGemini(content, systemInstruction);
    } catch (_error) {
      reply = urgent
        ? ''
        : 'تعذر الحصول على رد الآن. حاولي مرة أخرى بعد قليل.';
    }

    const finalReply = urgent
      ? reply
        ? `${URGENT_BANNER_AR}\n\n${reply}`
        : URGENT_BANNER_AR
      : reply;

    const { data: savedAssistantMessage } = await userClient
      .from('chat_messages')
      .insert({
        thread_id: threadId,
        user_id: userId,
        role: 'assistant',
        content: finalReply,
        metadata: { source: 'gemini', urgent },
      })
      .select()
      .single();

    return new Response(
      JSON.stringify({
        reply: finalReply,
        urgent,
        messageId: savedAssistantMessage?.id ?? null,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error.' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
