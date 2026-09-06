// Supabase Edge Function: dream-interpreter-chat
//
// Server-side home for the Dream Interpreter's Gemini call, moved off the
// client per the Gemini trust-boundary remediation (closes SEC-001/AB-002
// for this feature). The system prompt is owned here; the client sends only
// the already-assembled conversation transcript (Gemini's /interactions
// endpoint has no history field of its own, so the client still resends the
// whole transcript each turn — unchanged behavior, just relocated).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
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
- Always reply in the same language the user's most recent message is written in (e.g. Arabic in, Arabic out; English in, English out). Never switch languages on your own.`;

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
      'dream-interpreter-chat',
      AI_ENDPOINT_RATE_LIMIT,
    );
    if (rateLimit.status === 'rate_limited') {
      return rateLimitedResponse(rateLimit.retryAfterSeconds, corsHeaders);
    }
    if (rateLimit.status === 'limiter_unavailable') {
      return limiterUnavailableResponse(corsHeaders);
    }

    const { prompt } = await req.json();
    if (typeof prompt !== 'string' || !prompt.trim()) {
      return new Response(JSON.stringify({ error: 'prompt is required.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (prompt.length > MAX_PROMPT_LENGTH) {
      return new Response(
        JSON.stringify({ error: `prompt exceeds ${MAX_PROMPT_LENGTH} characters.` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const result = await callGemini({
      models: GEMINI_MODELS,
      prompt,
      systemInstruction: SYSTEM_PROMPT,
      timeoutMs: 20_000,
    });

    return new Response(JSON.stringify({ text: result.text }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('dream-interpreter-chat: request failed', {
      error: error instanceof Error ? error.message : String(error),
    });
    // Unlike dr-niswah-chat/fiqh-advisor-chat, this feature has no graceful
    // fallback-text UX today — the client shows a real error state on
    // failure — so failures are surfaced as an error response, not masked.
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error.' }),
      { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
