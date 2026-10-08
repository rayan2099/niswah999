import { assertEquals, assertStrictEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import {
  assertSnapshotHealth,
  citationPayload,
  EXPECTED_SNAPSHOT_COMMIT,
  formatKnowledgeBlock,
  KnowledgeHit,
  retrieveKnowledge,
} from './kb_retrieval.ts';

function hit(overrides: Partial<KnowledgeHit> = {}): KnowledgeHit {
  return {
    knowledge_key: 'HL-TEST-001',
    version_id: 'v1',
    domain: 'HEALTH',
    category: 'TEST',
    topic: 'test',
    madhhab: null,
    content_language: 'en',
    canonical_statement: 'Test statement.',
    qualification_note: null,
    safety_class: null,
    source_key: 'SRC',
    source_title: 'Source Title',
    locator: 'p.1',
    source_url: 'https://example.test/source',
    rank_score: 0.5,
    ...overrides,
  };
}

// A fake SupabaseClient exposing only the `.rpc()` shape retrieveKnowledge /
// assertSnapshotHealth actually call. Records every call so tests can assert
// short-circuit behavior (e.g. Fiqh-with-no-madhhab never reaching the RPC).
function fakeClient(rpcImpl: (fn: string, args: unknown) => Promise<{ data: unknown; error: unknown }>) {
  const calls: Array<{ fn: string; args: unknown }> = [];
  return {
    calls,
    // deno-lint-ignore no-explicit-any
    rpc(fn: string, args: unknown): any {
      calls.push({ fn, args });
      return rpcImpl(fn, args);
    },
  };
}

Deno.test('formatKnowledgeBlock — includes QUALIFICATION line when present (HL-MENS-002 fixture)', () => {
  const qualification =
    'Population-level general guidance only; never an individual diagnostic boundary.';
  const block = formatKnowledgeBlock([
    hit({
      knowledge_key: 'HL-MENS-002',
      canonical_statement:
        'In adults, menstrual cycle length normally varies across people and can vary over time.',
      qualification_note: qualification,
    }),
  ]);
  assertEquals(block.includes(`QUALIFICATION=${qualification}`), true);
});

Deno.test('formatKnowledgeBlock — omits QUALIFICATION line when absent (no fabricated caveat)', () => {
  const block = formatKnowledgeBlock([hit({ qualification_note: null })]);
  assertEquals(block.includes('QUALIFICATION='), false);
});

Deno.test('formatKnowledgeBlock — includes SAFETY_CLASS when present, previously silently dropped', () => {
  const block = formatKnowledgeBlock([hit({ safety_class: 'URGENT' })]);
  assertEquals(block.includes('SAFETY_CLASS=URGENT'), true);
});

Deno.test('formatKnowledgeBlock — zero hits produces the explicit no-match block, not an empty string', () => {
  const block = formatKnowledgeBlock([]);
  assertEquals(block, '[KNOWLEDGE]\nNo production-eligible knowledge item matched this request.');
});

Deno.test('citationPayload — every field comes from the hit object, never from model output', () => {
  const hits = [hit({ knowledge_key: 'A', source_key: 'S1', locator: 'p.1' })];
  const citations = citationPayload(hits);
  assertEquals(citations.length, 1);
  assertEquals(citations[0].knowledgeKey, 'A');
  assertEquals(citations[0].sourceKey, 'S1');
  assertEquals(citations[0].url, hits[0].source_url);
});

Deno.test('citationPayload — dedupes identical version/source/locator triples', () => {
  const hits = [
    hit({ version_id: 'v1', source_key: 'S1', locator: 'p.1' }),
    hit({ version_id: 'v1', source_key: 'S1', locator: 'p.1' }),
    hit({ version_id: 'v1', source_key: 'S1', locator: 'p.2' }),
  ];
  const citations = citationPayload(hits);
  assertEquals(citations.length, 2);
});

Deno.test('retrieveKnowledge — Fiqh with no madhhab short-circuits before calling the RPC (Madhhab-boundary guard)', async () => {
  const client = fakeClient(() => Promise.resolve({ data: [hit()], error: null }));
  const result = await retrieveKnowledge(client as never, {
    domain: 'FIQH',
    language: 'en',
    query: 'any question',
    madhhab: null,
  });
  assertEquals(result, []);
  assertEquals(client.calls.length, 0, 'the RPC must never be called for FIQH without an explicit madhhab');
});

Deno.test('retrieveKnowledge — Fiqh WITH a madhhab reaches the RPC and passes it through unchanged', async () => {
  const client = fakeClient((fn, args) => {
    assertStrictEquals(fn, 'retrieve_knowledge_v1');
    return Promise.resolve({ data: [hit({ madhhab: 'hanafi' })], error: null });
  });
  const result = await retrieveKnowledge(client as never, {
    domain: 'FIQH',
    language: 'ar',
    query: 'ما حكم الحيض؟', // a real domain query -- must pass the relevance gate to reach the RPC at all
    madhhab: 'hanafi',
  });
  assertEquals(result.length, 1);
  assertEquals(client.calls.length, 1);
  assertEquals((client.calls[0].args as { p_madhhab: string }).p_madhhab, 'hanafi');
});

Deno.test('retrieveKnowledge — RPC error fails closed to an empty result, never throws', async () => {
  const client = fakeClient(() => Promise.resolve({ data: null, error: { message: 'boom' } }));
  const result = await retrieveKnowledge(client as never, {
    domain: 'HEALTH',
    language: 'en',
    query: 'what is the fertile window and how is it estimated', // a real domain query -- must pass the relevance gate to reach the RPC at all
  });
  assertEquals(result, []);
  // Asserted explicitly so this test cannot silently "pass" without ever
  // reaching the RPC (which the relevance gate added in the Retrieval
  // Precision Remediation Pass would otherwise make possible for a
  // non-domain query, papering over whether the RPC-error path itself
  // still works).
  assertEquals(client.calls.length, 1, 'the RPC must actually be called for this test to exercise its own error path');
});

Deno.test('assertSnapshotHealth — ok:true when the active commit matches exactly what this code expects', async () => {
  const client = fakeClient(() =>
    Promise.resolve({ data: [{ commit_sha: EXPECTED_SNAPSHOT_COMMIT }], error: null })
  );
  const health = await assertSnapshotHealth(client as never);
  assertEquals(health.ok, true);
  assertEquals(health.activeCommit, EXPECTED_SNAPSHOT_COMMIT);
});

Deno.test('assertSnapshotHealth — fails closed when no snapshot is registered at all', async () => {
  const client = fakeClient(() => Promise.resolve({ data: [], error: null }));
  const health = await assertSnapshotHealth(client as never);
  assertEquals(health.ok, false);
  assertEquals(health.reason, 'no_snapshot_registered');
});

Deno.test('assertSnapshotHealth — fails closed when the live DB is seeded from a DIFFERENT commit than expected', async () => {
  const client = fakeClient(() =>
    Promise.resolve({ data: [{ commit_sha: 'some-other-commit-not-what-code-expects' }], error: null })
  );
  const health = await assertSnapshotHealth(client as never);
  assertEquals(health.ok, false);
  assertEquals(health.reason, 'commit_mismatch');
  assertEquals(health.activeCommit, 'some-other-commit-not-what-code-expects');
  assertEquals(health.expectedCommit, EXPECTED_SNAPSHOT_COMMIT);
});

Deno.test('assertSnapshotHealth — fails closed (not throws) when the RPC call itself errors', async () => {
  const client = fakeClient(() => Promise.resolve({ data: null, error: { message: 'connection lost' } }));
  const health = await assertSnapshotHealth(client as never);
  assertEquals(health.ok, false);
  assertEquals(health.reason, 'check_failed');
});
