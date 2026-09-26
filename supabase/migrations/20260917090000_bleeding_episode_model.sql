-- BLEEDING EPISODE / OBSERVATION MODEL
--
-- Niswah Core Menstrual Data Integrity & Active Bleeding Journey charter,
-- Commit A. Establishes the first-class, provenance-aware entities the
-- charter's central doctrine requires and the flat `cycle_entries` table
-- cannot express: an explicit episode lifecycle, immutable observations
-- with a revision chain for corrections, temporal precision, and a
-- genuine "estimate" (never observed history) history for a user's usual
-- duration/cycle length.
--
-- PR #4 hardening pass (2026-09-18): this file has never been applied to
-- any real environment (only local, torn-down-every-time reconstructions
-- during development) — a hostile self-review, and then a critical
-- review of that review, found the original design still had real
-- integrity gaps. Rewritten in place rather than layered with follow-up
-- ALTERs, exactly like the earlier RLS/constraint fixes: there is no
-- persisted state anywhere that has the old shape, so there is nothing
-- to migrate away from.
--
-- Lifecycle redesign (Blocker 5): the original active/ended/uncertain
-- three-way conflated two independent questions — is the episode still
-- open at all, and is her continuation within it *confirmed or
-- uncertain*. That meant "I'm not sure" (marking uncertain) silently
-- vacated the one-active-episode slot, since the old unique index only
-- protected `status = 'active'` — a second "start" could then be created
-- while the first was still genuinely unresolved. Split into two
-- orthogonal columns: `lifecycle_status` (open/ended) and
-- `continuation_certainty` (confirmed/uncertain, meaningful only while
-- open). The one-per-user uniqueness now covers every open episode
-- regardless of certainty.
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
--
-- PR #4 final implementation wave, Hardening 5 — ONE CANONICAL MUTATION
-- BOUNDARY: a review found that even after Hardening 2 introduced
-- `correct_observation` as "the" controlled correction path, an ordinary
-- authenticated client could still satisfy `bleeding_observations_validate_insert`'s
-- own rules with a direct table INSERT (any row with `supersedes_id` set
-- passed the trigger same as a call through the RPC) — the RPC was
-- never actually the *sole* authority, just the officially-documented
-- one. All three canonical tables now REVOKE every client-facing
-- INSERT/UPDATE/DELETE grant entirely (SELECT remains, gated by the
-- existing RLS policies below); every mutation goes through a
-- SECURITY DEFINER RPC instead (see the RPC migrations from
-- 20260917100000 onward). RLS policies for INSERT/UPDATE are left in
-- place as documentation of intent (and because dropping them entirely
-- would be a larger, non-additive change with no behavioral benefit once
-- the grants that would have used them are gone) but are now
-- structurally unreachable by an ordinary client — only the RPCs, which
-- bypass RLS as SECURITY DEFINER, can actually write.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'users'
  ) THEN

    -- 1. bleeding_episodes — the explicit lifecycle entity the charter
    --    requires in place of re-deriving "currently bleeding since when"
    --    from raw rows on every read. `start_date`/`end_date` are always
    --    the honest, factual calendar dates the user reported;
    --    `*_precision` records how exact that report actually was (never
    --    silently promoted to `exact_time`); `*_source` distinguishes a
    --    live, same-day report from a historical/backfilled one, matching
    --    data classes 1/2 of the charter's 7-class taxonomy.
    --
    --    `client_operation_id`/`end_client_operation_id` (Blocker 1/2):
    --    the client generates a fresh UUID once per logical "start" or
    --    "end" action. Retrying the exact same operation (response lost,
    --    app killed mid-request, a genuine double-tap) is detected by the
    --    RPC via these columns and returns the original result instead of
    --    erroring or duplicating — see the start/end RPC migrations.
    --    Unlike a plain unique-constraint rejection, this actually proves
    --    a retry is the *same* operation rather than merely rejecting a
    --    second one.
    CREATE TABLE IF NOT EXISTS public.bleeding_episodes (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      lifecycle_status text NOT NULL DEFAULT 'open',
      continuation_certainty text,
      start_date date NOT NULL,
      start_precision text NOT NULL,
      start_time timestamptz,
      start_source text NOT NULL,
      end_date date,
      end_precision text,
      end_time timestamptz,
      end_source text,
      superseded_by uuid REFERENCES public.bleeding_episodes(id),
      client_operation_id uuid,
      end_client_operation_id uuid,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT bleeding_episodes_lifecycle_status_check
        CHECK (lifecycle_status IN ('open', 'ended')),
      CONSTRAINT bleeding_episodes_continuation_certainty_check
        CHECK (continuation_certainty IS NULL
          OR continuation_certainty IN ('confirmed', 'uncertain')),
      -- Continuation certainty is only ever meaningful while the episode
      -- is open — "I'm not sure [if it has ended]" (Section 9's NOT SURE
      -- branch) never itself closes the episode, and an ended episode has
      -- nothing left to be uncertain about.
      CONSTRAINT bleeding_episodes_continuation_consistency_check
        CHECK (
          (lifecycle_status = 'open' AND continuation_certainty IS NOT NULL)
          OR (lifecycle_status = 'ended' AND continuation_certainty IS NULL)
        ),
      CONSTRAINT bleeding_episodes_precision_check
        CHECK (start_precision IN ('exact_time', 'approximate_time', 'date_only')
          AND (end_precision IS NULL
            OR end_precision IN ('exact_time', 'approximate_time', 'date_only'))),
      CONSTRAINT bleeding_episodes_source_check
        CHECK (start_source IN ('user_observed', 'user_reported_historical')
          AND (end_source IS NULL
            OR end_source IN ('user_observed', 'user_reported_historical'))),
      CONSTRAINT bleeding_episodes_end_after_start_check
        CHECK (end_date IS NULL OR end_date >= start_date),
      -- end_precision/end_source must be present exactly when there is a
      -- real end to describe — never a dangling value with no end_date,
      -- never an ended episode missing them.
      CONSTRAINT bleeding_episodes_end_metadata_consistency_check
        CHECK (
          (end_date IS NULL AND end_precision IS NULL AND end_source IS NULL)
          OR (end_date IS NOT NULL AND end_precision IS NOT NULL AND end_source IS NOT NULL)
        ),
      -- A row must never claim to supersede itself.
      CONSTRAINT bleeding_episodes_no_self_supersede_check
        CHECK (superseded_by IS NULL OR superseded_by <> id)
    );

    -- One OPEN episode per user (Blocker 5) — covers both `confirmed` and
    -- `uncertain` continuation, so "I'm not sure" can never silently
    -- vacate the slot and let a second, genuinely concurrent episode
    -- start. Ended episodes are unrestricted since real corrections/
    -- backfill can legitimately create several over time.
    CREATE UNIQUE INDEX IF NOT EXISTS bleeding_episodes_one_open_per_user
      ON public.bleeding_episodes (user_id) WHERE lifecycle_status = 'open';

    -- Idempotency keys (Blocker 1/2) — unique only when present, since
    -- not every write path necessarily supplies one.
    CREATE UNIQUE INDEX IF NOT EXISTS bleeding_episodes_client_operation_id_unique
      ON public.bleeding_episodes (client_operation_id)
      WHERE client_operation_id IS NOT NULL;
    CREATE UNIQUE INDEX IF NOT EXISTS bleeding_episodes_end_client_operation_id_unique
      ON public.bleeding_episodes (end_client_operation_id)
      WHERE end_client_operation_id IS NOT NULL;

    CREATE INDEX IF NOT EXISTS bleeding_episodes_user_start_idx
      ON public.bleeding_episodes (user_id, start_date DESC);

    -- Closure Blocker 5 — precision/timestamp consistency: `date_only`
    -- must never carry a precise timestamp it never actually reported
    -- (that would silently claim more exactness than was given), and
    -- `exact_time`/`approximate_time` must never claim precision while
    -- carrying no time at all (the opposite fabrication). Enforced at
    -- the DB layer, not merely by RPC validation, so a direct write —
    -- if one were ever legitimately possible — could not bypass it
    -- either.
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'bleeding_episodes_start_precision_time_check'
    ) THEN
      ALTER TABLE public.bleeding_episodes
        ADD CONSTRAINT bleeding_episodes_start_precision_time_check
        CHECK (
          (start_precision = 'date_only' AND start_time IS NULL)
          OR (start_precision IN ('exact_time', 'approximate_time')
            AND start_time IS NOT NULL)
        );
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'bleeding_episodes_end_precision_time_check'
    ) THEN
      ALTER TABLE public.bleeding_episodes
        ADD CONSTRAINT bleeding_episodes_end_precision_time_check
        CHECK (
          end_precision IS NULL
          OR (end_precision = 'date_only' AND end_time IS NULL)
          OR (end_precision IN ('exact_time', 'approximate_time')
            AND end_time IS NOT NULL)
        );
    END IF;

    ALTER TABLE public.bleeding_episodes ENABLE ROW LEVEL SECURITY;

    -- A single blanket `USING/WITH CHECK` policy with no `FOR` clause
    -- defaults to `FOR ALL` in Postgres — wrong here. Episodes DO need to
    -- transition over time (open -> ended, marking continuation
    -- uncertain), so SELECT/INSERT/UPDATE are legitimate; DELETE is
    -- deliberately withheld — episode history must not be destructible by
    -- a direct table call (account-deletion cascade runs as a privileged
    -- role and is unaffected by this).
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'bleeding_episodes'
        AND policyname = 'bleeding_episodes_select_own'
    ) THEN
      CREATE POLICY bleeding_episodes_select_own ON public.bleeding_episodes
        FOR SELECT USING (public.can_access_user(user_id));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'bleeding_episodes'
        AND policyname = 'bleeding_episodes_insert_own'
    ) THEN
      CREATE POLICY bleeding_episodes_insert_own ON public.bleeding_episodes
        FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'bleeding_episodes'
        AND policyname = 'bleeding_episodes_update_own'
    ) THEN
      CREATE POLICY bleeding_episodes_update_own ON public.bleeding_episodes
        FOR UPDATE USING (public.can_access_user(user_id))
        WITH CHECK (auth.uid() = user_id);
    END IF;

    -- Blocker 8 established column-level UPDATE (start evidence must not
    -- be freely mutable even where UPDATE was otherwise allowed).
    -- PR #4 final implementation wave, Hardening 5 — ONE CANONICAL
    -- MUTATION BOUNDARY: that column-level grant was still a grant. Every
    -- mutation now goes through a validated, SECURITY DEFINER RPC
    -- (start/end/onboarding/correction/continuation-uncertain), so an
    -- ordinary authenticated client has no legitimate reason to issue a
    -- direct table-level INSERT/UPDATE/DELETE against this table at all
    -- — not even on the columns a legitimate transition touches. RLS
    -- policies above remain in force for the RPCs' own internal
    -- SELECTs/writes are unaffected by these client-facing grants
    -- (SECURITY DEFINER functions run under the function owner's
    -- privileges, not the caller's), and remain as documentation of the
    -- row-level intent even though the column-level grant they'd gate is
    -- now gone. `anon` never had a legitimate reason to write here in the
    -- first place — every policy requires `auth.uid() = user_id`, which
    -- an anonymous session can never satisfy — so its grants are
    -- withdrawn entirely rather than left as a harmless-in-practice but
    -- unnecessary surface.
    REVOKE INSERT, UPDATE, DELETE ON public.bleeding_episodes FROM authenticated;
    REVOKE ALL ON public.bleeding_episodes FROM anon;

    GRANT SELECT ON TABLE public.bleeding_episodes TO authenticated;
    GRANT ALL ON TABLE public.bleeding_episodes TO service_role;

    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = 'bleeding_episodes_set_updated_at'
    ) THEN
      CREATE TRIGGER bleeding_episodes_set_updated_at
        BEFORE UPDATE ON public.bleeding_episodes
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;

    -- 2. bleeding_observations — one immutable fact per row. A correction
    --    never overwrites a row in place (Section 17); it inserts a new
    --    row whose `supersedes_id` points at the one it corrects. `flow`
    --    includes 'uncertain' (a daily check-in's "I'm not sure" response,
    --    Section 14/15) distinct from 'none' (an explicit "not bleeding
    --    today"), so an unanswered check-in is never confused with either.
    --    `reported_at` vs `observed_date` makes backfill distance visible
    --    (Section 16) without a redundant, potentially-contradicting
    --    "is this backfilled" flag.
    --
    --    Blocker 7 — `timezone` (a best-effort IANA identifier, or a
    --    platform abbreviation when that's genuinely all that is
    --    available — nullable, metadata only, never used in a
    --    computation) is now separate from `utc_offset_minutes` (always
    --    reliably obtainable from the platform, exact for the instant
    --    reported, and the only field local-date-boundary math is ever
    --    based on). A named zone string can be wrong/ambiguous
    --    ("AST"/"GMT+3"); a numeric UTC offset captured at report time
    --    cannot.
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
      timezone text,
      utc_offset_minutes integer NOT NULL,
      symptoms jsonb,
      notes text,
      supersedes_id uuid REFERENCES public.bleeding_observations(id),
      client_operation_id uuid,
      created_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT bleeding_observations_precision_check
        CHECK (precision IN ('exact_time', 'approximate_time', 'date_only')),
      CONSTRAINT bleeding_observations_flow_check
        CHECK (flow IN ('uncertain', 'none', 'spotting', 'light', 'medium', 'heavy')),
      CONSTRAINT bleeding_observations_source_check
        CHECK (source IN ('user_observed', 'user_reported_historical')),
      CONSTRAINT bleeding_observations_utc_offset_range_check
        CHECK (utc_offset_minutes BETWEEN -720 AND 840),
      -- A row must never claim to supersede itself.
      CONSTRAINT bleeding_observations_no_self_supersede_check
        CHECK (supersedes_id IS NULL OR supersedes_id <> id)
      -- No-future-observation is enforced at the canonical RPC layer
      -- (Blocker 10), not here: Postgres CHECK constraints must be
      -- immutable and cannot call now(); a plain INSERT (a daily
      -- check-in observation added directly, not through start/end) is
      -- still validated by the inserting repository code before it ever
      -- reaches the database. See docs/menstrual-data-integrity-contract.md.
    );

    -- A revision chain has one tip: prevents two different corrections
    -- forking off the same prior observation (Section 43's "invalid/self/
    -- cyclic supersession" case) and, since a row can only reference a
    -- prior id that already exists, trivially prevents cycles too.
    CREATE UNIQUE INDEX IF NOT EXISTS bleeding_observations_supersedes_once
      ON public.bleeding_observations (supersedes_id) WHERE supersedes_id IS NOT NULL;

    CREATE UNIQUE INDEX IF NOT EXISTS bleeding_observations_client_operation_id_unique
      ON public.bleeding_observations (client_operation_id)
      WHERE client_operation_id IS NOT NULL;

    CREATE INDEX IF NOT EXISTS bleeding_observations_episode_idx
      ON public.bleeding_observations (episode_id, observed_date);
    CREATE INDEX IF NOT EXISTS bleeding_observations_user_date_idx
      ON public.bleeding_observations (user_id, observed_date DESC);

    -- Closure Blocker 5 — same precision/timestamp consistency rule as
    -- bleeding_episodes' own start/end constraints above, applied here to
    -- every observation (daily check-in, backfill, episode start/end,
    -- correction, onboarding-reported history).
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'bleeding_observations_precision_time_check'
    ) THEN
      ALTER TABLE public.bleeding_observations
        ADD CONSTRAINT bleeding_observations_precision_time_check
        CHECK (
          (precision = 'date_only' AND observed_time IS NULL)
          OR (precision IN ('exact_time', 'approximate_time')
            AND observed_time IS NOT NULL)
        );
    END IF;

    ALTER TABLE public.bleeding_observations ENABLE ROW LEVEL SECURITY;

    -- Observations are genuinely insert-only for the regular
    -- authenticated policy: no UPDATE, no DELETE, at the database level,
    -- not just by application convention — corrections are a new row with
    -- `supersedes_id`, never an edit of the old one (Section 17).
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'bleeding_observations'
        AND policyname = 'bleeding_observations_select_own'
    ) THEN
      CREATE POLICY bleeding_observations_select_own ON public.bleeding_observations
        FOR SELECT USING (public.can_access_user(user_id));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'bleeding_observations'
        AND policyname = 'bleeding_observations_insert_own'
    ) THEN
      CREATE POLICY bleeding_observations_insert_own ON public.bleeding_observations
        FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    -- Hardening 5: no direct client INSERT either, even though this
    -- table was already insert-only for corrections/appends — the same
    -- "every mutation goes through a validated RPC" boundary applies to
    -- new facts as much as to updates. `record_bleeding_observation`,
    -- the start/end RPCs, `record_onboarding_menstrual_history`, and
    -- `correct_observation` are now the only INSERT paths, all SECURITY
    -- DEFINER.
    REVOKE INSERT ON public.bleeding_observations FROM authenticated;
    REVOKE ALL ON public.bleeding_observations FROM anon;

    GRANT SELECT ON TABLE public.bleeding_observations TO authenticated;
    GRANT ALL ON TABLE public.bleeding_observations TO service_role;

    -- Every INSERT into bleeding_observations, from whichever code path —
    -- addObservation (daily check-ins, corrections, backfill), the
    -- start/end RPCs, or a direct REST-style call this Dart layer never
    -- wrote — passes through this single validation point (PR #4
    -- completion wave, Fix C: "no direct client method may bypass
    -- invariants enforced by another canonical path"). SECURITY DEFINER
    -- (explicit search_path, matching `create_user_profile()`) so its own
    -- lookups always see the true row regardless of who is asking — the
    -- ownership check below depends on this; see its own note for the
    -- exact cross-account defect this closes.
    --
    -- Checks, in order:
    -- 1. Ownership — an observation's user_id must match its episode's
    --    true owner. Nothing else verifies this; RLS only checks the
    --    observation's own user_id column, not the relationship. Originally
    --    written as a plain (non-DEFINER) trigger, which meant its own
    --    internal SELECT was itself subject to
    --    `bleeding_episodes_select_own`'s RLS policy — hiding another
    --    user's episode from the caller made a genuine cross-account
    --    attempt evaluate `NEW.user_id <> NULL` (NULL, not TRUE) and
    --    silently succeed. Confirmed and reproduced before this fix.
    -- 2. Episode open/ended compatibility — PR #4 completion wave,
    --    Hardening 2: an ended episode accepts ZERO new facts, with no
    --    exception. The earlier version special-cased `end_bleeding_episode`'s
    --    own closing observation (`flow = 'none' AND observed_date =
    --    end_date`) — a real structural loophole, since any owning caller
    --    could satisfy that same shape directly. `end_bleeding_episode`
    --    now inserts its closing observation *before* transitioning the
    --    episode to ended (see that migration), so it never needs an
    --    exception here at all: the episode is still genuinely `open` at
    --    the moment that INSERT runs. What an ended episode *does* still
    --    accept is a genuine correction — `NEW.supersedes_id IS NOT NULL`,
    --    itself validated below to reference a real prior fact belonging
    --    to this same user and episode. A correction of history is not
    --    the same operation as adding a new event, and must remain
    --    possible after an episode closes; a brand-new, unrelated fact
    --    must not.
    -- 3. No future observations — offset-based, mirroring the RPCs' own
    --    boundary check, so a plain INSERT (not routed through an RPC)
    --    cannot bypass it.
    -- 4. Correction-target validation — supersedes_id must reference an
    --    observation belonging to the same user AND the same episode;
    --    `bleeding_observations_supersedes_once` (a partial unique index)
    --    already prevents a fork/cycle at the chain-structure level.
    CREATE OR REPLACE FUNCTION public.bleeding_observations_validate_insert()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $trigger$
    DECLARE
      v_episode_user_id uuid;
      v_episode_status text;
      v_local_today date;
      v_supersedes_user_id uuid;
      v_supersedes_episode_id uuid;
    BEGIN
      SELECT user_id, lifecycle_status
        INTO v_episode_user_id, v_episode_status
      FROM public.bleeding_episodes
      WHERE id = NEW.episode_id;

      IF v_episode_user_id IS NULL THEN
        RAISE EXCEPTION 'episode % does not exist', NEW.episode_id;
      END IF;

      IF NEW.user_id <> v_episode_user_id THEN
        RAISE EXCEPTION
          'bleeding_observations.user_id must match its episode''s owner';
      END IF;

      IF v_episode_status = 'ended' AND NEW.supersedes_id IS NULL THEN
        RAISE EXCEPTION
          'cannot add a new fact to an ended episode (%) — only a '
          'correction (supersedes_id) is permitted', NEW.episode_id;
      END IF;

      v_local_today := ((now() AT TIME ZONE 'UTC')
        + make_interval(mins => NEW.utc_offset_minutes))::date;
      IF NEW.observed_date > v_local_today THEN
        RAISE EXCEPTION
          'observed_date cannot be in the future (got %, local today is %)',
          NEW.observed_date, v_local_today;
      END IF;

      IF NEW.supersedes_id IS NOT NULL THEN
        SELECT user_id, episode_id INTO v_supersedes_user_id, v_supersedes_episode_id
        FROM public.bleeding_observations
        WHERE id = NEW.supersedes_id;

        IF v_supersedes_user_id IS NULL THEN
          RAISE EXCEPTION 'supersedes_id % does not exist', NEW.supersedes_id;
        END IF;
        IF v_supersedes_user_id <> NEW.user_id THEN
          RAISE EXCEPTION
            'a correction must belong to the same user as the observation it supersedes';
        END IF;
        IF v_supersedes_episode_id <> NEW.episode_id THEN
          RAISE EXCEPTION
            'a correction must belong to the same episode as the observation it supersedes';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $trigger$;

    -- Replaces the earlier, narrower
    -- bleeding_observations_check_episode_owner_trigger — same slot, wider
    -- function. DROP+CREATE (not achievable via a mere function
    -- CREATE OR REPLACE, since the trigger itself still points at the old
    -- function name) is safe here precisely because nothing has ever run
    -- this migration against a real environment.
    DROP TRIGGER IF EXISTS bleeding_observations_check_episode_owner_trigger
      ON public.bleeding_observations;
    DROP FUNCTION IF EXISTS public.bleeding_observations_check_episode_owner();

    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = 'bleeding_observations_validate_insert_trigger'
    ) THEN
      CREATE TRIGGER bleeding_observations_validate_insert_trigger
        BEFORE INSERT ON public.bleeding_observations
        FOR EACH ROW EXECUTE FUNCTION public.bleeding_observations_validate_insert();
    END IF;

    -- 3. cycle_baselines — a user's stated USUAL duration/cycle length.
    --    Class 3 of the taxonomy (USER_REPORTED_ESTIMATE): never itself
    --    an observation. Blocker 9 — an in-place-upsertable single row per
    --    user made every earlier estimate unrecoverable the moment she
    --    changed her answer, which breaks reproducibility for anything
    --    that may have used the *old* value (a prediction computed under
    --    the old estimate can no longer be explained). Redesigned as an
    --    append-only history: each answer is its own immutable row, and
    --    "the current baseline" is simply the most recent one by
    --    `reported_at`. Still never versioned as *observed* history —
    --    it is a history of *estimates*, a fundamentally different class.
    CREATE TABLE IF NOT EXISTS public.cycle_baselines (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      usual_bleeding_duration_days integer,
      usual_cycle_length_days integer,
      reported_at timestamptz NOT NULL DEFAULT now(),
      created_at timestamptz NOT NULL DEFAULT now(),
      -- PR #4 completion wave, Fix A: lets
      -- record_onboarding_menstrual_history recognize a retried operation
      -- and return the original row instead of inserting a duplicate
      -- baseline version — the same idempotency pattern already used by
      -- bleeding_episodes/bleeding_observations.
      client_operation_id uuid,
      -- Blocker 6 — these are technical/storage-abuse bounds only, never
      -- a clinical-normality assumption: a user reporting an unusual but
      -- real duration/cycle length must never be rejected for falling
      -- outside a "typical" range. Deliberately broad.
      CONSTRAINT cycle_baselines_duration_range_check
        CHECK (usual_bleeding_duration_days IS NULL
          OR usual_bleeding_duration_days BETWEEN 1 AND 365),
      CONSTRAINT cycle_baselines_length_range_check
        CHECK (usual_cycle_length_days IS NULL
          OR usual_cycle_length_days BETWEEN 1 AND 1000)
    );

    CREATE INDEX IF NOT EXISTS cycle_baselines_user_reported_idx
      ON public.cycle_baselines (user_id, reported_at DESC);

    CREATE UNIQUE INDEX IF NOT EXISTS cycle_baselines_client_operation_id_unique
      ON public.cycle_baselines (client_operation_id)
      WHERE client_operation_id IS NOT NULL;

    ALTER TABLE public.cycle_baselines ENABLE ROW LEVEL SECURITY;

    -- Append-only, matching bleeding_observations: SELECT/INSERT only,
    -- no UPDATE/DELETE — a new estimate is a new row, never an edit of an
    -- old one.
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'cycle_baselines'
        AND policyname = 'cycle_baselines_select_own'
    ) THEN
      CREATE POLICY cycle_baselines_select_own ON public.cycle_baselines
        FOR SELECT USING (public.can_access_user(user_id));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'cycle_baselines'
        AND policyname = 'cycle_baselines_insert_own'
    ) THEN
      CREATE POLICY cycle_baselines_insert_own ON public.cycle_baselines
        FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    -- Hardening 5: baseline estimates now go through the SECURITY
    -- DEFINER `save_baseline_estimate` RPC, not a direct client INSERT.
    REVOKE INSERT ON public.cycle_baselines FROM authenticated;
    REVOKE ALL ON public.cycle_baselines FROM anon;

    GRANT SELECT ON TABLE public.cycle_baselines TO authenticated;
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
