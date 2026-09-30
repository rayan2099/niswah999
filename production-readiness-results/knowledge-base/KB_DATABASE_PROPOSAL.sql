-- PROPOSAL ONLY. DO NOT APPLY AUTOMATICALLY.
-- Niswah V1 Knowledge Base schema draft.

create table if not exists knowledge_sources (
  id uuid primary key default gen_random_uuid(),
  source_key text unique not null,
  domain text not null,
  title text not null,
  author_or_body text,
  edition text,
  language text,
  source_type text,
  authority_tier text,
  approval_state text not null default 'CANDIDATE',
  license_status text,
  url_or_reference text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists knowledge_items (
  id uuid primary key default gen_random_uuid(),
  knowledge_key text unique not null,
  domain text not null,
  category text,
  topic text,
  subtopic text,
  madhhab text,
  created_at timestamptz not null default now()
);

create table if not exists knowledge_item_versions (
  id uuid primary key default gen_random_uuid(),
  knowledge_item_id uuid not null references knowledge_items(id) on delete cascade,
  version integer not null,
  canonical_statement text not null,
  supporting_explanation text,
  language text not null,
  conditions jsonb not null default '{}'::jsonb,
  exceptions jsonb not null default '{}'::jsonb,
  applicable_user_states jsonb not null default '{}'::jsonb,
  safety_class text,
  review_status text not null default 'DRAFT',
  effective_from timestamptz,
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  unique(knowledge_item_id, version, language)
);

create table if not exists knowledge_reviews (
  id uuid primary key default gen_random_uuid(),
  knowledge_item_version_id uuid not null references knowledge_item_versions(id) on delete cascade,
  reviewer_role text not null,
  reviewer_name text,
  decision text not null,
  notes text,
  reviewed_at timestamptz not null default now()
);

create table if not exists knowledge_item_sources (
  knowledge_item_version_id uuid not null references knowledge_item_versions(id) on delete cascade,
  source_id uuid not null references knowledge_sources(id) on delete restrict,
  locator text not null,
  relation_type text not null default 'PRIMARY',
  primary key (knowledge_item_version_id, source_id, locator)
);

create table if not exists knowledge_citations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  knowledge_item_version_id uuid not null references knowledge_item_versions(id),
  source_id uuid not null references knowledge_sources(id),
  locator text not null,
  response_trace_id text,
  created_at timestamptz not null default now()
);

create table if not exists knowledge_source_state_history (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references knowledge_sources(id) on delete cascade,
  from_state text,
  to_state text not null,
  changed_by text,
  notes text,
  changed_at timestamptz not null default now()
);

create index if not exists idx_ki_domain_topic on knowledge_items(domain, topic, madhhab);
create index if not exists idx_kiv_status on knowledge_item_versions(review_status, language);
create index if not exists idx_kiv_conditions_gin on knowledge_item_versions using gin(conditions);
create index if not exists idx_kiv_states_gin on knowledge_item_versions using gin(applicable_user_states);

-- Embedding/vector columns intentionally omitted until reviewed knowledge exists.
