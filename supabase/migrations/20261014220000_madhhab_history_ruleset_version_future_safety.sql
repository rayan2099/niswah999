-- MADHHAB HISTORY: future-safe ruleset_version resolution
--
-- Effective-dated Madhhab history task, governance item 2: the existing
-- `madhhab_history.ruleset_version` column only ever records the ruleset
-- version in force for the NEW side of a transition, never the PREVIOUS
-- side. That is harmless for every row written so far (there has only
-- ever been one ruleset value, MadhhabRuleEvaluator.rulesetVersion), but
-- is a structural gap for whenever a second ruleset version ships: a date
-- before a user's earliest-known transition would have no recorded way
-- to know what ruleset applied to her previously-selected Madhhab.
--
-- Fix: a new, nullable `previous_ruleset_version` column, populated going
-- forward by `MadhhabController._recordHistory` from the user's own prior
-- `madhhab_history` row (if one exists) at the moment of each NEW
-- transition -- "recording sufficient previous/new version information
-- on future transitions," per the governance decision, rather than
-- attempting to infer it later from nothing.
--
-- Existing rows are NOT backfilled -- this column is NULL for all of
-- them, and `MadhhabHistoryResolver`'s existing deterministic fallback
-- (the current global ruleset constant) continues to apply for those,
-- which is correct in practice today since only one ruleset value has
-- ever existed. No historical version is invented here.
--
-- Guarded (IF EXISTS/IF NOT EXISTS) matching this repo's established
-- pattern (see 20261007090000_madhhab_change_history.sql).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'madhhab_history'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'madhhab_history'
        AND column_name = 'previous_ruleset_version'
    ) THEN
      ALTER TABLE public.madhhab_history
        ADD COLUMN previous_ruleset_version TEXT;
    END IF;
  END IF;
END $$;
