-- DAILY/BACKFILL OBSERVATION, CONTINUATION-UNCERTAIN, AND BASELINE
-- ESTIMATE — the remaining canonical mutation operations Hardening 5
-- requires now that direct client INSERT/UPDATE on bleeding_episodes,
-- bleeding_observations, and cycle_baselines is revoked entirely (see
-- the schema migration). Commit D1 (daily check-in) and D4 (backfill)
-- are the same underlying operation from the database's point of view —
-- an immutable new fact attached to an OPEN episode — differing only in
-- which `observed_date`/`source` the caller passes (exactly the same
-- split `start_bleeding_episode` already establishes for "today" vs. a
-- backdated start); one shared RPC serves both rather than duplicating
-- near-identical validation twice.
--
-- All three are `SECURITY DEFINER` with an explicit `SET search_path`
-- (RLS is bypassed; every check below is self-contained and does not
-- depend on RLS visibility — each derives `v_user_id` from `auth.uid()`
-- exclusively and never trusts a caller-supplied user id). `EXECUTE` is
-- revoked from `PUBLIC` and re-granted only to `authenticated`.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_episodes'
  ) THEN

    -- record_bleeding_observation — Commits D1 (daily check-in's YES
    -- answer) and D4 (backfill: observed_date in the past, reported_at
    -- defaults to the real insert time via the column's own DEFAULT
    -- now(), so the gap between them is always genuine, never
    -- fabricated). Never accepts `supersedes_id` — a correction to an
    -- existing fact MUST go through `correct_observation` instead; this
    -- keeps "add a new event" and "correct a prior one" as two distinct
    -- operations rather than one INSERT path branching on a parameter
    -- (Hardening 2's own stated principle, applied here too). Future-
    -- date rejection and the open-episode requirement are also enforced
    -- by `bleeding_observations_validate_insert`, which still runs
    -- regardless of this function's own SECURITY DEFINER status — the
    -- explicit checks below exist to fail with a specific, actionable
    -- message rather than relying solely on the trigger's.
    -- Closure Blocker 4: drops the old 11-parameter overload (p_source,
    -- caller-trusted) before creating the new one below — see
    -- start_bleeding_episode's identical note.
    DROP FUNCTION IF EXISTS public.record_bleeding_observation(
      uuid, uuid, date, text, text, text, integer, timestamptz, text,
      jsonb, text
    );

    CREATE OR REPLACE FUNCTION public.record_bleeding_observation(
      p_client_operation_id uuid,
      p_episode_id uuid,
      p_observed_date date,
      p_precision text,
      p_flow text,
      p_utc_offset_minutes integer,
      p_observed_time timestamptz DEFAULT NULL,
      p_timezone text DEFAULT NULL,
      p_symptoms jsonb DEFAULT NULL,
      p_notes text DEFAULT NULL
    )
    RETURNS TABLE (observation_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_episode_user_id uuid;
      v_episode_status text;
      v_existing_id uuid;
      v_new_id uuid;
      v_local_today date;
      v_derived_source text;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION
          'record_bleeding_observation requires an authenticated user';
      END IF;

      -- Idempotent replay: this exact operation already succeeded.
      SELECT id INTO v_existing_id
      FROM public.bleeding_observations
      WHERE client_operation_id = p_client_operation_id AND user_id = v_user_id;

      IF v_existing_id IS NOT NULL THEN
        RETURN QUERY SELECT v_existing_id;
        RETURN;
      END IF;

      SELECT user_id, lifecycle_status INTO v_episode_user_id, v_episode_status
      FROM public.bleeding_episodes
      WHERE id = p_episode_id;

      IF v_episode_user_id IS NULL OR v_episode_user_id <> v_user_id THEN
        RAISE EXCEPTION
          'episode % does not exist or does not belong to the calling user',
          p_episode_id;
      END IF;
      IF v_episode_status <> 'open' THEN
        RAISE EXCEPTION
          'cannot add a new observation to episode % — it is not open '
          '(use correct_observation for a correction to existing history)',
          p_episode_id;
      END IF;

      v_local_today := ((now() AT TIME ZONE 'UTC')
        + make_interval(mins => p_utc_offset_minutes))::date;
      IF p_observed_date > v_local_today THEN
        RAISE EXCEPTION
          'observed_date cannot be in the future (got %, local today is %)',
          p_observed_date, v_local_today;
      END IF;

      -- Closure Blocker 5 — precision/timestamp consistency, mirroring
      -- every other write RPC's identical checks.
      IF p_precision = 'date_only' AND p_observed_time IS NOT NULL THEN
        RAISE EXCEPTION 'observed_time must be null when precision is date_only';
      END IF;
      IF p_precision IN ('exact_time', 'approximate_time')
        AND p_observed_time IS NULL
      THEN
        RAISE EXCEPTION 'observed_time is required when precision is %', p_precision;
      END IF;

      -- Closure Blocker 4 — derived here, never trusted from the caller;
      -- see start_bleeding_episode's identical rationale. This one
      -- function serves both D1 (today's check-in) and D4 (backfill), so
      -- the same today-vs-past comparison already used for future-date
      -- rejection is what distinguishes them.
      v_derived_source := CASE WHEN p_observed_date = v_local_today
        THEN 'user_observed' ELSE 'user_reported_historical' END;

      INSERT INTO public.bleeding_observations (
        user_id, episode_id, observed_date, observed_time, precision, flow,
        source, timezone, utc_offset_minutes, symptoms, notes,
        client_operation_id
      ) VALUES (
        v_user_id, p_episode_id, p_observed_date, p_observed_time, p_precision,
        p_flow, v_derived_source, p_timezone, p_utc_offset_minutes, p_symptoms,
        p_notes, p_client_operation_id
      ) RETURNING id INTO v_new_id;

      RETURN QUERY SELECT v_new_id;
    END;
    $function$;

    REVOKE ALL ON FUNCTION public.record_bleeding_observation(
      uuid, uuid, date, text, text, integer, timestamptz, text, jsonb, text
    ) FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION public.record_bleeding_observation(
      uuid, uuid, date, text, text, integer, timestamptz, text, jsonb, text
    ) TO authenticated;

    -- set_continuation_uncertain — Commit D1's "I'M NOT SURE" daily
    -- check-in answer (Section 9/15). Never closes the episode, never
    -- fabricates a bleeding=true/false observation — only records that
    -- continuation itself is unresolved. No `client_operation_id`:
    -- unlike every other RPC here, this is a pure state assignment, not
    -- an event append — repeating it is naturally, harmlessly
    -- idempotent (setting the same value twice creates no duplicate row
    -- to de-duplicate against), so the machinery the other RPCs need to
    -- distinguish "genuine retry" from "new request" does not apply.
    CREATE OR REPLACE FUNCTION public.set_continuation_uncertain(
      p_episode_id uuid
    )
    RETURNS TABLE (episode_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_episode_user_id uuid;
      v_episode_status text;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION
          'set_continuation_uncertain requires an authenticated user';
      END IF;

      SELECT user_id, lifecycle_status INTO v_episode_user_id, v_episode_status
      FROM public.bleeding_episodes
      WHERE id = p_episode_id
      FOR UPDATE;

      IF v_episode_user_id IS NULL OR v_episode_user_id <> v_user_id THEN
        RAISE EXCEPTION
          'episode % does not exist or does not belong to the calling user',
          p_episode_id;
      END IF;
      IF v_episode_status <> 'open' THEN
        RAISE EXCEPTION 'episode % is not open', p_episode_id;
      END IF;

      UPDATE public.bleeding_episodes
      SET continuation_certainty = 'uncertain'
      WHERE id = p_episode_id;

      RETURN QUERY SELECT p_episode_id;
    END;
    $function$;

    REVOKE ALL ON FUNCTION public.set_continuation_uncertain(uuid) FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION public.set_continuation_uncertain(uuid)
      TO authenticated;

    -- save_baseline_estimate — replaces CycleBaselineRepositoryImpl's
    -- former direct INSERT into cycle_baselines now that the table
    -- revokes client INSERT entirely. Always a new row (Blocker 9): a
    -- changed estimate never overwrites the old one.
    CREATE OR REPLACE FUNCTION public.save_baseline_estimate(
      p_client_operation_id uuid,
      p_usual_bleeding_duration_days integer DEFAULT NULL,
      p_usual_cycle_length_days integer DEFAULT NULL
    )
    RETURNS TABLE (baseline_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_existing_id uuid;
      v_new_id uuid;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'save_baseline_estimate requires an authenticated user';
      END IF;

      SELECT id INTO v_existing_id
      FROM public.cycle_baselines
      WHERE client_operation_id = p_client_operation_id AND user_id = v_user_id;

      IF v_existing_id IS NOT NULL THEN
        RETURN QUERY SELECT v_existing_id;
        RETURN;
      END IF;

      INSERT INTO public.cycle_baselines (
        user_id, usual_bleeding_duration_days, usual_cycle_length_days,
        client_operation_id
      ) VALUES (
        v_user_id, p_usual_bleeding_duration_days, p_usual_cycle_length_days,
        p_client_operation_id
      ) RETURNING id INTO v_new_id;

      RETURN QUERY SELECT v_new_id;
    END;
    $function$;

    REVOKE ALL ON FUNCTION public.save_baseline_estimate(uuid, integer, integer)
      FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION public.save_baseline_estimate(uuid, integer, integer)
      TO authenticated;

  END IF;
END $$;
