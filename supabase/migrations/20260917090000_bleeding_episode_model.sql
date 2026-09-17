-- BLEEDING EPISODE / OBSERVATION MODEL
--
-- Niswah Core Menstrual Data Integrity & Active Bleeding Journey charter,
-- Commit A (2026-09-17). Establishes the first-class, provenance-aware
-- entities the charter's central doctrine requires and the flat
-- `cycle_entries` table cannot express: an explicit episode lifecycle
-- (active/ended/uncertain), immutable observations with a revision chain
-- for corrections, temporal precision, and a genuine "estimate" (never
-- observed history) table for a user's usual duration/cycle length.
--
-- These tables are additive and do not replace `cycle_entries` in this
-- migration. `cycle_entries` keeps its existing schema and every existing
-- consumer (calculation service, status engine, dashboard, AI/Fiqh
-- context, notifications, data export) keeps working unchanged. A new
-- `data_provenance` column is added to it (see step 5 below) purely so
-- those consumers can tell a legacy row (no corresponding observation
-- under this new model, provenance genuinely unknown) apart from a row
-- written going forward through the new repository. Full migration of
-- every consumer onto `bleeding_episodes` / `bleeding_observations`
-- directly is out of scope for this migration — see
-- docs/menstrual-data-integrity-contract.md for the transition plan.
--
-- Guarded (IF EXISTS / IF NOT EXISTS) per this repo's established pattern
-- (see 20260914120000_madhhab_authority_state.sql) — a fresh `supabase
-- start` applies supabase/migrations/ before the canonical baseline
-- defines `public.users`, so the guard makes this file a safe no-op there
-- and a real, idempotent set of DDL statements against production.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'users'
  ) THEN

    -- 1. bleeding_episodes — the explicit active/ended/uncertain lifecycle
    --    the charter requires in place of re-deriving "currently bleeding
    --    since when" from raw rows on every read. `start_date`/`end_date`
    --    are always the honest, factual calendar dates the user reported;
    --    `*_precision` records how exact that report actually was (never
    --    silently promoted to `exact_time`); `*_source` distinguishes a
    --    live, same-day report from a historical/backfilled one, matching
    --    data classes 1/2 of the charter's 7-class taxonomy.
    CREATE TABLE IF NOT EXISTS public.bleeding_episodes (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      status text NOT NULL DEFAULT 'active',
      start_date date NOT NULL,
      start_precision text NOT NULL,
      start_time timestamptz,
      start_source text NOT NULL,
      end_date date,
      end_precision text,
      end_time timestamptz,
      end_source text,
      superseded_by uuid REFERENCES public.bleeding_episodes(id),
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT bleeding_episodes_status_check
        CHECK (status IN ('active', 'ended', 'uncertain')),
      CONSTRAINT bleeding_episodes_precision_check
        CHECK (start_precision IN ('exact_time', 'approximate_time', 'date_only')
          AND (end_precision IS NULL
            OR end_precision IN ('exact_time', 'approximate_time', 'date_only'))),
      CONSTRAINT bleeding_episodes_source_check
        CHECK (start_source IN ('user_observed', 'user_reported_historical')
          AND (end_source IS NULL
            OR end_source IN ('user_observed', 'user_reported_historical'))),
      -- 'uncertain' represents "I'm not sure if it has ended" (Section 9's
      -- NOT SURE branch) — end_date stays null, distinct from 'ended'.
      CONSTRAINT bleeding_episodes_status_end_consistency_check
        CHECK (
          (status = 'ended' AND end_date IS NOT NULL)
          OR (status IN ('active', 'uncertain') AND end_date IS NULL)
        ),
      CONSTRAINT bleeding_episodes_end_after_start_check
        CHECK (end_date IS NULL OR end_date >= start_date)
    );

    -- One active episode per user (Section 38: never silently allow two
    -- concurrent active journeys). Ended/uncertain episodes are unrestricted
    -- since real corrections/backfill can legitimately create several.
    CREATE UNIQUE INDEX IF NOT EXISTS bleeding_episodes_one_active_per_user
      ON public.bleeding_episodes (user_id) WHERE status = 'active';

    CREATE INDEX IF NOT EXISTS bleeding_episodes_user_start_idx
      ON public.bleeding_episodes (user_id, start_date DESC);

    ALTER TABLE public.bleeding_episodes ENABLE ROW LEVEL SECURITY;

    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'bleeding_episodes'
        AND policyname = 'bleeding_episodes_own'
    ) THEN
      CREATE POLICY bleeding_episodes_own ON public.bleeding_episodes
        USING (public.can_access_user(user_id))
        WITH CHECK (auth.uid() = user_id);
    END IF;

    GRANT ALL ON TABLE public.bleeding_episodes TO anon;
    GRANT ALL ON TABLE public.bleeding_episodes TO authenticated;
    GRANT ALL ON TABLE public.bleeding_episodes TO service_role;

    -- 2. bleeding_observations — one immutable fact per row. A correction
    --    never overwrites a row in place (Section 17); it inserts a new
    --    row whose `supersedes_id` points at the one it corrects. `flow`
    --    includes 'uncertain' (a daily check-in's "I'm not sure" response,
    --    Section 14/15) distinct from 'none' (an explicit "not bleeding
    --    today"), so an unanswered check-in is never confused with either.
    --    `reported_at` vs `observed_date` makes backfill distance visible
    --    (Section 16) without a redundant, potentially-contradicting
    --    "is this backfilled" flag.
    CREATE TABLE IF NOT EXISTS public.bleeding_observations (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      episode_id uuid NOT NULL REFERENCES public.bleeding_episodes(id) ON DELETE CASCADE,
      observed_date date NOT NULL,
      observed_time timestamptz,
      precision text NOT NULL,
      flow text NOT NULL,
      source text NOT NULL,
      reported_at timestamptz NOT NULL DEFAULT now(),
      timezone text NOT NULL,
      symptoms jsonb,
      notes text,
      supersedes_id uuid REFERENCES public.bleeding_observations(id),
      created_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT bleeding_observations_precision_check
        CHECK (precision IN ('exact_time', 'approximate_time', 'date_only')),
      CONSTRAINT bleeding_observations_flow_check
        CHECK (flow IN ('uncertain', 'none', 'spotting', 'light', 'medium', 'heavy')),
      CONSTRAINT bleeding_observations_source_check
        CHECK (source IN ('user_observed', 'user_reported_historical'))
      -- No-future-observation is enforced at the application layer, not
      -- here: Postgres CHECK constraints must be immutable and cannot call
      -- now(), and "future" depends on the reporter's own timezone column
      -- on this same row. See docs/menstrual-data-integrity-contract.md.
    );

    -- A revision chain has one tip: prevents two different corrections
    -- forking off the same prior observation (Section 43's "invalid/self/
    -- cyclic supersession" case) and, since a row can only reference a
    -- prior id that already exists, trivially prevents cycles too.
    CREATE UNIQUE INDEX IF NOT EXISTS bleeding_observations_supersedes_once
      ON public.bleeding_observations (supersedes_id) WHERE supersedes_id IS NOT NULL;

    CREATE INDEX IF NOT EXISTS bleeding_observations_episode_idx
      ON public.bleeding_observations (episode_id, observed_date);
    CREATE INDEX IF NOT EXISTS bleeding_observations_user_date_idx
      ON public.bleeding_observations (user_id, observed_date DESC);

    ALTER TABLE public.bleeding_observations ENABLE ROW LEVEL SECURITY;

    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'bleeding_observations'
        AND policyname = 'bleeding_observations_own'
    ) THEN
      CREATE POLICY bleeding_observations_own ON public.bleeding_observations
        USING (public.can_access_user(user_id))
        WITH CHECK (auth.uid() = user_id);
    END IF;

    GRANT ALL ON TABLE public.bleeding_observations TO anon;
    GRANT ALL ON TABLE public.bleeding_observations TO authenticated;
    GRANT ALL ON TABLE public.bleeding_observations TO service_role;

    -- 3. cycle_baselines — a user's stated USUAL duration/cycle length.
    --    Class 3 of the taxonomy (USER_REPORTED_ESTIMATE): never itself an
    --    observation, and per Section 4 not versioned as history — the
    --    latest stated estimate is all that is meaningful, so a new answer
    --    simply replaces the old one (one row per user).
    CREATE TABLE IF NOT EXISTS public.cycle_baselines (
      user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
      usual_bleeding_duration_days integer,
      usual_cycle_length_days integer,
      reported_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT cycle_baselines_duration_range_check
        CHECK (usual_bleeding_duration_days IS NULL
          OR usual_bleeding_duration_days BETWEEN 1 AND 20),
      CONSTRAINT cycle_baselines_length_range_check
        CHECK (usual_cycle_length_days IS NULL
          OR usual_cycle_length_days BETWEEN 15 AND 90)
    );

    ALTER TABLE public.cycle_baselines ENABLE ROW LEVEL SECURITY;

    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'cycle_baselines'
        AND policyname = 'cycle_baselines_own'
    ) THEN
      CREATE POLICY cycle_baselines_own ON public.cycle_baselines
        USING (public.can_access_user(user_id))
        WITH CHECK (auth.uid() = user_id);
    END IF;

    GRANT ALL ON TABLE public.cycle_baselines TO anon;
    GRANT ALL ON TABLE public.cycle_baselines TO authenticated;
    GRANT ALL ON TABLE public.cycle_baselines TO service_role;

    -- 4. Nothing in this migration ever deletes or rewrites a row in
    --    `cycle_entries` (Section 34/64: additive, reversible, no lost
    --    history). Step 5 only adds a nullable-safe column with a
    --    backward-compatible default.
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'cycle_entries'
    ) THEN

      -- 5. data_provenance — lets existing consumers tell a legacy row
      --    (written before this model existed; whether it is a genuine
      --    manual log or an old onboarding-fabricated day can no longer be
      --    reliably determined, Section 33 — CRITICAL) apart from a row
      --    the new repository wrote going forward. Every existing row is
      --    explicitly backfilled to 'legacy_unverified', never silently
      --    assumed to be 'user_observed' — this is the honest default the
      --    charter requires, not a placeholder to fix later.
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'cycle_entries'
          AND column_name = 'data_provenance'
      ) THEN
        ALTER TABLE public.cycle_entries
          ADD COLUMN data_provenance text NOT NULL DEFAULT 'legacy_unverified';
      END IF;

      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'cycle_entries_data_provenance_check'
      ) THEN
        ALTER TABLE public.cycle_entries
          ADD CONSTRAINT cycle_entries_data_provenance_check
          CHECK (data_provenance IN (
            'legacy_unverified', 'user_observed', 'user_reported_historical'
          ));
      END IF;

      UPDATE public.cycle_entries SET data_provenance = 'legacy_unverified'
        WHERE data_provenance NOT IN (
          'legacy_unverified', 'user_observed', 'user_reported_historical'
        );

    END IF;

  END IF;
END $$;
