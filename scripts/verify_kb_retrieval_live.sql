\set ON_ERROR_STOP on

-- Live smoke tests for fail-closed retrieval behavior after seed/deploy.
DO $$
DECLARE
  n integer;
  wrong_madhhab integer;
BEGIN
  -- Fiqh must never return anything without an explicit Madhhab.
  SELECT count(*) INTO n
  FROM public.retrieve_knowledge_v1('FIQH','ar','ما أقل مدة الحيض؟',null,8);
  IF n <> 0 THEN
    RAISE EXCEPTION 'Fiqh retrieval returned % rows without a Madhhab', n;
  END IF;

  -- Arabic routing metadata must reach the verified Hanafi minimum-duration atom.
  SELECT count(*) INTO n
  FROM public.retrieve_knowledge_v1('FIQH','ar','ما أقل مدة أو قدر معتبر لصحة الحكم بالحيض؟','hanafi',8)
  WHERE knowledge_key = 'HNF-HAID-04';
  IF n = 0 THEN
    RAISE EXCEPTION 'Arabic Hanafi routing did not retrieve HNF-HAID-04';
  END IF;

  -- Explicit Madhhab filtering is hard: no other Madhhab may leak in.
  SELECT count(*) INTO wrong_madhhab
  FROM public.retrieve_knowledge_v1('FIQH','ar','ما أقل مدة أو قدر معتبر لصحة الحكم بالحيض؟','hanafi',8)
  WHERE madhhab <> 'hanafi';
  IF wrong_madhhab <> 0 THEN
    RAISE EXCEPTION 'Cross-Madhhab leak: % non-Hanafi rows returned in Hanafi retrieval', wrong_madhhab;
  END IF;

  -- Health retrieval should find the cycle-Day-1 atom for a direct English query.
  SELECT count(*) INTO n
  FROM public.retrieve_knowledge_v1('HEALTH','en','first day of menstrual bleeding cycle day one',null,8)
  WHERE knowledge_key = 'HL-MENS-001';
  IF n = 0 THEN
    RAISE EXCEPTION 'Health routing did not retrieve HL-MENS-001';
  END IF;

  -- An unrelated query must fail closed rather than returning arbitrary top rows.
  SELECT count(*) INTO n
  FROM public.retrieve_knowledge_v1('FIQH','en','electric car shopping list and tire pressure', 'hanafi', 8);
  IF n <> 0 THEN
    RAISE EXCEPTION 'Low-relevance Fiqh query returned % arbitrary KB rows', n;
  END IF;

  RAISE NOTICE 'KB RETRIEVAL GATE PASS: Madhhab, Arabic routing, health routing, and low-relevance fail-closed behavior verified.';
END $$;
