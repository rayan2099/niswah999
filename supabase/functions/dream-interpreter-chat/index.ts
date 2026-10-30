// Supabase Edge Function: dream-interpreter-chat
//
// Server-side home for the Dream Interpreter's model call, moved off the
// client per the Gemini trust-boundary remediation (closes SEC-001/AB-002
// for this feature). The system prompt is owned here; the client sends only
// the already-assembled conversation transcript (neither Gemini's old
// /interactions endpoint nor OpenAI's Responses API endpoint used here has
// a history field of its own, so the client still resends the whole
// transcript each turn — unchanged behavior, just relocated). Provider
// Migration (2026-09-30): generation now goes through OpenAI's Responses
// API (openai_client.ts), not Gemini.
//
// AICTX remediation (2026-09-09): previously received zero context
// (AICTX-4, lowest materiality of the four AI features given its
// non-medical/non-fiqh domain, but still a real, disclosed gap). Now
// receives a light 'dream_interpreter' scope — major pregnancy/menstrual
// state and recent wellbeing/notes — explicitly not to be reinterpreted as
// medical or fiqh rulings (see the added system-prompt guidance below).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { callOpenAI } from '../_shared/openai_client.ts';
import { buildUserAiContext, formatContextBlock } from '../_shared/ai_user_context.ts';
import { AI_ENDPOINT_RATE_LIMIT, checkRateLimit } from '../_shared/rate_limit.ts';
import {
  categorizeError,
  CHAT_CORS_HEADERS,
  chatErrorResponse,
  chatJsonResponse,
  correlationIdFrom,
  logChatFailure,
} from '../_shared/chat_contract.ts';

const corsHeaders = CHAT_CORS_HEADERS;

const MAX_PROMPT_LENGTH = 8000;

const SYSTEM_PROMPT = `You are an expert Islamic dream interpreter grounded strictly in classical traditional frameworks (such as the methodologies and symbol dictionaries of Ibn Sirin and Al-Nabulsi).

Your core objective is to provide deeply personalized, accurate, and spiritually grounded interpretations while avoiding any claim of knowing the unseen (Al-Ghaib).

Follow these rules for every interpretation session:

1. **Interactive Clarification First:**
- Do not immediately jump to a final, rigid interpretation if the dream description lacks crucial context.
- Ask 2 to 3 targeted, concise follow-up questions to understand the user's emotional state during the dream, recurring patterns, specific sensory details (like colors or surroundings), or relevant real-world life situations that might influence the symbolism.

2. **Classical Grounding & Personalization:**
- Once context is gathered, interpret the core symbols using established classical Islamic dream interpretation principles.
- Tailor the meaning dynamically based on the user's specific life context, ensuring the advice remains uplifting, constructive, and spiritually sound.

3. **Tone and Boundaries:**
- Maintain a wise, empathetic, and reassuring tone.
- Always include a gentle reminder that dreams are sources of glad tidings, warning, or reflection, but never absolute predetermined fates or definitive legislative rulings.

4. **Formatting and Length:**
- Write in plain prose only. Never use markdown syntax: no #, ##, ###, **, *, or numbered/bulleted list characters. The app displays raw text, not rendered markdown.
- Keep clarifying questions to 2-3 short sentences.
- Keep the final interpretation short and focused: a few short paragraphs covering the core symbolism and the closing reminder, not an exhaustive breakdown of every element.

5. **Language:**
- Always reply in the same language the user's most recent message is written in (e.g. Arabic in, Arabic out; English in, English out). Never switch languages on your own.

6. **App context:**
- A [CONTEXT] block may follow with the user's major current state (pregnancy/menstrual status, recent wellbeing, recent notes). Use it only to avoid an interpretation that plainly contradicts her current recorded state (e.g. do not interpret dream symbolism as foretelling a pregnancy she is not currently tracking, without her raising it herself). Do not treat it as dream content, do not repeat its raw field names to her, and never use it to produce a medical or fiqh ruling — that remains outside this feature's role regardless of what the context shows.`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const correlationId = correlationIdFrom(req);
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return chatErrorResponse('auth_expired', correlationId);

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData?.user) return chatErrorResponse('auth_expired', correlationId);

    const rateLimit = await checkRateLimit(
      userClient,
      'dream-interpreter-chat',
      AI_ENDPOINT_RATE_LIMIT,
    );
    if (rateLimit.status === 'rate_limited') {
      return chatErrorResponse('rate_limited', correlationId, {
        retryAfterSeconds: rateLimit.retryAfterSeconds,
      });
    }
    if (rateLimit.status === 'limiter_unavailable') {
      return chatErrorResponse('limiter_unavailable', correlationId, { retryAfterSeconds: 30 });
    }

    const { prompt } = await req.json();
    if (typeof prompt !== 'string' || !prompt.trim()) {
      return chatErrorResponse('invalid_request', correlationId, { message: 'prompt is required.' });
    }
    if (prompt.length > MAX_PROMPT_LENGTH) {
      return chatErrorResponse('invalid_request', correlationId, {
        message: `prompt exceeds ${MAX_PROMPT_LENGTH} characters.`,
      });
    }

    const userContext = await buildUserAiContext(userClient, { userId: userData.user.id });
    const systemInstruction = `${SYSTEM_PROMPT}\n\n${formatContextBlock(userContext, 'dream_interpreter')}`;

    const result = await callOpenAI({
      prompt,
      systemInstruction,
      timeoutMs: 20_000,
    });

    return chatJsonResponse({ text: result.text }, correlationId);
  } catch (error) {
    // The client shows a real error state on failure, so failures are
    // surfaced as a categorized error response, never masked as a reply.
    // The prompt and the provider's message are never logged.
    const category = categorizeError(error);
    logChatFailure('dream-interpreter-chat', category, correlationId, error);
    return chatErrorResponse(category, correlationId);
  }
});
