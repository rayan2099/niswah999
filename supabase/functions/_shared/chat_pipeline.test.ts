// End-to-end tests of the three conversational chat handlers (TestFlight
// Feedback 2, 2026-10-31) against a fake Supabase and a fake OpenAI. They
// pin the causes found, not wording:
//   - no library match no longer short-circuits to a fixed reply: the model
//     is called and its answer returned, marked as AI-generated;
//   - only the library items the answer used are cited, never all of them;
//   - the safety-escalation library is searched only for urgent messages
//     or questions about warning signs;
//   - the fiqh advisor answers without a madhhab and for unresolved state;
//   - handoffs never point back at the chat she came from;
//   - auth, rate limits and the urgent path are unchanged.
// A mocked model proves the pipeline, never answer quality: that is what
// _evals/live_eval.ts is for.

import { assert, assertEquals, assertStringIncludes } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { EXPECTED_SNAPSHOT_COMMIT, type KnowledgeHit } from './kb_retrieval.ts';

const SUPABASE_URL = 'https://fake-project.supabase.co';
Deno.env.set('SUPABASE_URL', SUPABASE_URL);
Deno.env.set('SUPABASE_ANON_KEY', 'anon-key');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'service-role-key');
Deno.env.set('OPENAI_API_KEY', 'sk-test');
Deno.env.set('OPENAI_MODEL', 'test-model');

type Handler = (req: Request) => Promise<Response>;
const handlers: Record<string, Handler> = {};

// Literal specifiers, so they are part of the module graph and the test
// needs no file-read permission (CI runs `deno test --allow-env`).
const IMPORTS: Record<string, () => Promise<unknown>> = {
  'dr-niswah-chat': () => import('../dr-niswah-chat/index.ts'),
  'fiqh-advisor-chat': () => import('../fiqh-advisor-chat/index.ts'),
  'ai-assistant-chat': () => import('../ai-assistant-chat/index.ts'),
};

async function load(name: string): Promise<Handler> {
  if (handlers[name]) return handlers[name];
  const realServe = Deno.serve;
  let captured: Handler | null = null;
  // deno-lint-ignore no-explicit-any
  (Deno as any).serve = (handler: Handler) => {
    captured = handler;
    return { finished: Promise.resolve(), shutdown: () => Promise.resolve() };
  };
  try {
    await IMPORTS[name]();
  } finally {
    // deno-lint-ignore no-explicit-any
    (Deno as any).serve = realServe;
  }
  if (!captured) throw new Error(`${name} did not call Deno.serve`);
  handlers[name] = captured;
  return captured;
}

interface World {
  hits: Partial<Record<'HEALTH' | 'SAFETY_ESCALATION' | 'FIQH', KnowledgeHit[]>>;
  modelText: string;
  rateAllowed?: boolean;
  authOk?: boolean;
}

interface Recorded {
  retrievals: { domain: string; madhhab: string | null }[];
  modelCalls: { instructions: string; input: string }[];
  inserts: { table: string; body: unknown }[];
}

