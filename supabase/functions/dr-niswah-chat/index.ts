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
import { callGemini } from '../_shared/gemini_client.ts';
import {
  AI_ENDPOINT_RATE_LIMIT,
  checkRateLimit,
  limiterUnavailableResponse,
  rateLimitedResponse,
} from '../_shared/rate_limit.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

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

    // A red-flag safety message must never be blocked by abuse controls —
    // the rate limit applies only to non-urgent traffic (closes AB-008).
    if (!urgent) {
      const rateLimit = await checkRateLimit(
        userClient,
        'dr-niswah-chat',
        AI_ENDPOINT_RATE_LIMIT,
      );
      if (rateLimit.status === 'rate_limited') {
        return rateLimitedResponse(rateLimit.retryAfterSeconds, corsHeaders);
      }
      if (rateLimit.status === 'limiter_unavailable') {
        return limiterUnavailableResponse(corsHeaders);
      }
    }

    // Each of the three persistence writes below (audit log, user message,
    // assistant message) is now independently isolated (PJ-004/OB-004):
    // previously, a failure in *any one* of them threw uncaught to the
    // outer handler, aborting the whole request with a raw 500 — silently
    // losing the user's message, the safety audit-log entry, AND the
    // Gemini reply (including the safety banner) together, even though
    // Gemini itself may never even have been called yet. Now, a failure in
    // any one is logged and the flow continues — the safety banner in
    // particular must reach the client's screen regardless of whether any
    // of these three inserts succeeds.
    let flaggedConversationSaved = true;
    if (urgent) {
      try {
        const serviceClient = createClient(supabaseUrl, serviceRoleKey);
        await serviceClient.from('flagged_conversations').insert({
          user_id: userId,
          thread_id: threadId,
          message_excerpt: content.slice(0, 500),
          matched_categories: redFlags,
        });
      } catch (error) {
        flaggedConversationSaved = false;
        // Zero-tolerance signal (per OB remediation plan §4): a failed
        // safety audit-log write is never allowed to be silent, even
        // though the conversation itself proceeds.
        console.error('dr-niswah-chat: flagged_conversations insert failed', {
          userId,
          threadId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    let userMessageSaved = true;
    try {
      await userClient.from('chat_messages').insert({
        thread_id: threadId,
        user_id: userId,
        role: 'user',
        content,
        metadata: {},
      });
    } catch (error) {
      userMessageSaved = false;
      console.error('dr-niswah-chat: user chat_messages insert failed', {
        userId,
        threadId,
        urgent,
        error: error instanceof Error ? error.message : String(error),
      });
    }

    const pregnancyProfile = await loadPregnancyProfile(userClient, userId);
    const pregnancyStatus = getPregnancyStatus(pregnancyProfile, new Date());
    const systemInstruction = `${SYSTEM_PROMPT}\n\n${buildContextBlock(pregnancyStatus, pregnancyProfile)}`;

    let reply: string;
    try {
      const result = await callGemini({
        models: GEMINI_MODELS,
        prompt: content,
        systemInstruction,
      });
      reply = result.text;
    } catch (error) {
      // Logged (not silently swallowed, per the Gemini trust-boundary
      // remediation's observability requirement) even though the user still
      // gets a graceful fallback message — a real doctor/urgent path needs a
      // visible failure signal, not just a nice error screen (OB-003).
      console.error('dr-niswah-chat: Gemini call failed', {
        userId,
        threadId,
        urgent,
        error: error instanceof Error ? error.message : String(error),
      });
      reply = urgent
        ? ''
        : 'تعذر الحصول على رد الآن. حاولي مرة أخرى بعد قليل.';
    }

    const finalReply = urgent
      ? reply
        ? `${URGENT_BANNER_AR}\n\n${reply}`
        : URGENT_BANNER_AR
      : reply;

    // The reply — including the safety banner for an urgent message — is
    // computed and about to be returned to the client regardless of what
    // happens below. A persistence failure here must not cost the user the
    // reply she can already see would exist; it costs only whether that
    // reply is also in her history the next time she opens the app (a
    // strictly smaller, and separately reported, problem).
    let assistantMessageId: string | null = null;
    let assistantMessageSaved = true;
    try {
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
      assistantMessageId = savedAssistantMessage?.id ?? null;
    } catch (error) {
      assistantMessageSaved = false;
      console.error('dr-niswah-chat: assistant chat_messages insert failed', {
        userId,
        threadId,
        urgent,
        error: error instanceof Error ? error.message : String(error),
      });
    }

    if (urgent && (!flaggedConversationSaved || !userMessageSaved || !assistantMessageSaved)) {
      // Zero-tolerance signal for the safety-relevant path specifically —
      // distinct from the per-write console.error calls above, this one
      // line lets a log-based alert catch "some part of an urgent
      // exchange didn't fully persist" without needing to correlate three
      // separate log lines (OB remediation plan §4's zero-tolerance alert).
      console.error('dr-niswah-chat: urgent exchange partially unpersisted', {
        userId,
        threadId,
        flaggedConversationSaved,
        userMessageSaved,
        assistantMessageSaved,
      });
    }

    return new Response(
      JSON.stringify({
        reply: finalReply,
        urgent,
        messageId: assistantMessageId,
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
