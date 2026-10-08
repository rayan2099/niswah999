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
  }));
}
