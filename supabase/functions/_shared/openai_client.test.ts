import { assertEquals, assertRejects } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { callOpenAI } from './openai_client.ts';

// Stubs the global fetch used by callOpenAI() so these tests are
// deterministic and never touch the real network / never need a real
// OPENAI_API_KEY. Always restored in `finally`, even on assertion failure.
function withStubbedFetch<T>(
  impl: (input: string | URL | Request, init?: RequestInit) => Promise<Response>,
  run: () => Promise<T>,
): Promise<T> {
  const original = globalThis.fetch;
  // deno-lint-ignore no-explicit-any
  globalThis.fetch = impl as any;
  return run().finally(() => {
    globalThis.fetch = original;
  });
}

function withEnv<T>(vars: Record<string, string | undefined>, run: () => Promise<T>): Promise<T> {
  const previous: Record<string, string | undefined> = {};
  for (const key of Object.keys(vars)) previous[key] = Deno.env.get(key);
  for (const [key, value] of Object.entries(vars)) {
    if (value === undefined) Deno.env.delete(key);
    else Deno.env.set(key, value);
  }
  return run().finally(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  });
}

function okResponse(text: string): Response {
  return new Response(
    JSON.stringify({
      output: [
        { type: 'message', content: [{ type: 'output_text', text }] },
      ],
    }),
    { status: 200 },
  );
}

Deno.test('callOpenAI — throws a clear config error when OPENAI_API_KEY is missing', async () => {
  await withEnv({ OPENAI_API_KEY: undefined, OPENAI_MODEL: 'gpt-test' }, async () => {
    await assertRejects(
      () => callOpenAI({ prompt: 'hi', systemInstruction: 'be nice' }),
      Error,
      'OPENAI_API_KEY is not configured.',
    );
  });
});

Deno.test('callOpenAI — throws a clear config error when OPENAI_MODEL is missing (never assumes a hardcoded default)', async () => {
  await withEnv({ OPENAI_API_KEY: 'test-key', OPENAI_MODEL: undefined }, async () => {
    await assertRejects(
      () => callOpenAI({ prompt: 'hi', systemInstruction: 'be nice' }),
      Error,
      'OPENAI_MODEL is not configured.',
    );
  });
});

Deno.test('callOpenAI — calls the OpenAI Responses API endpoint with store:false and no hosted tools', async () => {
  await withEnv({ OPENAI_API_KEY: 'test-key', OPENAI_MODEL: 'gpt-test-model' }, async () => {
    let capturedUrl: string | URL | Request | undefined;
    let capturedBody: Record<string, unknown> | undefined;
    let capturedAuth: string | null | undefined;
    await withStubbedFetch(
      (input, init) => {
        capturedUrl = input;
        capturedBody = JSON.parse(String(init?.body));
        capturedAuth = (init?.headers as Record<string, string>)?.['Authorization'] ?? null;
        return Promise.resolve(okResponse('a real reply'));
      },
      () => callOpenAI({ prompt: 'What is the ruling?', systemInstruction: 'Stay in the KB.' }),
    );

    assertEquals(String(capturedUrl), 'https://api.openai.com/v1/responses');
    assertEquals(capturedBody?.model, 'gpt-test-model');
    assertEquals(capturedBody?.input, 'What is the ruling?');
    assertEquals(capturedBody?.instructions, 'Stay in the KB.');
    assertEquals(
      capturedBody?.store,
      false,
      'store:false is a hard product requirement -- no OpenAI-side conversation persistence',
    );
    assertEquals('tools' in (capturedBody ?? {}), false, 'no hosted tool (web_search/file_search/etc.) may ever be attached');
    assertEquals(capturedAuth, 'Bearer test-key');
  });
});

Deno.test('callOpenAI — never sends previous_response_id (no OpenAI-side conversation chaining)', async () => {
  await withEnv({ OPENAI_API_KEY: 'test-key', OPENAI_MODEL: 'gpt-test-model' }, async () => {
    let capturedBody: Record<string, unknown> | undefined;
    await withStubbedFetch(
      (_input, init) => {
        capturedBody = JSON.parse(String(init?.body));
        return Promise.resolve(okResponse('reply'));
      },
      () => callOpenAI({ prompt: 'hi', systemInstruction: 'sys' }),
    );
    assertEquals('previous_response_id' in (capturedBody ?? {}), false);
  });
});

