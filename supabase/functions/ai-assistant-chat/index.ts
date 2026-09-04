// Supabase Edge Function: ai-assistant-chat
//
// Server-side home for the general-assistant chat thread type's Gemini call,
// moved off the client per the Gemini trust-boundary remediation (closes
// SEC-001/AB-002 for this feature). The system prompt is owned here — the
// client sends only the current message (this thread type has never
// resent conversation history; unchanged).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { callGemini } from '../_shared/gemini_client.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const GEMINI_MODELS = ['gemini-3.5-flash-lite', 'gemini-3.6-flash'];
const MAX_CONTENT_LENGTH = 4000;

const SYSTEM_PROMPT = `You are Niswah AI, a concise and supportive general assistant. Do not provide medical diagnoses or definitive religious rulings; direct those questions to the dedicated advisors.
Always reply in the same language the user's message is written in.
Write in plain prose only. Never use markdown syntax: no #, ##, ###, **, *, or numbered/bulleted list characters. The app displays raw text, not rendered markdown.`;

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

    const { content } = await req.json();
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

    const result = await callGemini({
      models: GEMINI_MODELS,
      prompt: content,
      systemInstruction: SYSTEM_PROMPT,
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
