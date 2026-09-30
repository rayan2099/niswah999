-- Niswah V1 KB — qualification metadata + frozen-snapshot enforcement.
--
-- Additive to 20260929114500_knowledge_base_v1.sql (never applied to any
-- database yet — PR #6 is still draft/unmerged). Adds:
--   1) a first-class qualification_note column so a VERIFIED_WITH_QUALIFICATION
--      row's scope restriction survives into retrieval and generation instead
--      of being flattened into an unconditional claim;
--   2) an evidence_snapshot_commit column plus a kb_snapshot_registry table so
--      runtime retrieval can be checked against the exact frozen evidence
--      snapshot (EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json) it was seeded from,
--      and fails safely rather than silently serving an unrecognized dataset.

alter table public.knowledge_item_versions
  add column if not exists qualification_note text,
  add column if not exists evidence_snapshot_commit text;

-- Backfill is a no-op today (table is empty pre-deploy); the column is
-- required going forward so every future insert must declare which frozen
-- snapshot it came from.
alter table public.knowledge_item_versions
  alter column evidence_snapshot_commit set not null;

comment on column public.knowledge_item_versions.qualification_note is
'Production-facing scope restriction for VERIFIED_WITH_QUALIFICATION rows (e.g. HL-MENS-002: never state a bare cycle-length range without naming its source). Must reach formatKnowledgeBlock() and the generated answer, never be silently dropped.';
comment on column public.knowledge_item_versions.evidence_snapshot_commit is
'The frozen_at_commit_sha from EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json this row was seeded from. Retrieval checks this against the snapshot the running code expects and fails closed on mismatch.';

-- ----------------------------------------------------------------------------
-- kb_snapshot_registry
-- ----------------------------------------------------------------------------
-- One append-only row per seed run, recording exactly which frozen evidence
-- snapshot was loaded. is_current marks the one the live data actually
-- reflects; render_kb_seed_sql.py sets the previous row's is_current=false in
-- the same transaction it inserts the new one, so there is never more than
-- one "current" snapshot at a time and the history is never rewritten.

create table if not exists public.kb_snapshot_registry (
  id uuid primary key default gen_random_uuid(),
  commit_sha text not null,
  manifest_sha256 text not null,
  master_csv_sha256 text not null,
  freeze_timestamp_utc timestamptz not null,
  total_atoms integer not null,
  production_eligible_count integer not null,
  fail_closed_count integer not null,
  loaded_at timestamptz not null default now(),
  is_current boolean not null default false
);

create unique index if not exists idx_kb_snapshot_registry_one_current
  on public.kb_snapshot_registry (is_current)
  where is_current;

alter table public.kb_snapshot_registry enable row level security;
revoke all on public.kb_snapshot_registry from anon, authenticated;

