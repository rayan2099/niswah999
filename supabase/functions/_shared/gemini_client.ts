// Shared Gemini caller for every AI-backed Edge Function. Factored out of
// dr-niswah-chat's original inline implementation so the four functions that
// need it (dr-niswah-chat, fiqh-advisor-chat, dream-interpreter-chat,
// ai-assistant-chat) share one tested timeout/model-fallback/parsing path
// instead of four independently-drifting copies.
//
// Endpoint/model/request-shape confirmed live and functional via a
// controlled smoke test (see production-readiness-results/master/00_05
// Phase 0 §UNK-001) — this is not a documented-but-unverified guess.

const GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/interactions';

export interface GeminiCitation {
  url: string;
  title: string;
  startIndex: number;
  endIndex: number;
}

export interface GeminiCallResult {
  text: string;
  citations: GeminiCitation[];
}

export interface GeminiCallOptions {
  models: string[];
  prompt: string;
  systemInstruction: string;
  useGoogleSearch?: boolean;
  /** Per-attempt timeout in milliseconds. */
  timeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 20_000;

/**
 * Calls Gemini's `/v1beta/interactions` endpoint, trying each model in
 * `models` in order (matching the client's original transient-failure
 * fallback behavior: 429/500/503 moves on to the next model; anything else
 * throws immediately). Each attempt is bounded by `timeoutMs` via
 * AbortController so a slow/hung upstream call can't hold the function open
 * indefinitely (AB-004).
 */
export async function callGemini(options: GeminiCallOptions): Promise<GeminiCallResult> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) throw new Error('GEMINI_API_KEY is not configured.');

  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  let lastError: unknown;

  for (const model of options.models) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(GEMINI_ENDPOINT, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify({
          model,
          input: options.prompt,
          system_instruction: options.systemInstruction,
          ...(options.useGoogleSearch
            ? { tools: [{ type: 'google_search' }] }
            : {}),
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
      const blocks: Array<{ text?: string; annotations?: unknown[] }> = [
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

      const citations: GeminiCitation[] = [];
      for (const block of blocks) {
        for (const raw of block.annotations ?? []) {
          const annotation = raw as Record<string, unknown>;
          if (annotation.type !== 'url_citation') continue;
          const url = String(annotation.url ?? '');
          if (!url) continue;
          citations.push({
            url,
            title: String(annotation.title ?? new URL(url).host),
            startIndex: Number(annotation.start_index ?? 0),
            endIndex: Number(annotation.end_index ?? 0),
          });
        }
      }

      return { text, citations };
    } catch (error) {
      lastError = error instanceof DOMException && error.name === 'AbortError'
        ? new Error(`Gemini request timed out after ${timeoutMs}ms.`)
        : error;
    } finally {
      clearTimeout(timer);
    }
  }

  throw lastError instanceof Error ? lastError : new Error('Gemini request failed.');
}