Deno.test('callOpenAI — extracts output_text from the Responses API message shape', async () => {
  await withEnv({ OPENAI_API_KEY: 'test-key', OPENAI_MODEL: 'gpt-test-model' }, async () => {
    const result = await withStubbedFetch(
      () => Promise.resolve(okResponse('The knowledge base indicates...')),
      () => callOpenAI({ prompt: 'hi', systemInstruction: 'sys' }),
    );
    assertEquals(result.text, 'The knowledge base indicates...');
    assertEquals(result.model, 'gpt-test-model');
  });
});

Deno.test('callOpenAI — throws when the response contains no output_text (never silently returns empty)', async () => {
  await withEnv({ OPENAI_API_KEY: 'test-key', OPENAI_MODEL: 'gpt-test-model' }, async () => {
    await assertRejects(
      () =>
        withStubbedFetch(
          () => Promise.resolve(new Response(JSON.stringify({ output: [] }), { status: 200 })),
          () => callOpenAI({ prompt: 'hi', systemInstruction: 'sys' }),
        ),
      Error,
      'OpenAI returned no text.',
    );
  });
});

Deno.test('callOpenAI — 401 (invalid credentials) fails immediately, no retry', async () => {
  await withEnv({ OPENAI_API_KEY: 'bad-key', OPENAI_MODEL: 'gpt-test-model' }, async () => {
    let callCount = 0;
    await assertRejects(() =>
      withStubbedFetch(
        () => {
          callCount++;
          return Promise.resolve(
            new Response(JSON.stringify({ error: { message: 'Incorrect API key provided.' } }), { status: 401 }),
          );
        },
        () => callOpenAI({ prompt: 'hi', systemInstruction: 'sys' }),
      ),
    );
    assertEquals(callCount, 1, '401 must never be retried -- it is not a transient error');
  });
});

Deno.test('callOpenAI — 429 (rate limited) retries once with the same model, then fails', async () => {
  await withEnv({ OPENAI_API_KEY: 'test-key', OPENAI_MODEL: 'gpt-test-model' }, async () => {
    let callCount = 0;
    const models: string[] = [];
    await assertRejects(() =>
      withStubbedFetch(
        (_input, init) => {
          callCount++;
          models.push(JSON.parse(String(init?.body)).model);
          return Promise.resolve(
            new Response(JSON.stringify({ error: { message: 'Rate limit exceeded' } }), { status: 429 }),
          );
        },
        () => callOpenAI({ prompt: 'hi', systemInstruction: 'sys', maxRetries: 1 }),
      ),
    );
    assertEquals(callCount, 2, 'exactly one retry (maxRetries:1 => 2 total attempts)');
    assertEquals(models, ['gpt-test-model', 'gpt-test-model'], 'retries the SAME configured model, never switches');
  });
});

Deno.test('callOpenAI — a transient error followed by success returns the successful result', async () => {
  await withEnv({ OPENAI_API_KEY: 'test-key', OPENAI_MODEL: 'gpt-test-model' }, async () => {
    let callCount = 0;
    const result = await withStubbedFetch(
      () => {
        callCount++;
        if (callCount === 1) {
          return Promise.resolve(new Response(JSON.stringify({ error: {} }), { status: 503 }));
        }
        return Promise.resolve(okResponse('recovered reply'));
      },
      () => callOpenAI({ prompt: 'hi', systemInstruction: 'sys', maxRetries: 1 }),
    );
    assertEquals(result.text, 'recovered reply');
    assertEquals(callCount, 2);
  });
});

Deno.test('callOpenAI — a network-level fetch failure (TypeError) is classified and fails safely, not thrown raw', async () => {
  await withEnv({ OPENAI_API_KEY: 'test-key', OPENAI_MODEL: 'gpt-test-model' }, async () => {
    await assertRejects(
      () =>
        withStubbedFetch(
          () => Promise.reject(new TypeError('fetch failed')),
          () => callOpenAI({ prompt: 'hi', systemInstruction: 'sys', maxRetries: 0 }),
        ),
      Error,
      'OpenAI request failed: network error.',
    );
  });
});
