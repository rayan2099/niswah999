// Supabase Edge Function: fiqh-advisor-chat
// Production KB integration: only evidence-eligible, published rows are authoritative.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { callGemini } from '../_shared/gemini_client.ts';
import { buildUserAiContext, formatContextBlock } from '../_shared/ai_user_context.ts';
import { citationPayload, formatKnowledgeBlock, retrieveKnowledge } from '../_shared/kb_retrieval.ts';
import {
  AI_ENDPOINT_RATE_LIMIT,
  checkRateLimit,
  limiterUnavailableResponse,
  rateLimitedResponse,
} from '../_shared/rate_limit.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const GEMINI_MODELS = ['gemini-3.6-flash', 'gemini-3.5-flash'];
const MAX_QUESTION_LENGTH = 4000;
const ALLOWED_MADHHABS = ['hanafi', 'maliki', 'shafii', 'hanbali'];
const NO_MADHHAB_SELECTED_AR =
  'لم تختاري مذهبكِ الفقهي بعد، لذا لا يمكن تقديم توجيه دقيق دون معرفته. يمكنكِ اختياره من الإعدادات، أو اختيار "لا أعرف مذهبي" إذا كنتِ غير متأكدة.';
const NO_ELIGIBLE_KB_AR =
  'لا توجد في قاعدة المعرفة المعتمدة حاليًا مادة كافية لهذه الحالة ضمن مذهبك، لذلك لن أقدّم حكمًا آليًا. يُرجى سؤال جهة إفتاء أو عالِمة مؤهلة.';

function detectLanguage(text: string): 'ar' | 'en' {
  return /[\u0600-\u06FF]/.test(text) ? 'ar' : 'en';
}

function buildSystemInstruction(madhhab: string): string {
  return `You are Niswah's source-grounded Fiqh educational assistant for the ${madhhab} madhhab.
Use ONLY the supplied [KNOWLEDGE] block for substantive rulings. Never invent, broaden, or import a ruling from model memory or web search.
Every material ruling must stay within the supplied canonical statement and its conditions. Distinguish factual tracking data from a religious ruling.
If the supplied knowledge is insufficient for the exact case, say that the case requires qualified scholarly guidance rather than extrapolating.
Do not diagnose medical conditions. Urgent health symptoms must be escalated to licensed medical care.
Answer in the user's language. Plain prose only; no markdown.`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header.' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData?.user) {
      return new Response(JSON.stringify({ error: 'Invalid session.' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const rateLimit = await checkRateLimit(userClient, 'fiqh-advisor-chat', AI_ENDPOINT_RATE_LIMIT);
    if (rateLimit.status === 'rate_limited') return rateLimitedResponse(rateLimit.retryAfterSeconds, corsHeaders);
    if (rateLimit.status === 'limiter_unavailable') return limiterUnavailableResponse(corsHeaders);

    const { question, madhhab, madhhab_state: madhhabStateRaw, clientFiqhState } = await req.json();
    if (typeof question !== 'string' || !question.trim()) {
      return new Response(JSON.stringify({ error: 'question is required.' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (question.length > MAX_QUESTION_LENGTH) {
      return new Response(JSON.stringify({ error: `question exceeds ${MAX_QUESTION_LENGTH} characters.` }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const madhhabState =
      madhhabStateRaw === 'unset' || madhhabStateRaw === 'unknown' || madhhabStateRaw === 'selected'
        ? madhhabStateRaw
        : (typeof madhhab === 'string' && ALLOWED_MADHHABS.includes(madhhab) ? 'selected' : 'unset');

    if (madhhabState !== 'selected') {
      return new Response(JSON.stringify({ text: NO_MADHHAB_SELECTED_AR, citations: [] }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (typeof madhhab !== 'string' || !ALLOWED_MADHHABS.includes(madhhab)) {
      return new Response(JSON.stringify({ error: 'Invalid madhhab.' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const language = detectLanguage(question);
    const [userContext, kbHits] = await Promise.all([
      buildUserAiContext(userClient, {
        clientMadhhab: madhhab,
        clientMadhhabState: madhhabState,
        clientFiqhState: typeof clientFiqhState === 'string' ? clientFiqhState : null,
      }),
      retrieveKnowledge(userClient, {
        domain: 'FIQH', language, query: question, madhhab, limit: 8,
      }),
    ]);

    if (kbHits.length === 0) {
      return new Response(JSON.stringify({ text: NO_ELIGIBLE_KB_AR, citations: [] }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const systemInstruction = `${buildSystemInstruction(madhhab)}\n\n${formatContextBlock(userContext, 'fiqh_advisor')}\n\n${formatKnowledgeBlock(kbHits)}`;
    const result = await callGemini({
      models: GEMINI_MODELS,
      prompt: question,
      systemInstruction,
      timeoutMs: 30_000,
    });

    return new Response(JSON.stringify({ text: result.text, citations: citationPayload(kbHits) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('fiqh-advisor-chat: request failed', {
      error: error instanceof Error ? error.message : String(error),
    });
    return new Response(JSON.stringify({ error: 'Fiqh advisor unavailable.' }), {
      status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
