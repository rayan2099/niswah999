-- Niswah V1 production knowledge-base schema.
-- Applies the reviewed KB contract with fail-closed publication and backend-owned citations.

create extension if not exists pg_trgm;

create table if not exists public.knowledge_sources (
  id uuid primary key default gen_random_uuid(),
  source_key text unique not null,
  domain text not null check (domain in ('HEALTH','SAFETY_ESCALATION','FIQH','NISWAH_PRODUCT')),
  title text not null,
  author_or_body text,
  language text,
  source_type text,
  authority_tier text,
  evidence_state text not null check (evidence_state in ('PRIMARY_SOURCE_VERIFIED','INSTITUTIONALLY_CORROBORATED')),
  license_status text,
  url_or_reference text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.knowledge_items (
  id uuid primary key default gen_random_uuid(),
  knowledge_key text unique not null,
  domain text not null check (domain in ('HEALTH','SAFETY_ESCALATION','FIQH','NISWAH_PRODUCT')),
  category text,
  topic text,
  subtopic text,
  madhhab text check (madhhab is null or madhhab in ('hanafi','maliki','shafii','hanbali')),
  -- Search routing metadata is deliberately separate from canonical content.
  -- For Fiqh, Arabic question text may route retrieval but is never treated as
  -- an approved Arabic ruling unless an Arabic knowledge_item_version exists.
  search_text_ar text,
  search_text_en text,
  publication_state text not null default 'DRAFT' check (publication_state in ('DRAFT','PUBLISHED','RETIRED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.knowledge_item_versions (
  id uuid primary key default gen_random_uuid(),
  knowledge_item_id uuid not null references public.knowledge_items(id) on delete cascade,
  version integer not null,
  language text not null check (language in ('ar','en')),
  canonical_statement text not null,
  supporting_explanation text,
  conditions jsonb not null default '{}'::jsonb,
  exceptions jsonb not null default '{}'::jsonb,
  applicable_user_states jsonb not null default '{}'::jsonb,
  safety_class text,
  evidence_state text not null check (evidence_state in ('PRIMARY_SOURCE_VERIFIED','INSTITUTIONALLY_CORROBORATED')),
  production_eligible boolean not null default false,
  effective_from timestamptz,
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  unique (knowledge_item_id, version, language)
);

create table if not exists public.knowledge_item_sources (
  knowledge_item_version_id uuid not null references public.knowledge_item_versions(id) on delete cascade,
  source_id uuid not null references public.knowledge_sources(id) on delete restrict,
  locator text not null,
  relation_type text not null default 'PRIMARY' check (relation_type in ('PRIMARY','CORROBORATING')),
  primary key (knowledge_item_version_id, source_id, locator)
);

create table if not exists public.knowledge_citations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  knowledge_item_version_id uuid not null references public.knowledge_item_versions(id),
  source_id uuid not null references public.knowledge_sources(id),
  locator text not null,
  response_trace_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_ki_retrieval on public.knowledge_items(domain, publication_state, madhhab, category, topic);
create index if not exists idx_ki_search_ar_trgm on public.knowledge_items using gin (search_text_ar gin_trgm_ops);
create index if not exists idx_ki_search_en_trgm on public.knowledge_items using gin (search_text_en gin_trgm_ops);
create index if not exists idx_kiv_retrieval on public.knowledge_item_versions(production_eligible, language, evidence_state);
create index if not exists idx_kiv_statement_trgm on public.knowledge_item_versions using gin (canonical_statement gin_trgm_ops);
create index if not exists idx_kiv_states_gin on public.knowledge_item_versions using gin (applicable_user_states);

alter table public.knowledge_sources enable row level security;
alter table public.knowledge_items enable row level security;
alter table public.knowledge_item_versions enable row level security;
alter table public.knowledge_item_sources enable row level security;
alter table public.knowledge_citations enable row level security;

-- No direct client reads. Edge functions retrieve through this fail-closed RPC.
revoke all on public.knowledge_sources from anon, authenticated;
revoke all on public.knowledge_items from anon, authenticated;
revoke all on public.knowledge_item_versions from anon, authenticated;
revoke all on public.knowledge_item_sources from anon, authenticated;
revoke all on public.knowledge_citations from anon, authenticated;

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
  with scored as (
    select
      ki.knowledge_key,
      kiv.id as version_id,
      ki.domain,
      ki.category,
      ki.topic,
      ki.madhhab,
      kiv.language as content_language,
      kiv.canonical_statement,
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
    where ki.publication_state = 'PUBLISHED'
      and kiv.production_eligible = true
      and (
        kiv.language = p_language
        -- V1 Fiqh propositions are source-verified in English. Arabic
        -- scholar-packet questions may route retrieval, but the canonical
        -- English proposition is returned and the model may translate it
        -- without broadening it. No Arabic ruling is invented in storage.
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
    -- Never return arbitrary "top" rows for an unrelated question. The
    -- threshold is intentionally conservative and is covered by acceptance
    -- tests; below-threshold queries fail closed to zero knowledge hits.
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
'Fail-closed KB retrieval: only published, production-eligible, sufficiently relevant rows. FIQH requires an explicit Madhhab; Arabic routing may return the verified English proposition without creating an unreviewed Arabic ruling.';
