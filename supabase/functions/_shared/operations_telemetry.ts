// Content-free operational metrics. No user ID, prompt, response, health state,
// request URL, headers, or arbitrary metadata is accepted by this module.
export type Advisor =
  | "ai-assistant-chat"
  | "dr-niswah-chat"
  | "fiqh-advisor-chat"
  | "dream-interpreter-chat";
export interface AiMetric {
  advisor: Advisor;
  kind: "endpoint" | "model";
  status: number;
  duration_ms: number;
  model?: string;
  input_tokens?: number;
  output_tokens?: number;
}
const tokenCount = (v: unknown) =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0 ? v : undefined;
export function metricPayload(event: AiMetric): AiMetric {
  return {
    advisor: event.advisor,
    kind: event.kind,
    status: event.status,
    duration_ms: Math.min(300000, Math.max(0, Math.round(event.duration_ms))),
    ...(event.kind === "model"
      ? {
        model: event.model?.slice(0, 100),
        input_tokens: tokenCount(event.input_tokens),
        output_tokens: tokenCount(event.output_tokens),
      }
      : {}),
  };
}
async function sendMetric(event: AiMetric): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 1500);
  try {
    const response = await fetch(`${url}/rest/v1/rpc/record_ai_operation`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: key,
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({ p_event: metricPayload(event) }),
      signal: controller.signal,
    });
    // Never log response bodies (including error details) or retry on the user path.
    await response.body?.cancel();
  } catch {
    /* Monitoring must never change the advisor response. */
  } finally {
    clearTimeout(timer);
  }
}
export function emitMetric(event: AiMetric): Promise<void> {
  const task = sendMetric(event);
  const runtime = (globalThis as unknown as {
    EdgeRuntime?: { waitUntil: (p: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (runtime) {
    try {
      runtime.waitUntil(task);
      return Promise.resolve();
    } catch { /* Fall back to bounded write. */ }
  }
  return task;
}
export function observeAiEndpoint(
  advisor: Advisor,
  handler: (req: Request) => Promise<Response>,
) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return handler(req);
    const started = performance.now();
    let status = 500;
    try {
      const response = await handler(req);
      status = response.status;
      return response;
    } finally {
      await emitMetric({
        advisor,
        kind: "endpoint",
        status,
        duration_ms: performance.now() - started,
      });
    }
  };
}
