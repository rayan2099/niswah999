// Shared OpenAI Responses API caller for every AI-backed Edge Function.
//
// Provider Migration (2026-09-30): Niswah's production LLM provider is
// OpenAI, not Gemini. This module replaces gemini_client.ts (removed from
// the active runtime path) as the single call site all four AI-backed
// functions (dr-niswah-chat, fiqh-advisor-chat, ai-assistant-chat,
// dream-interpreter-chat) share, so provider logic is not duplicated four
// times. See production-readiness-results/knowledge-base/
// OPENAI_REAL_MODEL_ACCEPTANCE_REPORT.md for the migration record.
// Historical reports that predate this migration and mention Gemini remain
// historically accurate and are not rewritten.
//
// This module is a generation layer ONLY:
//   - it never determines authoritative medical/Fiqh facts;
//   - it never originates citations -- those come exclusively from the
//     canonical KB via kb_retrieval.ts's citationPayload(), never from
//     anything this module returns;
//   - it is never given a hosted tool (no web_search, no file_search, no
//     computer_use) -- the Niswah KB is the only retrieval source for
//     production answers, enforced by never sending a `tools` field here.
//   - every request explicitly sends `store: false` -- no OpenAI-side
//     conversation persistence, no `previous_response_id` chaining.

const OPENAI_ENDPOINT = 'https://api.openai.com/v1/responses';
const DEFAULT_TIMEOUT_MS = 20_000;
const DEFAULT_MAX_RETRIES = 1;

export interface OpenAiCallOptions {
  prompt: string;
  systemInstruction: string;
  /** Per-attempt timeout in milliseconds. */
  timeoutMs?: number;
  /** Retries on a transient (429/500/502/503) error, same model, before giving up. */
  maxRetries?: number;
}

export interface OpenAiCallResult {
  text: string;
  /** The model that actually produced this result -- for sanitized diagnostics only, never shown to the end user. */
  model: string;
  /** Non-sensitive token counts as reported by the Responses API, when present. */
  usage?: { inputTokens?: number; outputTokens?: number };
}

type ErrorCategory =
  | 'invalid_credentials'
  | 'permission_denied'
  | 'rate_limited'
  | 'model_unavailable'
  | 'context_length_exceeded'
  | 'bad_request'
  | 'server_error'
  | 'timeout'
  | 'network_error'
  | 'empty_response'
  | 'malformed_response'
  | 'unknown';

function classifyStatus(status: number, errorBody: { error?: { code?: string; type?: string } } | null): ErrorCategory {
  if (status === 401) return 'invalid_credentials';
  if (status === 403) return 'permission_denied';
  if (status === 404) return 'model_unavailable';
  if (status === 429) return 'rate_limited';
  if (status >= 500) return 'server_error';
  if (status === 400) {
    const code = errorBody?.error?.code ?? '';
    if (code.includes('context_length') || code.includes('token')) return 'context_length_exceeded';
    return 'bad_request';
  }
  return 'unknown';
}

const RETRYABLE: ReadonlySet<ErrorCategory> = new Set(['rate_limited', 'server_error']);

// A non-retryable failure (bad credentials, permission denied, model
// unavailable, malformed/empty response, etc.) must break out of the retry
// loop on the first occurrence, not fall through to another attempt. Thrown
// from inside the per-attempt `try` and caught by this module's own
// `catch (error)` below -- without this marker, that catch would swallow
// the throw into `lastError` and let the loop continue anyway, silently
// retrying an error class that was never supposed to be retried. (Found by
// openai_client.test.ts's 401 test during the OpenAI provider migration.)
class NonRetryableOpenAiError extends Error {}

