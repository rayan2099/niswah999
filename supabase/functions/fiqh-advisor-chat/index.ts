// Supabase Edge Function: fiqh-advisor-chat
//
// Server-side home for the Fiqh Advisor's Gemini call and Google-Search
// grounding, moved off the client per the Gemini trust-boundary remediation
// (closes SEC-001/AB-002/AB-012 for this feature). The system prompt and the
// trusted-citation filter (previously applied client-side in
// ai_advisor_service.dart) are now both owned here — the client only ever
// sends the question and the user's selected madhhab.
//
// AICTX remediation (2026-09-09): previously received only the madhhab
// label — zero deterministic-engine output (AICTX-3). Now also receives
// cycle/pregnancy facts and, when supplied by the client, the deterministic
// fiqh classification (clearly labeled client_computed — see
// _shared/ai_user_context.ts's header comment for why this is not
// reimplemented/re-verified server-side). The system prompt is updated to
// explain it, not to change what it's allowed to conclude from it.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { callGemini } from '../_shared/gemini_client.ts';
import { buildUserAiContext, formatContextBlock } from '../_shared/ai_user_context.ts';
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

const GEMINI_MODELS = ['gemini-3.6-flash', 'gemini-3.5-flash'];
const MAX_QUESTION_LENGTH = 4000;
const ALLOWED_MADHHABS = ['hanafi', 'maliki', 'shafii', 'hanbali'];
const TRUSTED_CITATION_DOMAINS = ['islamweb.net', 'dorar.net'];

const NO_SOURCES_FALLBACK_AR =
  'تعذر الوصول إلى المصادر الموثقة الآن. لا يمكن إصدار توجيه فقهي آلي دون مصادر؛ يُرجى المحاولة لاحقاً أو سؤال عالِمة أو جهة إفتاء مؤهلة.';
const NO_TRUSTED_CITATIONS_AR =
  'لم أجد مصادر فقهية موثقة وكافية لهذه الحالة. يُرجى عرض التفاصيل على عالِمة أو جهة إفتاء مؤهلة، ولا تعتمدي على إجابة آلية لاتخاذ حكم العبادة.';
// Fiqh Remediation Wave 1 (Section E, extended to this AI-facing surface):
// no madhhab is SELECTED yet (UNSET or UNKNOWN) — this function must never
// invent one just to produce an answer. Calm, matches the onboarding
// explanation's tone (Section H), never implies fault or pressure.
const NO_MADHHAB_SELECTED_AR =
  'لم تختاري مذهبكِ الفقهي بعد، لذا لا يمكن تقديم توجيه دقيق دون معرفته. يمكنكِ اختياره من الإعدادات، أو اختيار "لا أعرف مذهبي" إذا كنتِ غير متأكدة — سنساعدكِ في ذلك.';

function buildSystemInstruction(madhhab: string): string {
  return `You are Niswah's Fiqh research assistant. The user's selected school is ${madhhab}.
Answer in the user's language and stay within that school unless comparison is explicitly requested.
Use Google Search for every substantive ruling. Prefer recognized, attributable scholarly sources and structured fatwa repositories such as islamweb.net and dorar.net, then verified school-specific primary or institutional references.
Never infer a ruling from cycle arithmetic alone. Clearly distinguish factual tracking data from a religious ruling.
Include inline citations for every material ruling. If reliable sources conflict, are absent, or the case involves irregular habit transitions, pregnancy, miscarriage, nifas, retrospective prayer/fasting obligations, or danger to health, say that the case needs a qualified scholar and do not give a definitive ruling.
Do not diagnose medical conditions. Urgent or dangerous symptoms must be escalated to licensed medical care.
Do not claim certainty beyond the cited evidence.
Write in plain prose only. Never use markdown syntax: no #, ##, ###, **, *, or numbered/bulleted list characters. The app displays raw text, not rendered markdown.

A [CONTEXT] block may follow with facts already known by the app (recent bleeding history, pregnancy status, and — only when the client app supplied one — a deterministic_fiqh_classification already computed by the app's own rule engine, explicitly labeled with its source). Use this only to avoid asking the user to re-describe what the app already knows and to notice when her question concerns pregnancy/nifas/an irregular pattern even if she didn't say so explicitly — every escalation rule above still applies exactly as written when that's the case. If deterministic_fiqh_classification is present, you may reference it as the app's own existing classification, but do not present it as your own conclusion, do not contradict it, and never treat the informational bleeding-history scan in the context (which is explicitly not a ruling) as equivalent to a classification.`;
}

