import {
  assert as ok,
  assertEquals as deepStrictEqual,
  assertEquals as strictEqual,
  assertRejects as rejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  emitMetric,
  metricPayload,
  observeAiEndpoint,
} from "./operations_telemetry.ts";
import { callOpenAI } from "./openai_client.ts";

async function withTransport(
  run: (events: Record<string, unknown>[]) => Promise<void>,
  fail = false,
) {
  const original = globalThis.fetch;
  const keys = [
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "OPENAI_API_KEY",
    "OPENAI_MODEL",
  ];
  const previous = keys.map((k) => Deno.env.get(k));
  Deno.env.set("SUPABASE_URL", "https://test.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-test-key");
  Deno.env.set("OPENAI_API_KEY", "synthetic-openai-key");
  Deno.env.set("OPENAI_MODEL", "synthetic-model");
  const events: Record<string, unknown>[] = [];
  globalThis.fetch = async (input, init) => {
    if (String(input) === "https://api.openai.com/v1/responses") {
      return new Response(
        JSON.stringify({
          output: [{
            type: "message",
            content: [{ type: "output_text", text: "Synthetic reply" }],
          }],
          usage: { input_tokens: 12, output_tokens: 4 },
        }),
        { status: 200 },
      );
    }
    events.push(JSON.parse(String(init?.body)).p_event);
    if (fail) throw new Error("Synthetic telemetry outage");
    return new Response(null, { status: 204 });
  };
  try {
    await run(events);
  } finally {
    globalThis.fetch = original;
    keys.forEach((k, i) =>
      previous[i] === undefined
        ? Deno.env.delete(k)
        : Deno.env.set(k, previous[i]!)
    );
  }
}
Deno.test("metrics reject extra content by reconstructing an explicit payload", () => {
  const unsafe = {
    advisor: "dr-niswah-chat" as const,
    kind: "model" as const,
    status: 200,
    duration_ms: 9.8,
    input_tokens: -1,
    output_tokens: 4,
    prompt: "private content",
    user_id: "private ID",
  };
  const payload = metricPayload(unsafe);
  strictEqual(payload.duration_ms, 10);
  strictEqual(payload.input_tokens, undefined);
  strictEqual(payload.output_tokens, 4);
  ok(!("prompt" in payload));
  ok(!("user_id" in payload));
});
Deno.test("endpoint metric preserves response and never records request content", () =>
  withTransport(async (events) => {
    const response = await observeAiEndpoint(
      "dr-niswah-chat",
      async () => new Response("Synthetic fallback", { status: 200 }),
    )(
      new Request("https://app.invalid/chat", {
        method: "POST",
        body: "private prompt",
      }),
    );
    strictEqual(await response.text(), "Synthetic fallback");
    strictEqual(events.length, 1);
    deepStrictEqual(Object.keys(events[0]).sort(), [
      "advisor",
      "duration_ms",
      "kind",
      "status",
    ]);
    strictEqual(events[0].status, 200);
  }));
Deno.test("OPTIONS ignored, rejected and thrown endpoint outcomes measured", () =>
  withTransport(async (events) => {
    await observeAiEndpoint(
      "ai-assistant-chat",
      async () => new Response("ok"),
    )(new Request("https://app.invalid", { method: "OPTIONS" }));
    strictEqual(events.length, 0);
    await observeAiEndpoint(
      "ai-assistant-chat",
      async () => new Response(null, { status: 429 }),
    )(new Request("https://app.invalid"));
    await rejects(() =>
      observeAiEndpoint("ai-assistant-chat", async () => {
        throw new Error("private diagnostic");
      })(new Request("https://app.invalid"))
    );
    deepStrictEqual(events.map((e) => e.status), [429, 500]);
  }));
Deno.test("telemetry failure does not alter application response", () =>
  withTransport(async () => {
    const response = await observeAiEndpoint(
      "ai-assistant-chat",
      async () => new Response("ok"),
    )(new Request("https://app.invalid"));
    strictEqual(await response.text(), "ok");
    await emitMetric({
      advisor: "ai-assistant-chat",
      kind: "endpoint",
      status: 200,
      duration_ms: 1,
    });
  }, true));
Deno.test("model outcome records reported token counts without prompt or response", () =>
  withTransport(async (events) => {
    const r = await callOpenAI({
      advisor: "ai-assistant-chat",
      prompt: "private prompt",
      systemInstruction: "private instructions",
    });
    strictEqual(r.text, "Synthetic reply");
    strictEqual(events.length, 1);
    strictEqual(events[0].kind, "model");
    strictEqual(events[0].input_tokens, 12);
    strictEqual(events[0].output_tokens, 4);
    ok(!JSON.stringify(events).includes("private"));
    ok(!JSON.stringify(events).includes("Synthetic reply"));
  }));
Deno.test("model failures are recorded independently of any endpoint fallback", () =>
  withTransport(async (events) => {
    Deno.env.delete("OPENAI_API_KEY");
    await rejects(() =>
      callOpenAI({
        advisor: "dr-niswah-chat",
        prompt: "private prompt",
        systemInstruction: "private instructions",
      })
    );
    strictEqual(events.length, 1);
    strictEqual(events[0].kind, "model");
    strictEqual(events[0].status, 500);
    ok(!JSON.stringify(events).includes("private"));
    ok(!("input_tokens" in events[0]));
  }));
