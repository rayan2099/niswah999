// Supabase Edge Function: ai-assistant-chat
//
// Server-side home for the general-assistant chat thread type's Gemini call,
// moved off the client per the Gemini trust-boundary remediation (closes
// SEC-001/AB-002 for this feature). The system prompt is owned here — the
// client sends only the current message (this thread type has never
// resent conversation history; unchanged).
//
// AICTX remediation (2026-09-09): previously sent ZERO user-state context —
// the exact "isolated chatbot" failure mode the audit's charter names
// explicitly (AICTX-1). Now builds the same canonical context every other
// AI feature uses, scoped to 'general_assistant' — major shared facts
// only, per Phase D's "minimum relevant context necessary" rule.

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

const GEMINI_MODELS = ['gemini-3.5-flash-lite', 'gemini-3.6-flash'];
const MAX_CONTENT_LENGTH = 4000;

const SYSTEM_PROMPT = `You are Niswah AI, a concise and supportive general assistant. Do not provide medical diagnoses or definitive religious rulings; direct those questions to the dedicated advisors.
Always reply in the same language the user's message is written in.
Write in plain prose only. Never use markdown syntax: no #, ##, ###, **, *, or numbered/bulleted list characters. The app displays raw text, not rendered markdown.

A [CONTEXT] block with the user's current major app state (pregnancy, menstrual history, selected madhhab/fiqh state, recent wellbeing, recent notes) is included with every message. Use it only to avoid contradicting or ignoring a currently-recorded state (e.g. do not respond as though she is pregnant when the context says she is not, or ignore a recorded low-mood entry if she asks something related). Do not repeat the block's raw field names to the user, do not treat notes as verified facts, and do not attempt a medical or religious ruling yourself — defer those, as instructed above, to the dedicated advisors even when the context makes the situation clearer.`;

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
      'ai-assistant-chat',
      AI_ENDPOINT_RATE_LIMIT,
    );
    if (rateLimit.status === 'rate_limited') {
      return rateLimitedResponse(rateLimit.retryAfterSeconds, corsHeaders);
    }
    if (rateLimit.status === 'limiter_unavailable') {
      return limiterUnavailableResponse(corsHeaders);
    }

    const { content, madhhab, madhhab_state: madhhabState, clientFiqhState } = await req.json();
    if (typeof content !== 'string' || !content.trim()) {
      return new Response(JSON.stringify({ error: 'content is required.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (content.length > MAX_CONTENT_LENGTH) {
      return new Response(
        JSON.stringify({ error: `content exceeds ${MAX_CONTENT_LENGTH} characters.` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // madhhab/madhhab_state/clientFiqhState are all optional — older client
    // builds that don't send them yet simply get 'not_provided'/'unset'
    // fields in the context, never a guessed value (Fiqh Remediation Wave
    // 1, Section F).
    const userContext = await buildUserAiContext(userClient, {
      clientMadhhab: typeof madhhab === 'string' ? madhhab : null,
      clientMadhhabState: typeof madhhabState === 'string' ? madhhabState : null,
      clientFiqhState: typeof clientFiqhState === 'string' ? clientFiqhState : null,
    });
    const systemInstruction = `${SYSTEM_PROMPT}\n\n${formatContextBlock(userContext, 'general_assistant')}`;

    const result = await callGemini({
      models: GEMINI_MODELS,
      prompt: content,
      systemInstruction,
      timeoutMs: 20_000,
    });

    return new Response(JSON.stringify({ text: result.text }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('ai-assistant-chat: request failed', {
      error: error instanceof Error ? error.message : String(error),
    });
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error.' }),
      { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
