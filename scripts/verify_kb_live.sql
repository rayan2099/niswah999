\set ON_ERROR_STOP on

-- Niswah V1 live KB verification. Fail if denominator or publication gates drift.
DO $$
DECLARE
  health_count integer;
  fiqh_count integer;
  total_count integer;
  bad_fiqh_madhhab integer;
  unpublished_eligible integer;
  source_missing integer;
BEGIN
  SELECT count(*) INTO total_count
  FROM public.knowledge_items ki
  WHERE ki.publication_state = 'PUBLISHED'
    AND EXISTS (
      SELECT 1 FROM public.knowledge_item_versions kiv
      WHERE kiv.knowledge_item_id = ki.id AND kiv.production_eligible = true
    );

  SELECT count(*) INTO health_count
  FROM public.knowledge_items ki
  WHERE ki.publication_state = 'PUBLISHED'
    AND ki.domain IN ('HEALTH','SAFETY_ESCALATION')
    AND EXISTS (
      SELECT 1 FROM public.knowledge_item_versions kiv
      WHERE kiv.knowledge_item_id = ki.id AND kiv.production_eligible = true
    );

  SELECT count(*) INTO fiqh_count
  FROM public.knowledge_items ki
  WHERE ki.publication_state = 'PUBLISHED'
    AND ki.domain = 'FIQH'
    AND EXISTS (
      SELECT 1 FROM public.knowledge_item_versions kiv
      WHERE kiv.knowledge_item_id = ki.id AND kiv.production_eligible = true
    );

  SELECT count(*) INTO bad_fiqh_madhhab
  FROM public.knowledge_items ki
  WHERE ki.domain = 'FIQH'
    AND ki.publication_state = 'PUBLISHED'
    AND ki.madhhab IS NULL;

  SELECT count(*) INTO unpublished_eligible
  FROM public.knowledge_item_versions kiv
  JOIN public.knowledge_items ki ON ki.id = kiv.knowledge_item_id
  WHERE kiv.production_eligible = true
    AND ki.publication_state <> 'PUBLISHED';

  SELECT count(*) INTO source_missing
  FROM public.knowledge_item_versions kiv
  JOIN public.knowledge_items ki ON ki.id = kiv.knowledge_item_id
  WHERE kiv.production_eligible = true
    AND ki.publication_state = 'PUBLISHED'
    AND NOT EXISTS (
      SELECT 1 FROM public.knowledge_item_sources kis
      WHERE kis.knowledge_item_version_id = kiv.id
    );

  IF total_count <> 211 THEN
    RAISE EXCEPTION 'KB denominator mismatch: expected 211 active items, got %', total_count;
  END IF;
  IF health_count <> 74 THEN
    RAISE EXCEPTION 'Health/Safety denominator mismatch: expected 74, got %', health_count;
  END IF;
  IF fiqh_count <> 137 THEN
    RAISE EXCEPTION 'Fiqh denominator mismatch: expected 137, got %', fiqh_count;
  END IF;
  IF bad_fiqh_madhhab <> 0 THEN
    RAISE EXCEPTION 'Found % published Fiqh items without an explicit Madhhab', bad_fiqh_madhhab;
  END IF;
  IF unpublished_eligible <> 0 THEN
    RAISE EXCEPTION 'Found % production-eligible versions attached to non-published items', unpublished_eligible;
  END IF;
  IF source_missing <> 0 THEN
    RAISE EXCEPTION 'Found % production-eligible versions without source metadata', source_missing;
  END IF;

  RAISE NOTICE 'KB LIVE GATE PASS: 211 active items = 74 Health/Safety + 137 Fiqh; publication/source gates clean.';
END $$;
