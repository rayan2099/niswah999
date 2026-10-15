-- MADHHAB CHANGE HISTORY: public.madhhab_history
--
-- Requirement 2 of the Madhhab/symptom/community integrity task: a
-- Madhhab change is not an ordinary profile preference, because it may
-- affect how previously recorded bleeding data is *interpreted*. This
-- migration adds an append-only audit log of every Madhhab
-- selection-state transition, per user, with an effective timestamp and
-- the previous value preserved.
--
-- This table records only a Layer-2 preference transition (which
-- Madhhab, when, from what) — it never touches `cycle_entries`,
-- `bleeding_episodes`, or `bleeding_observations`. Raw observations stay
-- exactly as entered; only the engine's live, always-recomputed Layer-3
-- interpretation (`CycleStatusEngine`/`MadhhabRuleEvaluator`, which take
-- the user's *current* Madhhab as a plain parameter on every call, never
-- cached) is affected by a change recorded here.
--
-- Append-only by design: SELECT/INSERT policies only. No UPDATE/DELETE
-- policy exists at all — not even for the row's own owner — matching an
-- audit log's integrity expectation. `MadhhabController` is the sole
-- writer (`lib/core/preferences/madhhab_controller.dart`'s
-- `_recordHistory`), called from both `selectMadhhab()` and
-- `selectUnknown()` immediately before they overwrite the in-memory
-- state, so every transition — including "I don't know" — is captured.
--
-- Guarded (IF EXISTS/IF NOT EXISTS) matching this repo's established
-- pattern (see 20260914120000_madhhab_authority_state.sql).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'users'
  ) THEN

    CREATE TABLE IF NOT EXISTS public.madhhab_history (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      previous_selection_state TEXT NOT NULL,
      previous_madhhab TEXT,
      new_selection_state TEXT NOT NULL,
      new_madhhab TEXT,
      -- Forward contract for the day a cached/versioned Fiqh assessment is
      -- introduced (none exists today — CycleStatusEngine recomputes
      -- fresh on every access) — recorded now so this table's rows are
      -- already correctly attributable to the ruleset version in force
      -- at the time of the change.
      ruleset_version TEXT NOT NULL DEFAULT 'v1-2026-09-09',
      -- Audit readability only (e.g. 'onboarding', 'settings_direct',
      -- 'resolution_guided') — no behavior depends on this value.
      source TEXT,
      changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'madhhab_history_previous_state_check'
    ) THEN
      ALTER TABLE public.madhhab_history
        ADD CONSTRAINT madhhab_history_previous_state_check
        CHECK (previous_selection_state IN ('unset', 'unknown', 'selected'));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'madhhab_history_new_state_check'
    ) THEN
      ALTER TABLE public.madhhab_history
        ADD CONSTRAINT madhhab_history_new_state_check
        CHECK (new_selection_state IN ('unset', 'unknown', 'selected'));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'madhhab_history_previous_value_check'
    ) THEN
      ALTER TABLE public.madhhab_history
        ADD CONSTRAINT madhhab_history_previous_value_check
        CHECK (previous_madhhab IS NULL OR lower(previous_madhhab) IN ('hanafi', 'maliki', 'shafii', 'hanbali'));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'madhhab_history_new_value_check'
    ) THEN
      ALTER TABLE public.madhhab_history
        ADD CONSTRAINT madhhab_history_new_value_check
        CHECK (new_madhhab IS NULL OR lower(new_madhhab) IN ('hanafi', 'maliki', 'shafii', 'hanbali'));
    END IF;

    CREATE INDEX IF NOT EXISTS idx_madhhab_history_user_id_changed_at
      ON public.madhhab_history(user_id, changed_at DESC);

    ALTER TABLE public.madhhab_history ENABLE ROW LEVEL SECURITY;

  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'madhhab_history'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE tablename = 'madhhab_history'
        AND policyname = 'Users can read their own madhhab_history'
    ) THEN
      CREATE POLICY "Users can read their own madhhab_history"
        ON public.madhhab_history
        FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE tablename = 'madhhab_history'
        AND policyname = 'Users can insert their own madhhab_history'
    ) THEN
      CREATE POLICY "Users can insert their own madhhab_history"
        ON public.madhhab_history
        FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
  END IF;
END $$;
