import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export type KnowledgeDomain = 'HEALTH' | 'SAFETY_ESCALATION' | 'FIQH' | 'NISWAH_PRODUCT';

export interface KnowledgeHit {
  knowledge_key: string;
  version_id: string;
  domain: KnowledgeDomain;
  category: string | null;
  topic: string | null;
  madhhab: string | null;
  content_language: 'ar' | 'en';
  canonical_statement: string;
  safety_class: string | null;
  source_key: string;
  source_title: string;
  locator: string;
  source_url: string;
  rank_score: number;
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
    chunks.push(
      `ID=${first.knowledge_key}\nCONTENT_LANGUAGE=${first.content_language}\nSTATEMENT=${first.canonical_statement}\nCITATIONS=${citations}`,
    );
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
