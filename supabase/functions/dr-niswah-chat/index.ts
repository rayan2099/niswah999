// Supabase Edge Function: dr-niswah-chat
//
// Owns the "طبيبة" persona system prompt and the Gemini call server-side —
// the prompt is versioned here (via git) and never shipped to the client.
// Also derives the pregnancy/postpartum context by reading the user's own
// rows and runs red-flag screening before the Gemini call. V1 KB integration
// (2026-09-29): substantive medical education is now grounded in published,
// production-eligible Health/Safety KB rows; citations are backend metadata.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { callGemini } from '../_shared/gemini_client.ts';
import { buildUserAiContext, formatContextBlock } from '../_shared/ai_user_context.ts';
import {
  citationPayload,
  formatKnowledgeBlock,
  retrieveKnowledge,
} from '../_shared/kb_retrieval.ts';
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

const SYSTEM_PROMPT = `أنتِ "طبيبة"، مرافقة صحية تعليمية داخل تطبيق نسوة.
أسلوبك دافئ، مطمئن، مباشر، وبالعربية الفصحى المبسطة عندما تكتب المستخدمة بالعربية.

ادخلي في صلب الإجابة مباشرة. لا تستخدمي رموز الماركداون. اجعلي الإجابة مختصرة عادةً إلا إذا طلبت المستخدمة تفصيلاً.

السياق الحالي للمستخدمة يصلك في كتلة [CONTEXT]. استخدميه للتخصيص دون تحويله إلى تشخيص.
- إن كان mode=pregnant، استخدمي الأسبوع/الثلث عند الصلة فقط.
- إن كان mode=postpartum، تحدثي عن مرحلة ما بعد الولادة.
- إن كان mode=unknown، لا تفترضي أسبوع حمل.
- high_risk_flags والملاحظات الذاتية إشارات سياقية وليست تشخيصًا.

سيصلك أيضًا [KNOWLEDGE] من قاعدة معرفة نسوة المعتمدة للإنتاج في هذه النسخة.
قواعد المعرفة غير قابلة للتجاوز:
- استخدمي [KNOWLEDGE] كمصدر وحيد لأي ادعاء صحي موضوعي/تعليمي محدد في الإجابة.
- لا تضيفي حقيقة طبية أو رقمًا أو جرعة أو حدًا زمنيًا غير مدعوم بالـ[KNOWLEDGE] المسترجع لهذه الرسالة.
- إذا لم توجد معرفة مؤهلة تدعم ادعاءً محددًا، اذكري حدود المعرفة المتاحة ووجهي لمختص بدل التخمين.
- لا تختلقي استشهادات ولا تكتبي روابط من عندك؛ الاستشهادات تُرفق من الخادم بشكل منفصل.
- لا تشخّصي، ولا تصفي علاجًا أو دواءً مخصصًا للمستخدمة.

حدود السلامة:
- عند علامة خطر، الأولوية للتوجيه الطبي العاجل؛ لا تسمحي للنص التثقيفي أن يؤخر هذا التوجيه.
- لا تحوّلي عرضًا إلى تشخيص.
- إذا كان مستوى الخطورة غير واضح، صرّحي بعدم اليقين ووجهي إلى مختص.`;

const URGENT_BANNER_AR =
  'قد يكون هذا من علامات الخطر. يُرجى التواصل مع طبيبتك أو الطوارئ الآن.';
const URGENT_BANNER_EN =
  'This may be an urgent warning sign. Please contact your clinician or emergency care now.';

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

function detectLanguage(text: string): 'ar' | 'en' {
  return /[\u0600-\u06FF]/.test(text) ? 'ar' : 'en';
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

    const language = detectLanguage(content);
    const redFlags = detectRedFlags(content);
    const urgent = redFlags.length > 0;

    // A red-flag safety message must never be blocked by abuse controls.
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

    const [userContext, safetyHits, healthHits] = await Promise.all([
      buildUserAiContext(userClient, { currentMessageSafetyFlags: redFlags }),
      retrieveKnowledge(userClient, {
        domain: 'SAFETY_ESCALATION',
        language,
        query: content,
        limit: urgent ? 8 : 4,
      }),
      retrieveKnowledge(userClient, {
        domain: 'HEALTH',
        language,
        query: content,
        limit: 8,
      }),
    ]);

    const kbHits = [...safetyHits, ...healthHits];
    const citations = citationPayload(kbHits);
    const systemInstruction = [
      SYSTEM_PROMPT,
      formatContextBlock(userContext, 'dr_niswah'),
      formatKnowledgeBlock(kbHits),
    ].join('\n\n');

    let reply: string;
    try {
      const result = await callGemini({
        models: GEMINI_MODELS,
        prompt: content,
        systemInstruction,
      });
      reply = result.text;
    } catch (error) {
      console.error('dr-niswah-chat: Gemini call failed', {
        userId,
        threadId,
        urgent,
        error: error instanceof Error ? error.message : String(error),
      });
      reply = urgent
        ? ''
        : language === 'ar'
          ? 'تعذر الحصول على رد الآن. حاولي مرة أخرى بعد قليل، وإذا كان لديك عرض مقلق فتواصلي مع مختص صحي.'
          : 'A response is unavailable right now. Please try again, and contact a clinician if you have a concerning symptom.';
    }

    const urgentBanner = language === 'ar' ? URGENT_BANNER_AR : URGENT_BANNER_EN;
    const finalReply = urgent
      ? reply
        ? `${urgentBanner}\n\n${reply}`
        : urgentBanner
      : reply;

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
          metadata: {
            source: 'gemini_kb_grounded',
            urgent,
            knowledge_keys: [...new Set(kbHits.map((h) => h.knowledge_key))],
            citation_count: citations.length,
          },
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
        citations,
        knowledgeGrounded: kbHits.length > 0,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (error) {
    console.error('dr-niswah-chat: unhandled error', {
      error: error instanceof Error ? error.message : String(error),
    });
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error.' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
