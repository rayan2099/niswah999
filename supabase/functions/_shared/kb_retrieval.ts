import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { checkQueryRelevance } from './kb_relevance_gate.ts';

export type KnowledgeDomain = 'HEALTH' | 'SAFETY_ESCALATION' | 'FIQH' | 'NISWAH_PRODUCT';

// The evidence snapshot this code was built against
// (EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json's frozen_at_commit_sha). Retrieval
// only ever trusts KB rows tagged with this exact commit — if the live
// database is seeded from a different snapshot (a re-freeze that this code
// hasn't been updated to expect, or a rollback), assertSnapshotHealth() below
// fails closed rather than silently serving a dataset that never passed the
// production-disposition gate this code assumes.
export const EXPECTED_SNAPSHOT_COMMIT = 'eda4b96c7b2a77924a3dd86397cbcbba671440b3';

export interface KnowledgeHit {
  knowledge_key: string;
  version_id: string;
  domain: KnowledgeDomain;
  category: string | null;
  topic: string | null;
  madhhab: string | null;
  content_language: 'ar' | 'en';
  canonical_statement: string;
  qualification_note: string | null;
  safety_class: string | null;
  human_review_status: string;
  source_key: string;
  source_title: string;
  locator: string;
  source_url: string;
  rank_score: number;
}

export interface SnapshotHealth {
  ok: boolean;
  activeCommit: string | null;
  expectedCommit: string;
  reason?: 'no_snapshot_registered' | 'commit_mismatch' | 'check_failed';
}

/**
 * Confirms the live database's currently-registered KB snapshot
 * (kb_snapshot_registry, populated by render_kb_seed_sql.py on every seed
 * run) matches the commit this code expects. Callers must treat a
 * non-`ok` result as "no eligible evidence" — never proceed to generation
 * as if retrieval had simply found nothing, since that would hide a real
 * deploy/rollback mismatch behind an ordinary "insufficient evidence" answer.
 */
export async function assertSnapshotHealth(client: SupabaseClient): Promise<SnapshotHealth> {
  const { data, error } = await client.rpc('get_active_kb_snapshot');
  if (error) {
    console.error('kb snapshot health check failed', { message: error.message });
    return { ok: false, activeCommit: null, expectedCommit: EXPECTED_SNAPSHOT_COMMIT, reason: 'check_failed' };
  }
  const row = Array.isArray(data) ? data[0] : data;
  const activeCommit = row?.commit_sha ?? null;
  if (!activeCommit) {
    return { ok: false, activeCommit: null, expectedCommit: EXPECTED_SNAPSHOT_COMMIT, reason: 'no_snapshot_registered' };
  }
  if (activeCommit !== EXPECTED_SNAPSHOT_COMMIT) {
    console.error('kb snapshot mismatch', { activeCommit, expectedCommit: EXPECTED_SNAPSHOT_COMMIT });
    return { ok: false, activeCommit, expectedCommit: EXPECTED_SNAPSHOT_COMMIT, reason: 'commit_mismatch' };
  }
  return { ok: true, activeCommit, expectedCommit: EXPECTED_SNAPSHOT_COMMIT };
}

export async function retrieveKnowledge(
  client: SupabaseClient,
  params: {
    domain: KnowledgeDomain;
    language: 'ar' | 'en';
    query: string;
    madhhab?: string | null;
    limit?: number;
  },
): Promise<KnowledgeHit[]> {
  if (params.domain === 'FIQH' && !params.madhhab) return [];
  // Retrieval Precision Remediation Pass: reject queries with no plausible
  // connection to Niswah's domain before ever calling the trigram-scoring
  // RPC -- the score threshold alone cannot separate these (measured,
  // RETRIEVAL_PRECISION_STUDY.md). A rejected query returns [] exactly like
  // an empty retrieval result, so every existing caller's no-eligible-
  // evidence fail-closed path already handles it correctly.
  const relevance = checkQueryRelevance(params.query);
  if (!relevance.allow) return [];
  const { data, error } = await client.rpc('retrieve_knowledge_v1', {
    p_domain: params.domain,
    p_language: params.language,
    p_query: params.query,
    p_madhhab: params.madhhab ?? null,
    p_limit: params.limit ?? 8,
  });
  if (error) {
    console.error('kb retrieval failed', { domain: params.domain, message: error.message });
    return [];
  }
  return (data ?? []) as KnowledgeHit[];
}