function isTrustedCitation(url: string): boolean {
  let host: string;
  try {
    host = new URL(url).host.toLowerCase();
  } catch {
    return false;
  }
  return TRUSTED_CITATION_DOMAINS.some(
    (domain) => host === domain || host.endsWith(`.${domain}`),
  );
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

    const rateLimit = await checkRateLimit(
      userClient,
      'fiqh-advisor-chat',
      AI_ENDPOINT_RATE_LIMIT,
    );
    if (rateLimit.status === 'rate_limited') {
      return rateLimitedResponse(rateLimit.retryAfterSeconds, corsHeaders);
    }
    if (rateLimit.status === 'limiter_unavailable') {
      return limiterUnavailableResponse(corsHeaders);
    }

    const { question, madhhab, madhhab_state: madhhabStateRaw, clientFiqhState } = await req.json();
    if (typeof question !== 'string' || !question.trim()) {
      return new Response(JSON.stringify({ error: 'question is required.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (question.length > MAX_QUESTION_LENGTH) {
      return new Response(
        JSON.stringify({ error: `question exceeds ${MAX_QUESTION_LENGTH} characters.` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Fiqh Remediation Wave 1 (Section F): madhhab_state distinguishes
    // UNSET/UNKNOWN/SELECTED explicitly. An older client build that never
    // sends madhhab_state at all is treated as the pre-existing contract
    // (a plain madhhab string implies SELECTED) — every current client
    // build sends it explicitly.
    const madhhabState =
      madhhabStateRaw === 'unset' || madhhabStateRaw === 'unknown' || madhhabStateRaw === 'selected'
        ? madhhabStateRaw
        : (typeof madhhab === 'string' && ALLOWED_MADHHABS.includes(madhhab) ? 'selected' : 'unset');

    if (madhhabState !== 'selected') {
      // Never call Gemini with an invented madhhab — an honest, calm,
      // non-blocking degraded response instead (Section E/H).
      return new Response(JSON.stringify({ text: NO_MADHHAB_SELECTED_AR, citations: [] }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (typeof madhhab !== 'string' || !ALLOWED_MADHHABS.includes(madhhab)) {
      return new Response(JSON.stringify({ error: 'madhhab must be one of: ' + ALLOWED_MADHHABS.join(', ') }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const userContext = await buildUserAiContext(userClient, {
      clientMadhhab: madhhab,
      clientMadhhabState: madhhabState,
      clientFiqhState: typeof clientFiqhState === 'string' ? clientFiqhState : null,
    });
    const systemInstruction = `${buildSystemInstruction(madhhab)}\n\n${formatContextBlock(userContext, 'fiqh_advisor')}`;

    let text: string;
    let citations: Array<{ url: string; title: string; startIndex: number; endIndex: number }>;
    try {
      const result = await callGemini({
        models: GEMINI_MODELS,
        prompt: question,
        systemInstruction,
        useGoogleSearch: true,
        timeoutMs: 35_000,
      });
      const trusted = result.citations.filter((c) => isTrustedCitation(c.url));
      if (trusted.length === 0) {
        text = NO_TRUSTED_CITATIONS_AR;
        citations = [];
      } else {
        text = result.text;
        citations = trusted;
      }
    } catch (error) {
      console.error('fiqh-advisor-chat: Gemini call failed', {
        userId: userData.user.id,
        error: error instanceof Error ? error.message : String(error),
      });
      text = NO_SOURCES_FALLBACK_AR;
      citations = [];
    }

    return new Response(JSON.stringify({ text, citations }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('fiqh-advisor-chat: unhandled error', {
      error: error instanceof Error ? error.message : String(error),
    });
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error.' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