function hit(key: string, domain: KnowledgeHit['domain'], url: string): KnowledgeHit {
  return {
    knowledge_key: key,
    version_id: `v-${key}`,
    domain,
    category: null,
    topic: null,
    madhhab: domain === 'FIQH' ? 'hanbali' : null,
    content_language: 'ar',
    canonical_statement: `statement ${key}`,
    qualification_note: null,
    safety_class: null,
    human_review_status: 'NOT_REVIEWED',
    source_key: `SRC-${key}`,
    source_title: `Title ${key}`,
    locator: 'p1',
    source_url: url,
    rank_score: 0.5,
  };
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

function install(world: World): Recorded {
  const rec: Recorded = { retrievals: [], modelCalls: [], inserts: [] };
  globalThis.fetch = async (input: string | URL | Request, init?: RequestInit) => {
    const req = input instanceof Request ? input : new Request(input.toString(), init);
    const url = new URL(req.url);
    const bodyText = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
    const body = bodyText ? JSON.parse(bodyText) : null;

    if (url.hostname === 'api.openai.com') {
      rec.modelCalls.push({ instructions: body.instructions, input: body.input });
      return json({
        output: [{ type: 'message', content: [{ type: 'output_text', text: world.modelText }] }],
        usage: { input_tokens: 1, output_tokens: 1 },
      });
    }
    if (url.pathname === '/auth/v1/user') {
      return world.authOk === false
        ? json({ message: 'invalid' }, 401)
        : json({ id: 'user-1', aud: 'authenticated', role: 'authenticated', email: 'eval@example.com' });
    }
    if (url.pathname === '/rest/v1/rpc/check_and_increment_ai_rate_limit') {
      return json([{ allowed: world.rateAllowed !== false, retry_after_seconds: 30 }]);
    }
    if (url.pathname === '/rest/v1/rpc/retrieve_knowledge_v1') {
      rec.retrievals.push({ domain: body.p_domain, madhhab: body.p_madhhab });
      return json(world.hits[body.p_domain as 'HEALTH'] ?? []);
    }
    if (url.pathname === '/rest/v1/rpc/get_active_kb_snapshot') {
      return json([{ commit_sha: EXPECTED_SNAPSHOT_COMMIT }]);
    }
    if (url.pathname.startsWith('/rest/v1/')) {
      const table = url.pathname.slice('/rest/v1/'.length);
      if (req.method === 'POST') {
        rec.inserts.push({ table, body });
        const accept = req.headers.get('Accept') ?? '';
        return accept.includes('vnd.pgrst.object') ? json({ id: 'assistant-1' }, 201) : json([{ id: 'row-1' }], 201);
      }
      return json([]);
    }
    throw new Error(`unexpected fetch ${req.method} ${req.url}`);
  };
  return rec;
}

function post(body: Record<string, unknown>): Request {
  return new Request('http://localhost/', {
    method: 'POST',
    headers: { Authorization: 'Bearer user-jwt', 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

const THREAD = '6f1c2f43-3c2b-4b44-9d71-2f0f9a0c1a11';
const realFetch = globalThis.fetch;
const quietly = async <T>(fn: () => Promise<T>): Promise<T> => {
  const err = console.error;
  console.error = () => {};
  try {
    return await fn();
  } finally {
    console.error = err;
    globalThis.fetch = realFetch;
  }
};

// ---------------------------------------------------------------------------
// Doctor Niswah
// ---------------------------------------------------------------------------

Deno.test('dr-niswah — no library match: the model answers, marked AI-generated, no sources', () =>
  quietly(async () => {
    const handler = await load('dr-niswah-chat');
    const rec = install({
      hits: {},
      modelText: 'الجماع أثناء الدورة ليس ضارًا صحيًا في الغالب...\n[[topic: health]]\n[[verify: no]]\n[[used: none]]',
    });
    const res = await handler(post({ threadId: THREAD, content: 'هل الجماع وقت الدورة له أضرار؟' }));
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(rec.modelCalls.length, 1, 'the model must be called even with no library match');
    assertStringIncludes(body.reply, 'الجماع أثناء الدورة');
    assert(!body.reply.includes('[['), 'markers are stripped');
    assertEquals(body.citations, []);
    assertEquals(body.knowledgeGrounded, false);
    assertEquals(body.notice, { aiGenerated: true, verify: null, topic: 'health' });
    assertEquals(body.kind, 'general');
  }));

Deno.test('dr-niswah — safety library is not searched for an ordinary question, and unused items are not cited', () =>
  quietly(async () => {
    const handler = await load('dr-niswah-chat');
    const rec = install({
      hits: {
        HEALTH: [
          hit('HL-1', 'HEALTH', 'https://www.nhs.uk/periods'),
          hit('HL-2', 'HEALTH', 'https://www.womenshealth.gov/x'),
        ],
        SAFETY_ESCALATION: [hit('SF-1', 'SAFETY_ESCALATION', 'https://www.cdc.gov/hearher/maternal-warning-signs')],
      },
      modelText: 'اللون الأحمر الغامق غالبًا دم أقدم...\n[[topic: health]]\n[[verify: no]]\n[[used: HL-1]]',
    });
    const res = await handler(post({ threadId: THREAD, content: 'ما علاج اللون الأحمر الغامق للدم؟' }));
    const body = await res.json();
    assertEquals(rec.retrievals.map((r) => r.domain), ['HEALTH']);
    assertEquals(body.citations.map((c: { knowledgeKey: string }) => c.knowledgeKey), ['HL-1']);
    assertEquals(body.notice.aiGenerated, false);
    assertEquals(body.kind, 'grounded');
    // The retrieved-but-unused item never reaches the instructions as "the
    // only source": the prompt allows general knowledge.
    assertStringIncludes(rec.modelCalls[0].instructions, 'answer from well-established general knowledge');
  }));

Deno.test('dr-niswah — a missing [[used:]] line cites nothing (it used to cite every retrieved item)', () =>
  quietly(async () => {
    const handler = await load('dr-niswah-chat');
    install({
      hits: { HEALTH: [hit('HL-1', 'HEALTH', 'https://www.nhs.uk/periods')] },
      modelText: 'إجابة بلا أسطر وصفية',
    });
    const body = await (await handler(post({ threadId: THREAD, content: 'هل الدورة تتأثر بالتوتر؟' }))).json();
    assertEquals(body.citations, []);
    assertEquals(body.notice.aiGenerated, true, 'falls back to the health topic, never unmarked');
  }));

Deno.test('dr-niswah — urgent message: banner first, safety library searched, never rate limited', () =>
  quietly(async () => {
    const handler = await load('dr-niswah-chat');
    const rec = install({
      hits: { SAFETY_ESCALATION: [hit('SF-1', 'SAFETY_ESCALATION', 'https://www.cdc.gov/x')] },
      modelText: 'اذهبي للطوارئ الآن...\n[[topic: health]]\n[[verify: no]]\n[[used: SF-1]]',
      rateAllowed: false,
    });
    const body = await (await handler(post({ threadId: THREAD, content: 'انا حامل وعندي نزيف' }))).json();
    assertEquals(body.urgent, true);
    assert(body.reply.startsWith('قد يكون هذا من علامات الخطر'));
    assert(rec.retrievals.some((r) => r.domain === 'SAFETY_ESCALATION'));
    assert(rec.inserts.some((i) => i.table === 'flagged_conversations'));
  }));

Deno.test('dr-niswah — a greeting is answered by the model with no retrieval and no notice', () =>
  quietly(async () => {
    const handler = await load('dr-niswah-chat');
    const rec = install({ hits: {}, modelText: 'وعليكم السلام، أهلًا بكِ.\n[[topic: social]]\n[[verify: no]]\n[[used: none]]' });
    const body = await (await handler(post({ threadId: THREAD, content: 'السلام عليكم' }))).json();
    assertEquals(rec.retrievals.length, 0);
    assertEquals(rec.modelCalls.length, 1);
    assertEquals(body.notice.aiGenerated, false);
    assertEquals(body.citations, []);
  }));

Deno.test('dr-niswah — a handoff back to the chat she came from is dropped', () =>
  quietly(async () => {
    const handler = await load('dr-niswah-chat');
    install({ hits: {}, modelText: 'جواب\n[[topic: health]]\n[[route: fiqh]]' });
    const sentBack = await (await handler(post({ threadId: THREAD, content: 'سؤال', routed_from: 'fiqh' }))).json();
    assertEquals(sentBack.route, null);
    install({ hits: {}, modelText: 'جواب\n[[topic: health]]\n[[route: fiqh]]' });
    const fresh = await (await handler(post({ threadId: THREAD, content: 'سؤال' }))).json();
    assertEquals(fresh.route, 'fiqh');
  }));

Deno.test('dr-niswah — auth and rate limit still enforced before any model call', () =>
  quietly(async () => {
    const handler = await load('dr-niswah-chat');
    let rec = install({ hits: {}, modelText: 'x', authOk: false });
    assertEquals((await handler(post({ threadId: THREAD, content: 'سؤال' }))).status, 401);
    assertEquals(rec.modelCalls.length, 0);
    rec = install({ hits: {}, modelText: 'x', rateAllowed: false });
    assertEquals((await handler(post({ threadId: THREAD, content: 'سؤال عادي' }))).status, 429);
    assertEquals(rec.modelCalls.length, 0);
  }));

Deno.test('dr-niswah — the follow-up "لماذا؟" reaches the model with the earlier turn', () =>
  quietly(async () => {
    const handler = await load('dr-niswah-chat');
    const rec = install({ hits: {}, modelText: 'لأن...\n[[topic: health]]' });
    // Doctor Niswah reads earlier turns from the thread's stored rows
    // (newest first); serve two of them.
    globalThis.fetch = ((orig) => async (input: string | URL | Request, init?: RequestInit) => {
      const req = input instanceof Request ? input : new Request(input.toString(), init);
      const url = new URL(req.url);
      if (url.pathname === '/rest/v1/chat_messages' && req.method === 'GET') {
        return json([
          { id: 'a', role: 'assistant', content: 'الدم البني غالبًا دم قديم.' },
          { id: 'u', role: 'user', content: 'وش معنى اللون البني؟' },
        ]);
      }
      return orig(req);
    })(globalThis.fetch);
    await handler(post({ threadId: THREAD, content: 'لماذا؟' }));
    assertStringIncludes(rec.modelCalls[0].input, 'وش معنى اللون البني؟');
    assertStringIncludes(rec.modelCalls[0].input, 'Current user message: لماذا؟');
  }));

// ---------------------------------------------------------------------------
// Fiqh advisor
// ---------------------------------------------------------------------------

Deno.test('fiqh — no madhhab chosen: answers instead of the fixed "choose your madhhab" reply', () =>
  quietly(async () => {
    const handler = await load('fiqh-advisor-chat');
    const rec = install({
      hits: {},
      modelText: 'لا يجوز الجماع في الحيض بإجماع العلماء...\n[[topic: fiqh]]\n[[verify: no]]\n[[used: none]]',
    });
    const body = await (await handler(post({ question: 'هل يجوز الجماع وقت الحيض؟', madhhab_state: 'unset' }))).json();
    assertEquals(rec.modelCalls.length, 1);
    assertEquals(rec.retrievals.length, 0, 'the fiqh library is per madhhab');
    assertStringIncludes(body.text, 'بإجماع');
    assertEquals(body.notice, { aiGenerated: true, verify: null, topic: 'fiqh' });
    assertStringIncludes(rec.modelCalls[0].instructions, 'has not chosen a madhhab');
  }));

Deno.test('fiqh — selected madhhab: library searched, only used items cited, verify passed through', () =>
  quietly(async () => {
    const handler = await load('fiqh-advisor-chat');
    const rec = install({
      hits: {
        FIQH: [hit('FQ-1', 'FIQH', 'https://islamweb.net/a'), hit('FQ-2', 'FIQH', 'https://islamweb.net/b')],
      },
      modelText: 'عند الحنابلة...\n[[topic: fiqh]]\n[[verify: yes]]\n[[used: FQ-2]]',
    });
    const body = await (await handler(post({
      question: 'هل يجوز الجماع وقت الحيض؟',
      madhhab: 'hanbali',
      madhhab_state: 'selected',
    }))).json();
    assertEquals(rec.retrievals, [{ domain: 'FIQH', madhhab: 'hanbali' }]);
    assertEquals(body.citations.map((c: { knowledgeKey: string }) => c.knowledgeKey), ['FQ-2']);
    assertEquals(body.notice, { aiGenerated: false, verify: 'fiqh', topic: 'fiqh' });
    assertStringIncludes(rec.modelCalls[0].instructions, 'lead with the Hanbali position');
  }));

Deno.test('fiqh — state-dependent question with unresolved state: the model answers per case, never decides her state', () =>
  quietly(async () => {
    const handler = await load('fiqh-advisor-chat');
    const rec = install({ hits: {}, modelText: 'إذا كنتِ حائضًا... وإذا كنتِ طاهرًا...\n[[topic: fiqh]]' });
    const body = await (await handler(post({
      question: 'هل يجوز لي أصلي الحين؟',
      madhhab: 'shafii',
      madhhab_state: 'selected',
      clientFiqhState: 'needsAdvisory',
    }))).json();
    assertEquals(rec.modelCalls.length, 1);
    assertStringIncludes(rec.modelCalls[0].instructions, 'Do not decide her current state yourself');
    assertStringIncludes(body.text, 'إذا كنتِ حائضًا');
  }));

Deno.test('fiqh — an invalid madhhab is still rejected', () =>
  quietly(async () => {
    const handler = await load('fiqh-advisor-chat');
    const rec = install({ hits: {}, modelText: 'x' });
    const res = await handler(post({ question: 'سؤال', madhhab: 'zahiri', madhhab_state: 'selected' }));
    assertEquals(res.status, 400);
    assertEquals(rec.modelCalls.length, 0);
  }));

// ---------------------------------------------------------------------------
// Niswah AI (general assistant)
// ---------------------------------------------------------------------------

Deno.test('general — answers a fiqh question itself and may offer the Fiqh advisor', () =>
  quietly(async () => {
    const handler = await load('ai-assistant-chat');
    const rec = install({
      hits: {},
      modelText: 'لا يجوز الجماع وقت الحيض...\nوإن أردتِ تفاصيل حسب مذهبكِ فالمستشارة الفقهية تساعدكِ.\n[[topic: fiqh]]\n[[verify: no]]\n[[route: fiqh]]',
    });
    const body = await (await handler(post({ content: 'هل يجوز الجماع وقت الحيض؟' }))).json();
    assertStringIncludes(body.text, 'لا يجوز');
    assertEquals(body.route, 'fiqh');
    assertEquals(body.notice, { aiGenerated: true, verify: null, topic: 'fiqh' });
    assert(!rec.modelCalls[0].instructions.includes('You do not give medical diagnoses, personal treatment, or definitive religious rulings'));
  }));

Deno.test('general — an everyday answer carries no notice', () =>
  quietly(async () => {
    const handler = await load('ai-assistant-chat');
    install({ hits: {}, modelText: 'روتين بسيط...\n[[topic: general]]\n[[verify: no]]' });
    const body = await (await handler(post({ content: 'اقترحي علي روتين نوم' }))).json();
    assertEquals(body.notice.aiGenerated, false);
    assertEquals(body.route, null);
  }));