/**
 * Calls OpenAI's `/v1/responses` endpoint with the configured model
 * (`OPENAI_MODEL`, required -- never a hardcoded guess: Phase 9 of the
 * provider migration verified the configured model is actually available to
 * this API project before it was relied on here). Retries the same model on
 * a transient (429/5xx) error, matching the bounded-retry spirit of the
 * prior Gemini client's model-fallback behavior, but without switching
 * models (OpenAI has no documented equivalent "try a cheaper model next"
 * fallback list for this integration).
 */
export async function callOpenAI(options: OpenAiCallOptions): Promise<OpenAiCallResult> {
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  if (!apiKey) throw new Error('OPENAI_API_KEY is not configured.');
  const model = Deno.env.get('OPENAI_MODEL');
  if (!model) throw new Error('OPENAI_MODEL is not configured.');

  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const maxAttempts = 1 + Math.max(0, options.maxRetries ?? DEFAULT_MAX_RETRIES);
  let lastError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(OPENAI_ENDPOINT, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          // Never logged, never echoed back in any response or error path.
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model,
          input: options.prompt,
          instructions: options.systemInstruction,
          store: false,
        }),
      });

      if (!response.ok) {
        const errorBody = await response.json().catch(() => null);
        const category = classifyStatus(response.status, errorBody);
        // Sanitized diagnostic log only: status + classified category +
        // model + OpenAI's own error code/type. Never the request body,
        // never the prompt/system instruction, never the Authorization
        // header, never the API key.
        console.error('callOpenAI: upstream error', {
          model,
          status: response.status,
          category,
          errorCode: errorBody?.error?.code ?? null,
          errorType: errorBody?.error?.type ?? null,
        });
        if (RETRYABLE.has(category) && attempt < maxAttempts) {
          lastError = new Error(`OpenAI request failed (${response.status}: ${category}).`);
          continue;
        }
        throw new NonRetryableOpenAiError(
          errorBody?.error?.message ?? `OpenAI request failed (${response.status}: ${category}).`,
        );
      }

      const decoded = await response.json();
      // The Responses API's `output` is an array of items; a message
      // item's `content` array holds `output_text` parts. Parsed
      // defensively -- this is an external API's JSON shape, not a
      // contract this codebase owns.
      const messageItems = (
        (decoded.output ?? []) as Array<{ type?: string; content?: unknown[] }>
      ).filter((item) => item.type === 'message');
      const text = messageItems
        .flatMap((item) => (item.content ?? []) as Array<{ type?: string; text?: string }>)
        .filter((part) => part.type === 'output_text')
        .map((part) => part.text ?? '')
        .filter(Boolean)
        .join('\n')
        .trim();

      if (!text) {
        console.error('callOpenAI: empty response text', { model });
        throw new NonRetryableOpenAiError('OpenAI returned no text.');
      }

      // Token counts only -- never the prompt/response content itself.
      const rawUsage = decoded.usage as { input_tokens?: number; output_tokens?: number } | undefined;
      const usage = rawUsage
        ? { inputTokens: rawUsage.input_tokens, outputTokens: rawUsage.output_tokens }
        : undefined;
      if (usage) {
        console.log('callOpenAI: usage', { model, ...usage });
      }

      return { text, model, usage };
    } catch (error) {
      if (error instanceof NonRetryableOpenAiError) {
        // `finally` below still runs (clears the timer) before this
        // propagates out of the loop entirely.
        throw error;
      }
      if (error instanceof DOMException && error.name === 'AbortError') {
        lastError = new Error(`OpenAI request timed out after ${timeoutMs}ms.`);
      } else if (error instanceof TypeError) {
        // fetch() throws a bare TypeError for network-level failures (DNS,
        // connection refused, etc.) -- classified explicitly so it isn't
        // confused with a parsing bug in this module's own code.
        console.error('callOpenAI: network error', { model, message: error.message });
        lastError = new Error('OpenAI request failed: network error.');
      } else {
        lastError = error;
      }
    } finally {
      clearTimeout(timer);
    }
  }

  throw lastError instanceof Error ? lastError : new Error('OpenAI request failed.');
}