create or replace function public.get_active_kb_snapshot()
returns table (
  commit_sha text,
  manifest_sha256 text,
  master_csv_sha256 text,
  freeze_timestamp_utc timestamptz,
  total_atoms integer,
  production_eligible_count integer,
  fail_closed_count integer,
  loaded_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select commit_sha, manifest_sha256, master_csv_sha256, freeze_timestamp_utc,
         total_atoms, production_eligible_count, fail_closed_count, loaded_at
  from public.kb_snapshot_registry
  where is_current
  limit 1;
$$;

revoke all on function public.get_active_kb_snapshot() from public;
grant execute on function public.get_active_kb_snapshot() to authenticated;

comment on function public.get_active_kb_snapshot is
'Returns the identity of whichever frozen evidence snapshot the live KB data was actually seeded from, or zero rows if none has been loaded yet. Edge functions check this against their own expected commit before treating retrieval results as trustworthy.';

-- ----------------------------------------------------------------------------
-- retrieve_knowledge_v1 — replaced to return qualification_note and to only
-- ever serve rows tagged with the currently-registered snapshot commit.
-- ----------------------------------------------------------------------------

drop function if exists public.retrieve_knowledge_v1(text, text, text, text, integer);

create or replace function public.retrieve_knowledge_v1(
  p_domain text,
  p_language text,
  p_query text,
  p_madhhab text default null,
  p_limit integer default 8
)
returns table (
  knowledge_key text,
  version_id uuid,
  domain text,
  category text,
  topic text,
  madhhab text,
  content_language text,
  canonical_statement text,
  qualification_note text,
  safety_class text,
  source_key text,
  source_title text,
  locator text,
  source_url text,
  rank_score real
)
language sql
security definer
set search_path = public
stable
as $$
  with active_snapshot as (
    select commit_sha from public.kb_snapshot_registry where is_current limit 1
  ),
  scored as (
    select
      ki.knowledge_key,
      kiv.id as version_id,
      ki.domain,
      ki.category,
      ki.topic,
      ki.madhhab,
      kiv.language as content_language,
      kiv.canonical_statement,
      kiv.qualification_note,
      kiv.safety_class,
      greatest(
        similarity(lower(kiv.canonical_statement), lower(coalesce(p_query,''))),
        word_similarity(lower(coalesce(p_query,'')), lower(kiv.canonical_statement)),
        similarity(
          lower(case when p_language = 'ar' then coalesce(ki.search_text_ar,'') else coalesce(ki.search_text_en,'') end),
          lower(coalesce(p_query,''))
        ),
        word_similarity(
          lower(coalesce(p_query,'')),
          lower(case when p_language = 'ar' then coalesce(ki.search_text_ar,'') else coalesce(ki.search_text_en,'') end)
        ),
        similarity(lower(coalesce(ki.topic,'')), lower(coalesce(p_query,'')))
      ) as score,
      case when kiv.language = p_language then 1 else 0 end as exact_language
    from public.knowledge_items ki
    join public.knowledge_item_versions kiv on kiv.knowledge_item_id = ki.id
    -- Fail closed on an unrecognized/mismatched snapshot: if the registry has
    -- no current row, or this version was seeded under a different commit
    -- than the one currently registered as active, it is never returned.
    -- This is a second, independent check from get_active_kb_snapshot() --
    -- callers should check that too, but retrieval itself never silently
    -- serves stale/foreign rows even if a caller forgets to.
    where exists (select 1 from active_snapshot)
      and kiv.evidence_snapshot_commit = (select commit_sha from active_snapshot)
      and ki.publication_state = 'PUBLISHED'
      and kiv.production_eligible = true
      and (
        kiv.language = p_language
        or (ki.domain = 'FIQH' and p_language = 'ar' and kiv.language = 'en')
      )
      and ki.domain = p_domain
      and (
        p_domain <> 'FIQH'
        or (p_madhhab is not null and ki.madhhab = lower(p_madhhab))
      )
  ),
  eligible as (
    select * from scored
    where score >= 0.12
  )
  select
    e.knowledge_key,
    e.version_id,
    e.domain,
    e.category,
    e.topic,
    e.madhhab,
    e.content_language,
    e.canonical_statement,
    e.qualification_note,
    e.safety_class,
    ks.source_key,
    ks.title,
    kis.locator,
    ks.url_or_reference,
    e.score
  from eligible e
  join public.knowledge_item_sources kis on kis.knowledge_item_version_id = e.version_id
  join public.knowledge_sources ks on ks.id = kis.source_id
  order by e.exact_language desc, e.score desc, e.knowledge_key
  limit greatest(1, least(coalesce(p_limit, 8), 20));
$$;

revoke all on function public.retrieve_knowledge_v1(text,text,text,text,integer) from public;
grant execute on function public.retrieve_knowledge_v1(text,text,text,text,integer) to authenticated;

comment on function public.retrieve_knowledge_v1 is
'Fail-closed KB retrieval: only published, production-eligible, sufficiently relevant rows tagged with the currently-registered evidence snapshot. FIQH requires an explicit Madhhab; Arabic routing may return the verified English proposition without creating an unreviewed Arabic ruling. qualification_note, when present, must be carried into the generated answer, not dropped.';
