-- Persist human_review_status on knowledge_item_versions and expose it
-- through retrieval/provenance.
--
-- Launch-readiness audit (2026-10-15), FD-5 condition 1
-- (FOUNDER_DECISIONS.md: "human_review_status must remain explicit on
-- every row, always"). Before this migration, human_review_status
-- existed only in the build-time CSV pipeline
-- (PRODUCTION_DISPOSITION_MASTER.csv -> build_kb_production_candidates.py
-- -> render_kb_seed_sql.py) that decides WHICH rows get seeded at all --
-- it was never a column on the live database row itself. That satisfied
-- condition 1 only by coincidence: every currently-seeded row happens to
-- share the single value NOT_REVIEWED (254/254, confirmed against
-- PRODUCTION_DISPOSITION_MASTER.csv this audit), so a blanket prompt-level
-- statement ("human_review_status is NOT_REVIEWED for all of it") was
-- true. There was no live mechanism to vary it per row, and nothing
-- would have caught a future seed run that mixed reviewed and
-- unreviewed content.
--
-- All current production-eligible content is backfilled to NOT_REVIEWED
-- -- this is not a guess: every one of the 254 rows in
-- PRODUCTION_DISPOSITION_MASTER.csv already carries human_review_status
-- = NOT_REVIEWED, confirmed directly against that file. Future seed runs
-- must supply this column explicitly (render_kb_seed_sql.py now reads it
-- from the candidate CSV and fails the render if a row is missing it --
-- see that script's own SystemExit check) rather than relying on a
-- NOT NULL default to paper over a missing value.

alter table public.knowledge_item_versions
  add column if not exists human_review_status text;

update public.knowledge_item_versions
set human_review_status = 'NOT_REVIEWED'
where human_review_status is null;

-- Deliberately NO default: a default value would let some future insert
-- path that forgets to pass human_review_status succeed silently with a
-- guessed value, exactly what condition 1 ("always explicit") forbids.
-- NOT NULL with no default means any insert missing it fails loudly at
-- the database level, not just in render_kb_seed_sql.py's own check.
alter table public.knowledge_item_versions
  alter column human_review_status set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'knowledge_item_versions_human_review_status_check'
  ) then
    alter table public.knowledge_item_versions
      add constraint knowledge_item_versions_human_review_status_check
      check (human_review_status in (
        'NOT_REVIEWED',
        'SCHOLAR_APPROVED',
        'MEDICALLY_APPROVED',
        'SCHOLAR_AND_MEDICALLY_APPROVED',
        'REJECTED'
      ));
  end if;
end $$;

comment on column public.knowledge_item_versions.human_review_status is
'Explicit, per-row, database-level review status (FD-5 condition 1 — FOUNDER_DECISIONS.md). NOT_REVIEWED for all 254 currently-eligible rows. Must reach retrieval/citation output unflattened — a NOT_REVIEWED row must never be presented as SCHOLAR_APPROVED/MEDICALLY_APPROVED anywhere (FD-5 condition 2). Set explicitly by render_kb_seed_sql.py from PRODUCTION_DISPOSITION_MASTER.csv on every seed; never left to the column default to decide.';

-- ----------------------------------------------------------------------------
-- retrieve_knowledge_v1 — replaced again to also return human_review_status,
-- so retrieval/provenance callers see the real per-row value instead of
-- having to assume a blanket constant.
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
  human_review_status text,
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
  query_check as (
    select
      (
        p_query ~* '\m(bleed|bleeding|blood|period|periods|menstrual|menstruation|menstruate|cycle|cycles|haid|hayd|istihada|istihadah|tahara|tuhr|purity|pure|nifas|nifaas|postpartum|pregnant|pregnancy|pregnancies|maternal|maternity|fertility|fertile|ttc|conceive|conception|spotting|discharge|cramps|cramping|prayer|pray|prays|praying|salah|salat|fast|fasting|fasted|ramadan|ghusl|wudu|ablution|dizziness|dizzy|chest|breathing|breath|miscarriage|childbirth|labor|delivery|postnatal|hormone|hormonal|menopause)\M'
        or p_query similar to '%(حيض|الحيض|حائض|حائضة|طهر|الطهر|طاهر|طاهرة|تطهر|نفاس|النفاس|نفساء|استحاضة|استحاضه|مستحاضة|دورة|الدورة|الدوره|حمل|الحمل|حامل|حوامل|ولادة|الولادة|ولدت|رضاعة|الرضاعة|رضاعه|نزيف|النزيف|دم|الدم|دماء|خصوبة|الخصوبة|خصوب|إباضة|الإباضة|اباضة|تبويض|صلاة|الصلاة|صلى|تصلي|أصلي|صوم|الصوم|صائم|صائمة|صيام|أصوم|غسل|الغسل|اغتسال|وضوء|الوضوء|دوار|دوخة|تنفس|التنفس|إجهاض|الإجهاض|هرمون|هرمونات)%'
      ) as has_anchor
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
      kiv.human_review_status,
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
    where exists (select 1 from active_snapshot)
      and (select has_anchor from query_check)
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
    e.human_review_status,
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
'Fail-closed KB retrieval: only published, production-eligible, sufficiently relevant rows tagged with the currently-registered evidence snapshot, AND only for queries containing at least one recognizable domain anchor term. FIQH requires an explicit Madhhab; Arabic routing may return the verified English proposition without creating an unreviewed Arabic ruling. qualification_note, when present, must be carried into the generated answer, not dropped. human_review_status is returned per row (2026-10-15) so callers see the real value rather than assuming a blanket constant.';
