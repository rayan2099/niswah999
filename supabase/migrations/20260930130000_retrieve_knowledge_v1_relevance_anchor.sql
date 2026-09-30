-- Retrieval Precision Remediation Pass (2026-09-30).
--
-- A 40-case, then 75-case combined measured study
-- (RETRIEVAL_PRECISION_STUDY.md, RETRIEVAL_PRECISION_REMEDIATION_REPORT.md)
-- found the trigram-similarity floor (score >= 0.12) cannot be raised to
-- fix its false-positive rate: false-positive and true-positive score
-- distributions genuinely overlap, so no single cutoff separates them
-- without losing real recall on genuine Fiqh/Health questions.
--
-- The primary fix is an application-layer relevance gate
-- (supabase/functions/_shared/kb_relevance_gate.ts), which is more
-- sophisticated than what is added here (typo-tolerant fuzzy matching,
-- gibberish detection, polysemy-trap and wrong-population exclusions) and
-- is the authoritative, fully-tested gate for real application traffic.
--
-- This migration adds a deliberately COARSER, second-tier backstop
-- directly in the RPC itself: a query must contain at least one
-- recognizable domain term (an "anchor") before ANY row is considered a
-- candidate, regardless of trigram score. This is not a duplicate of the
-- TypeScript gate's full logic (which would create a second,
-- independently-drifting copy of business logic in two languages, the
-- exact failure mode this codebase's own prior audits have repeatedly
-- flagged as a defect elsewhere) -- it is a narrower, purely lexical
-- floor that ANY caller of this RPC benefits from, including direct SQL
-- callers (e.g. scripts/verify_kb_retrieval_live.sql) that never go
-- through the application layer at all.
--
-- This narrows results only. It cannot promote a FAIL_CLOSED row (the
-- existing production_eligible/publication_state/snapshot-commit filters
-- are unchanged and evaluated identically), cannot cross a Madhhab
-- boundary (the existing madhhab filter is unchanged), and cannot expose
-- evidence a query's anchor terms didn't already make plausible.

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
  -- Coarse anchor presence check (see migration header comment for why
  -- this is intentionally simpler than the TypeScript gate). English:
  -- word-boundary match (\m/\M) against a curated domain-term list drawn
  -- from real KB search_text_en/ar frequency analysis, so "bicycle" does
  -- not match "cycle". Arabic: substring match, since Arabic morphology
  -- attaches prefixes/suffixes directly to the root -- word-boundary
  -- matching would miss real inflected forms.
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
'Fail-closed KB retrieval: only published, production-eligible, sufficiently relevant rows tagged with the currently-registered evidence snapshot, AND only for queries containing at least one recognizable domain anchor term (coarse second-tier relevance backstop, Retrieval Precision Remediation Pass 2026-09-30 -- see kb_relevance_gate.ts for the primary, more sophisticated application-layer gate). FIQH requires an explicit Madhhab; Arabic routing may return the verified English proposition without creating an unreviewed Arabic ruling. qualification_note, when present, must be carried into the generated answer, not dropped.';
