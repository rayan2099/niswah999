-- RECORD ONBOARDING MENSTRUAL HISTORY — RECONCILE WITH AN EXISTING OPEN
-- EPISODE INSTEAD OF BLINDLY INSERTING A SECOND ONE
--
-- Manual QA wave (2026-10-12), real staging data-integrity defect. The
-- previous version of this RPC always attempted to INSERT a new
-- bleeding_episodes row whenever p_start_date was given, with no regard
-- for whether the user already had one open. Since
-- bleeding_episodes_one_open_per_user is a real, intentional uniqueness
-- invariant (one actively-tracked episode per user, ever), that insert
-- then failed with a raw 23505 unique_violation — surfaced to the client
-- as an opaque "couldn't save" error, with no way to recover other than
-- abandoning the attempt. Confirmed this is a real, reachable scenario,
-- not merely test-account contamination: onboarding completion can be
-- retried, resumed after an interrupted flow, or re-entered after a
-- client-side reset of onboarding_completed while real menstrual data
-- already exists for that account.
--
-- New behavior when p_start_date is given and the user already has an
-- open episode (regardless of which operation created it):
--   - same start_date  -> treated as clearly the same episode. Reused
--     (its id is returned) without inserting a duplicate episode or
--     duplicate observation. Deliberately does NOT touch the existing
--     episode's own lifecycle_status/continuation_certainty/end_date/
--     client_operation_id — "add only missing compatible information"
--     is interpreted narrowly as the independent baseline write below,
--     never as silently overwriting fields on a record this operation
--     did not create and cannot know the full context of (it may have
--     been updated since by the dashboard or a different session).
--   - different start_date -> clearly NOT the same episode (an exact
--     date match is the only criterion used — no fuzzy "within N days"
--     guessing). Neither inserted nor mutated; instead the function
--     returns normally (no exception) with episode_conflict = true and
--     the conflicting episode's own id/start_date, so the caller can
--     show a real resolution flow instead of a generic failure.
--
-- The baseline write is unconditionally independent of the episode
-- outcome (there is no uniqueness constraint on cycle_baselines beyond
-- its own primary key — confirmed directly against staging) — it is
-- always attempted, so a conflicting/reused episode never blocks
-- unrelated baseline data from saving.
--
-- Both the episode and baseline parts are now independently idempotent
-- by their own `client_operation_id` match (replacing the previous
-- all-or-nothing early return, which meant a retry could never complete
-- *just* the part that hadn't been attempted yet) — calling this RPC
-- twice with the same operation id and the same payload can never
-- create a duplicate episode, a duplicate observation, or a duplicate
-- uniqueness failure, and never alters unrelated existing history.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_episodes'
  ) THEN

    -- Drops the previous 12-parameter/2-output-column overload before
    -- creating the new 5-output-column one below — CREATE OR REPLACE
    -- cannot change a function's output column list in place.
    DROP FUNCTION IF EXISTS public.record_onboarding_menstrual_history(
      uuid, integer, date, text, timestamptz, text, text, date, text,
      timestamptz, integer, integer
    );

    CREATE OR REPLACE FUNCTION public.record_onboarding_menstrual_history(
      p_client_operation_id uuid,
      p_utc_offset_minutes integer,
      p_start_date date DEFAULT NULL,
      p_start_precision text DEFAULT NULL,
      p_start_time timestamptz DEFAULT NULL,
      p_lifecycle_status text DEFAULT NULL,
      p_continuation_certainty text DEFAULT NULL,
      p_end_date date DEFAULT NULL,
      p_end_precision text DEFAULT NULL,
      p_end_time timestamptz DEFAULT NULL,
      p_usual_bleeding_duration_days integer DEFAULT NULL,
      p_usual_cycle_length_days integer DEFAULT NULL
    )
    RETURNS TABLE (
      episode_id uuid,
      baseline_id uuid,
      episode_conflict boolean,
      conflicting_episode_id uuid,
      conflicting_start_date date
    )
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_episode_id uuid;
      v_baseline_id uuid;
      v_episode_conflict boolean := false;
      v_conflicting_episode_id uuid;
      v_conflicting_start_date date;
      v_existing_open_id uuid;
      v_existing_open_start_date date;
      v_local_today date;
      v_derived_start_source text;
      v_derived_end_source text;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION
          'record_onboarding_menstrual_history requires an authenticated user';
      END IF;

      -- Episode part: idempotent replay by this exact operation id.
      SELECT e.id INTO v_episode_id
      FROM public.bleeding_episodes e
      WHERE e.client_operation_id = p_client_operation_id AND e.user_id = v_user_id;

      IF v_episode_id IS NULL AND p_start_date IS NOT NULL THEN
        v_local_today := ((now() AT TIME ZONE 'UTC')
          + make_interval(mins => p_utc_offset_minutes))::date;
        IF p_start_date > v_local_today THEN
          RAISE EXCEPTION
            'start_date cannot be in the future (got %, local today is %)',
            p_start_date, v_local_today;
        END IF;
        IF p_end_date IS NOT NULL AND p_end_date > v_local_today THEN
          RAISE EXCEPTION
            'end_date cannot be in the future (got %, local today is %)',
            p_end_date, v_local_today;
        END IF;
        IF p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
          RAISE EXCEPTION
            'end_date (%) precedes start_date (%)', p_end_date, p_start_date;
        END IF;

        IF p_start_precision = 'date_only' AND p_start_time IS NOT NULL THEN
          RAISE EXCEPTION 'start_time must be null when start_precision is date_only';
        END IF;
        IF p_start_precision IN ('exact_time', 'approximate_time')
          AND p_start_time IS NULL
        THEN
          RAISE EXCEPTION 'start_time is required when start_precision is %', p_start_precision;
        END IF;
        IF p_end_date IS NOT NULL THEN
          IF p_end_precision = 'date_only' AND p_end_time IS NOT NULL THEN
            RAISE EXCEPTION 'end_time must be null when end_precision is date_only';
          END IF;
          IF p_end_precision IN ('exact_time', 'approximate_time')
            AND p_end_time IS NULL
          THEN
            RAISE EXCEPTION 'end_time is required when end_precision is %', p_end_precision;
          END IF;
        END IF;

        -- The actual reconciliation check: does this user already have
        -- an open episode, from *any* operation (a previous onboarding
        -- attempt, the dashboard's Start Bleeding sheet, anything)?
        -- bleeding_episodes_one_open_per_user guarantees at most one.
        SELECT e.id, e.start_date INTO v_existing_open_id, v_existing_open_start_date
        FROM public.bleeding_episodes e
        WHERE e.user_id = v_user_id AND e.lifecycle_status = 'open'
        LIMIT 1;

        IF v_existing_open_id IS NOT NULL THEN
          IF v_existing_open_start_date = p_start_date THEN
            -- Clearly the same episode (exact date match — never a
            -- fuzzy/guessed match). Reused as-is; nothing inserted,
            -- nothing on the existing row touched.
            v_episode_id := v_existing_open_id;
          ELSE
            -- Clearly a different episode. Never inserted, never
            -- mutated, never silently guessed which one is "right" —
            -- the caller decides.
            v_episode_conflict := true;
            v_conflicting_episode_id := v_existing_open_id;
            v_conflicting_start_date := v_existing_open_start_date;
          END IF;
        ELSE
          v_derived_start_source := CASE WHEN p_start_date = v_local_today
            THEN 'user_observed' ELSE 'user_reported_historical' END;
          v_derived_end_source := CASE
            WHEN p_end_date IS NULL THEN NULL
            WHEN p_end_date = v_local_today THEN 'user_observed'
            ELSE 'user_reported_historical'
          END;

          INSERT INTO public.bleeding_episodes (
            user_id, lifecycle_status, continuation_certainty, start_date,
            start_precision, start_time, start_source, end_date, end_precision,
            end_time, end_source, client_operation_id
          ) VALUES (
            v_user_id, 'open', 'confirmed', p_start_date,
            p_start_precision, p_start_time, v_derived_start_source, p_end_date,
            p_end_precision, p_end_time, v_derived_end_source, p_client_operation_id
          ) RETURNING id INTO v_episode_id;

          INSERT INTO public.bleeding_observations (
            user_id, episode_id, observed_date, observed_time, precision, flow,
            source, utc_offset_minutes, client_operation_id
          ) VALUES (
            v_user_id, v_episode_id, p_start_date, p_start_time, p_start_precision,
            'uncertain', v_derived_start_source, p_utc_offset_minutes,
            p_client_operation_id
          );

          IF p_end_date IS NOT NULL THEN
            INSERT INTO public.bleeding_observations (
              user_id, episode_id, observed_date, observed_time, precision, flow,
              source, utc_offset_minutes
            ) VALUES (
              v_user_id, v_episode_id, p_end_date, p_end_time, p_end_precision,
              'none', v_derived_end_source, p_utc_offset_minutes
            );
          END IF;

          UPDATE public.bleeding_episodes
          SET lifecycle_status = p_lifecycle_status,
              continuation_certainty = p_continuation_certainty
          WHERE id = v_episode_id;
        END IF;
      END IF;

      -- Baseline part: independently idempotent by its own operation id
      -- — always attempted regardless of the episode outcome above, so
      -- a conflicting or reused episode never blocks unrelated baseline
      -- data from saving.
      SELECT b.id INTO v_baseline_id
      FROM public.cycle_baselines b
      WHERE b.client_operation_id = p_client_operation_id AND b.user_id = v_user_id;

      IF v_baseline_id IS NULL AND (
        p_usual_bleeding_duration_days IS NOT NULL
        OR p_usual_cycle_length_days IS NOT NULL
      ) THEN
        INSERT INTO public.cycle_baselines (
          user_id, usual_bleeding_duration_days, usual_cycle_length_days,
          client_operation_id
        ) VALUES (
          v_user_id, p_usual_bleeding_duration_days, p_usual_cycle_length_days,
          p_client_operation_id
        ) RETURNING id INTO v_baseline_id;
      END IF;

      RETURN QUERY SELECT
        v_episode_id, v_baseline_id, v_episode_conflict,
        v_conflicting_episode_id, v_conflicting_start_date;
    END;
    $function$;

    REVOKE ALL ON FUNCTION public.record_onboarding_menstrual_history(
      uuid, integer, date, text, timestamptz, text, text, date, text,
      timestamptz, integer, integer
    ) FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION public.record_onboarding_menstrual_history(
      uuid, integer, date, text, timestamptz, text, text, date, text,
      timestamptz, integer, integer
    ) TO authenticated;

  END IF;
END $$;