export function formatKnowledgeBlock(hits: KnowledgeHit[]): string {
  if (hits.length === 0) return '[KNOWLEDGE]\nNo production-eligible knowledge item matched this request.';
  const byVersion = new Map<string, KnowledgeHit[]>();
  for (const hit of hits) {
    const list = byVersion.get(hit.version_id) ?? [];
    list.push(hit);
    byVersion.set(hit.version_id, list);
  }
  const chunks: string[] = [];
  for (const rows of byVersion.values()) {
    const first = rows[0];
    const citations = rows.map((r) => `${r.source_title} | ${r.locator} | ${r.source_url}`).join(' || ');
    // safety_class and qualification_note previously reached this function
    // but were silently dropped before the model ever saw them. Both are
    // now included explicitly: qualification_note carries a
    // VERIFIED_WITH_QUALIFICATION row's scope restriction (e.g. HL-MENS-002's
    // "never state a bare range without naming its source") into the model's
    // context so it cannot flatten the proposition into an unconditional
    // claim; safety_class lets the model recognize escalation-relevant items.
    const lines = [
      `ID=${first.knowledge_key}`,
      `CONTENT_LANGUAGE=${first.content_language}`,
      `STATEMENT=${first.canonical_statement}`,
    ];
    if (first.qualification_note) lines.push(`QUALIFICATION=${first.qualification_note}`);
    if (first.safety_class) lines.push(`SAFETY_CLASS=${first.safety_class}`);
    // Per-row, database-level value (2026-10-15, FD-5 condition 1 --
    // FOUNDER_DECISIONS.md) rather than the model inferring/assuming a
    // blanket status -- see migration 20261015120000 for where this
    // column comes from and why it must never be flattened away.
    lines.push(`HUMAN_REVIEW_STATUS=${first.human_review_status}`);
    lines.push(`CITATIONS=${citations}`);
    chunks.push(lines.join('\n'));
  }
  return `[KNOWLEDGE]\n${chunks.join('\n---\n')}`;
}

export function citationPayload(hits: KnowledgeHit[]) {
  const seen = new Set<string>();
  return hits.filter((h) => {
    const key = `${h.version_id}|${h.source_key}|${h.locator}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).map((h) => ({
    knowledgeKey: h.knowledge_key,
    versionId: h.version_id,
    sourceKey: h.source_key,
    title: h.source_title,
    locator: h.locator,
    url: h.source_url,
    contentLanguage: h.content_language,
    humanReviewStatus: h.human_review_status,
  }));
}

/**
 * The citations shown under an answer: only the knowledge items the model
 * said it relied on, one card per source document. `usedIds` null means the
 * model did not say, and nothing is cited; an empty set means it used none. Hits arrive ranked, so the first locator kept for a source is
 * its best match.
 *
 * Before this, citationPayload() kept one card per (item, source, locator),
 * so four knowledge items drawn from one NHS page became four identical
 * "Urgent Maternal Warning Signs and Symptoms" cards (testing feedback
 * 2026-10-30).
 */
export function citationsForAnswer(hits: KnowledgeHit[], usedIds: Set<string> | null) {
  // TestFlight Feedback 2 (2026-10-31): a missing [[used:]] line used to
  // cite EVERY retrieved item, which is how unrelated safety items reached
  // unrelated answers. Now nothing is cited unless the model names it.
  if (usedIds === null) return [];
  const relevant = hits.filter((h) => usedIds.has(h.knowledge_key));
  const seen = new Set<string>();
  const unique = relevant.filter((h) => {
    const key = (h.source_url || h.source_key).trim().toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return citationPayload(unique);
}
