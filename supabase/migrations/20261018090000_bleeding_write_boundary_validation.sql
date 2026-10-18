-- BLEEDING WRITE-BOUNDARY VALIDATION (logging/sync hardening, proposed)
--
-- A review of how bleeding data is written (2026-10-18) found that the
-- canonical RPCs accepted several writes that leave the episode model
-- contradicting its own observations. Each was reproduced against a local
-- Postgres 16 reconstruction of the migration chain; the regression script
-- is test/logging_sync_hardening/sql/canonical_rpc_regression.sql.
--
-- CREATE OR REPLACE only — every signature is unchanged, so the existing
-- REVOKE/GRANT on each function is preserved and no client call changes.
-- No earlier migration is edited. Every new rejection is a plain RAISE
-- EXCEPTION (SQLSTATE P0001), which the app treats as a deterministic
-- rejection: a real error in the sheet, never "Saved on device — syncing",
-- and never auto-retried by the background sync.
--
-- 1. start_bleeding_episode — a new (open) episode may not start on or
--    before the end of an episode that already ended: an open episode from
--    D onward would overlap it.
-- 2. end_bleeding_episode — the end date may not precede bleeding she
--    already recorded in the same episode (an effective, non-superseded
--    observation with a bleeding flow after p_end_date).
-- 3. record_bleeding_observation — observed_date may not precede the
--    episode's start_date.
-- 4. correct_observation — a correction stays inside its episode's date
--    range; the episode's START observation can never be corrected to
--    `none`, its CLOSING observation can never be corrected to a bleeding
--    flow, and neither may move to a different date (the episode's own
--    start_date/end_date are derived from them and would silently
--    disagree).
-- 5. record_onboarding_menstrual_history — when she reports "started D,
--    ended E" and an OPEN episode with the same start date already exists,
--    the reused episode is now actually ended through end_bleeding_episode
--    (same validation, same atomic closing observation) instead of the end
--    being silently dropped. The idempotent replay also recognizes this
--    operation id as an episode's end_client_operation_id, so a retry
--    returns the same episode rather than inserting a second one.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_episodes'
  ) THEN

    -- 1 -----------------------------------------------------------------
    CREATE OR REPLACE FUNCTION public.start_bleeding_episode(
      p_client_operation_id uuid,
      p_start_date date,
      p_start_precision text,
      p_start_time timestamptz,
      p_flow text,
      p_observed_time timestamptz,
      p_precision text,
      p_timezone text,
      p_utc_offset_minutes integer,
      p_symptoms jsonb DEFAULT NULL,
      p_notes text DEFAULT NULL
    )
    RETURNS TABLE (episode_id uuid, observation_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_episode_id uuid;
      v_observation_id uuid;
      v_local_today date;
      v_derived_source text;
      v_overlapping_end date;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'start_bleeding_episode requires an authenticated user';
      END IF;

      -- Idempotent replay: this exact operation already succeeded.
      SELECT e.id INTO v_episode_id
      FROM public.bleeding_episodes e
      WHERE e.client_operation_id = p_client_operation_id AND e.user_id = v_user_id;

      IF v_episode_id IS NOT NULL THEN
        SELECT o.id INTO v_observation_id
        FROM public.bleeding_observations o
        WHERE o.client_operation_id = p_client_operation_id AND o.user_id = v_user_id;
        RETURN QUERY SELECT v_episode_id, v_observation_id;
        RETURN;
      END IF;

      v_local_today := ((now() AT TIME ZONE 'UTC')
        + make_interval(mins => p_utc_offset_minutes))::date;
      IF p_start_date > v_local_today THEN
        RAISE EXCEPTION
          'start_date cannot be in the future (got %, local today is %)',
          p_start_date, v_local_today;
      END IF;

      -- NEW: no overlap with an episode that already ended.
      SELECT max(e.end_date) INTO v_overlapping_end
      FROM public.bleeding_episodes e
      WHERE e.user_id = v_user_id
        AND e.lifecycle_status = 'ended'
        AND e.end_date >= p_start_date;
      IF v_overlapping_end IS NOT NULL THEN
        RAISE EXCEPTION
          'start_date (%) overlaps an episode that already ended on %',
          p_start_date, v_overlapping_end;
      END IF;

      IF p_start_precision = 'date_only' AND p_start_time IS NOT NULL THEN
        RAISE EXCEPTION 'start_time must be null when start_precision is date_only';
      END IF;
      IF p_start_precision IN ('exact_time', 'approximate_time')
        AND p_start_time IS NULL
      THEN
        RAISE EXCEPTION 'start_time is required when start_precision is %', p_start_precision;
      END IF;
      IF p_precision = 'date_only' AND p_observed_time IS NOT NULL THEN
        RAISE EXCEPTION 'observed_time must be null when precision is date_only';
      END IF;
      IF p_precision IN ('exact_time', 'approximate_time')
        AND p_observed_time IS NULL
      THEN
        RAISE EXCEPTION 'observed_time is required when precision is %', p_precision;
      END IF;

      v_derived_source := CASE WHEN p_start_date = v_local_today
        THEN 'user_observed' ELSE 'user_reported_historical' END;

      INSERT INTO public.bleeding_episodes (
        user_id, lifecycle_status, continuation_certainty, start_date,
        start_precision, start_time, start_source, client_operation_id
      ) VALUES (
        v_user_id, 'open', 'confirmed', p_start_date, p_start_precision,
        p_start_time, v_derived_source, p_client_operation_id
      ) RETURNING id INTO v_episode_id;

      INSERT INTO public.bleeding_observations (
        user_id, episode_id, observed_date, observed_time, precision, flow,
        source, timezone, utc_offset_minutes, symptoms, notes, client_operation_id
      ) VALUES (
        v_user_id, v_episode_id, p_start_date, p_observed_time, p_precision,
        p_flow, v_derived_source, p_timezone, p_utc_offset_minutes, p_symptoms,
        p_notes, p_client_operation_id
      ) RETURNING id INTO v_observation_id;

      RETURN QUERY SELECT v_episode_id, v_observation_id;
    END;
    $function$;

    -- 2 -----------------------------------------------------------------
    CREATE OR REPLACE FUNCTION public.end_bleeding_episode(
      p_client_operation_id uuid,
      p_episode_id uuid,
      p_end_date date,
      p_end_precision text,
      p_end_time timestamptz,
      p_observed_time timestamptz,
      p_precision text,
      p_timezone text,
      p_utc_offset_minutes integer
    )
    RETURNS TABLE (episode_id uuid, closing_observation_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_existing_observation_id uuid;
      v_episode_user_id uuid;
      v_episode_status text;
      v_episode_start date;
      v_closing_observation_id uuid;
      v_local_today date;
      v_derived_source text;
      v_latest_bleeding date;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'end_bleeding_episode requires an authenticated user';
      END IF;

      -- Idempotent replay: this exact "end" operation already succeeded.
      SELECT o.id INTO v_existing_observation_id
      FROM public.bleeding_observations o
      WHERE o.client_operation_id = p_client_operation_id AND o.user_id = v_user_id;

      IF v_existing_observation_id IS NOT NULL THEN
        RETURN QUERY SELECT p_episode_id, v_existing_observation_id;
        RETURN;
      END IF;

      SELECT user_id, lifecycle_status, start_date
        INTO v_episode_user_id, v_episode_status, v_episode_start
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
      IF p_end_date < v_episode_start THEN
        RAISE EXCEPTION
          'end_date (%) precedes episode start (%)', p_end_date, v_episode_start;
      END IF;

      -- NEW: never end before bleeding she already recorded in this
      -- episode (only the current, non-superseded value of each fact).
      SELECT max(o.observed_date) INTO v_latest_bleeding
      FROM public.bleeding_observations o
      WHERE o.episode_id = p_episode_id
        AND o.flow IN ('spotting', 'light', 'medium', 'heavy')
        AND NOT EXISTS (
          SELECT 1 FROM public.bleeding_observations s
          WHERE s.supersedes_id = o.id
        );
      IF v_latest_bleeding IS NOT NULL AND v_latest_bleeding > p_end_date THEN
        RAISE EXCEPTION
          'end_date (%) precedes bleeding already recorded on %',
          p_end_date, v_latest_bleeding;
      END IF;

      v_local_today := ((now() AT TIME ZONE 'UTC')
        + make_interval(mins => p_utc_offset_minutes))::date;
      IF p_end_date > v_local_today THEN
        RAISE EXCEPTION
          'end_date cannot be in the future (got %, local today is %)',
          p_end_date, v_local_today;
      END IF;

      IF p_end_precision = 'date_only' AND p_end_time IS NOT NULL THEN
        RAISE EXCEPTION 'end_time must be null when end_precision is date_only';
      END IF;
      IF p_end_precision IN ('exact_time', 'approximate_time')
        AND p_end_time IS NULL
      THEN
        RAISE EXCEPTION 'end_time is required when end_precision is %', p_end_precision;
      END IF;
      IF p_precision = 'date_only' AND p_observed_time IS NOT NULL THEN
        RAISE EXCEPTION 'observed_time must be null when precision is date_only';
      END IF;
      IF p_precision IN ('exact_time', 'approximate_time')
        AND p_observed_time IS NULL
      THEN
        RAISE EXCEPTION 'observed_time is required when precision is %', p_precision;
      END IF;

      v_derived_source := CASE WHEN p_end_date = v_local_today
        THEN 'user_observed' ELSE 'user_reported_historical' END;

      INSERT INTO public.bleeding_observations (
        user_id, episode_id, observed_date, observed_time, precision, flow,
        source, timezone, utc_offset_minutes, client_operation_id
      ) VALUES (
        v_user_id, p_episode_id, p_end_date, p_observed_time, p_precision,
        'none', v_derived_source, p_timezone, p_utc_offset_minutes, p_client_operation_id
      ) RETURNING id INTO v_closing_observation_id;

      UPDATE public.bleeding_episodes
      SET lifecycle_status = 'ended',
          continuation_certainty = NULL,
          end_date = p_end_date,
          end_precision = p_end_precision,
          end_time = p_end_time,
          end_source = v_derived_source,
          end_client_operation_id = p_client_operation_id
      WHERE id = p_episode_id;

      RETURN QUERY SELECT p_episode_id, v_closing_observation_id;
    END;
    $function$;

    -- 3 -----------------------------------------------------------------
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
      v_episode_start date;
      v_existing_id uuid;
      v_new_id uuid;
      v_local_today date;
      v_derived_source text;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION
          'record_bleeding_observation requires an authenticated user';
      END IF;

      SELECT id INTO v_existing_id
      FROM public.bleeding_observations
      WHERE client_operation_id = p_client_operation_id AND user_id = v_user_id;

      IF v_existing_id IS NOT NULL THEN
        RETURN QUERY SELECT v_existing_id;
        RETURN;
      END IF;

      SELECT user_id, lifecycle_status, start_date
        INTO v_episode_user_id, v_episode_status, v_episode_start
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

      -- NEW: never a fact dated before the episode it belongs to.
      IF p_observed_date < v_episode_start THEN
        RAISE EXCEPTION
          'observed_date (%) precedes the episode start (%)',
          p_observed_date, v_episode_start;
      END IF;

      v_local_today := ((now() AT TIME ZONE 'UTC')
        + make_interval(mins => p_utc_offset_minutes))::date;
      IF p_observed_date > v_local_today THEN
        RAISE EXCEPTION
          'observed_date cannot be in the future (got %, local today is %)',
          p_observed_date, v_local_today;
      END IF;

      IF p_precision = 'date_only' AND p_observed_time IS NOT NULL THEN
        RAISE EXCEPTION 'observed_time must be null when precision is date_only';
      END IF;
      IF p_precision IN ('exact_time', 'approximate_time')
        AND p_observed_time IS NULL
      THEN
        RAISE EXCEPTION 'observed_time is required when precision is %', p_precision;
      END IF;

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

    -- 4 -----------------------------------------------------------------
    CREATE OR REPLACE FUNCTION public.correct_observation(
      p_client_operation_id uuid,
      p_supersedes_id uuid,
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
      v_episode_id uuid;
      v_target_date date;
      v_existing_id uuid;
      v_already_superseded_by uuid;
      v_new_id uuid;
      v_root_operation_id uuid;
      v_root_flow text;
      v_root_date date;
      v_episode_status text;
      v_episode_start date;
      v_episode_end date;
      v_episode_operation_id uuid;
      v_episode_end_operation_id uuid;
      v_is_start boolean;
      v_is_closing boolean;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'correct_observation requires an authenticated user';
      END IF;

      SELECT id INTO v_existing_id
      FROM public.bleeding_observations
      WHERE client_operation_id = p_client_operation_id AND user_id = v_user_id;

      IF v_existing_id IS NOT NULL THEN
        RETURN QUERY SELECT v_existing_id;
        RETURN;
      END IF;

      -- FOR UPDATE serializes concurrent corrections of the same target
      -- (MENS-07, 20260926100000) so the loser gets NW409.
      SELECT episode_id, observed_date INTO v_episode_id, v_target_date
      FROM public.bleeding_observations
      WHERE id = p_supersedes_id AND user_id = v_user_id
      FOR UPDATE;

      IF v_episode_id IS NULL THEN
        RAISE EXCEPTION
          'supersedes_id % does not exist or does not belong to the calling user',
          p_supersedes_id;
      END IF;

      SELECT id INTO v_already_superseded_by
      FROM public.bleeding_observations
      WHERE supersedes_id = p_supersedes_id;

      IF v_already_superseded_by IS NOT NULL THEN
        RAISE EXCEPTION
          'observation % is no longer the current revision — it was '
          'already superseded by %', p_supersedes_id, v_already_superseded_by
          USING ERRCODE = 'NW409';
      END IF;

      IF p_precision = 'date_only' AND p_observed_time IS NOT NULL THEN
        RAISE EXCEPTION 'observed_time must be null when precision is date_only';
      END IF;
      IF p_precision IN ('exact_time', 'approximate_time')
        AND p_observed_time IS NULL
      THEN
        RAISE EXCEPTION 'observed_time is required when precision is %', p_precision;
      END IF;

      -- NEW: the correction must not contradict the episode's boundaries.
      -- The chain's ROOT identifies which fact this is: the episode's start
      -- observation shares the episode's client_operation_id (start RPC and
      -- onboarding both write it so); the closing observation shares its
      -- end_client_operation_id, or — onboarding-reported history — is the
      -- `none` row on end_date with no operation id.
      WITH RECURSIVE up AS (
        SELECT o.id, o.supersedes_id, o.client_operation_id, o.flow,
          o.observed_date
        FROM public.bleeding_observations o
        WHERE o.id = p_supersedes_id
        UNION ALL
        SELECT o.id, o.supersedes_id, o.client_operation_id, o.flow,
          o.observed_date
        FROM public.bleeding_observations o
        JOIN up ON o.id = up.supersedes_id
      )
      SELECT up.client_operation_id, up.flow, up.observed_date
        INTO v_root_operation_id, v_root_flow, v_root_date
      FROM up
      WHERE up.supersedes_id IS NULL;

      SELECT lifecycle_status, start_date, end_date, client_operation_id,
        end_client_operation_id
        INTO v_episode_status, v_episode_start, v_episode_end,
          v_episode_operation_id, v_episode_end_operation_id
      FROM public.bleeding_episodes
      WHERE id = v_episode_id;

      v_is_start := coalesce(
        v_root_operation_id IS NOT NULL
          AND v_root_operation_id = v_episode_operation_id,
        false);
      v_is_closing := coalesce(
        v_episode_status = 'ended' AND (
          (v_episode_end_operation_id IS NOT NULL
            AND v_root_operation_id = v_episode_end_operation_id)
          OR (v_root_operation_id IS NULL AND v_root_flow = 'none'
            AND v_root_date = v_episode_end)
        ),
        false);

      IF (v_is_start OR v_is_closing) AND p_observed_date <> v_target_date THEN
        RAISE EXCEPTION
          'the % observation of an episode cannot move to another date '
          '(episode dates are derived from it)',
          CASE WHEN v_is_start THEN 'start' ELSE 'closing' END;
      END IF;
      IF v_is_start AND p_flow = 'none' THEN
        RAISE EXCEPTION
          'the start observation of an episode cannot be corrected to no '
          'bleeding (flow none)';
      END IF;
      IF v_is_closing AND p_flow IN ('spotting', 'light', 'medium', 'heavy') THEN
        RAISE EXCEPTION
          'the closing observation of an ended episode cannot be corrected '
          'to bleeding (flow %)', p_flow;
      END IF;
      IF p_observed_date < v_episode_start
        OR (v_episode_end IS NOT NULL AND p_observed_date > v_episode_end)
      THEN
        RAISE EXCEPTION
          'a correction must stay inside its episode (% .. %), got %',
          v_episode_start, coalesce(v_episode_end::text, 'open'),
          p_observed_date;
      END IF;

      INSERT INTO public.bleeding_observations (
        user_id, episode_id, observed_date, observed_time, precision, flow,
        source, timezone, utc_offset_minutes, symptoms, notes,
        supersedes_id, client_operation_id
      ) VALUES (
        v_user_id, v_episode_id, p_observed_date, p_observed_time, p_precision,
        p_flow, 'user_reported_historical', p_timezone, p_utc_offset_minutes,
        p_symptoms, p_notes, p_supersedes_id, p_client_operation_id
      ) RETURNING id INTO v_new_id;

      RETURN QUERY SELECT v_new_id;
    END;
    $function$;

    -- 5 -----------------------------------------------------------------
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

      -- Episode part: idempotent replay by this exact operation id — as
      -- the episode's own operation id, or (NEW) as the operation that
      -- ended a reused open episode below.
      SELECT e.id INTO v_episode_id
      FROM public.bleeding_episodes e
      WHERE e.user_id = v_user_id
        AND (e.client_operation_id = p_client_operation_id
          OR e.end_client_operation_id = p_client_operation_id)
      LIMIT 1;

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

        SELECT e.id, e.start_date INTO v_existing_open_id, v_existing_open_start_date
        FROM public.bleeding_episodes e
        WHERE e.user_id = v_user_id AND e.lifecycle_status = 'open'
        LIMIT 1;

        IF v_existing_open_id IS NOT NULL THEN
          IF v_existing_open_start_date = p_start_date THEN
            v_episode_id := v_existing_open_id;
            -- NEW: she told us this same episode has ended — record that
            -- through the canonical end path (its own validation and its
            -- atomic closing observation) rather than dropping it.
            IF p_lifecycle_status = 'ended' AND p_end_date IS NOT NULL THEN
              PERFORM public.end_bleeding_episode(
                p_client_operation_id, v_existing_open_id, p_end_date,
                coalesce(p_end_precision, 'date_only'), p_end_time, p_end_time,
                coalesce(p_end_precision, 'date_only'), NULL,
                p_utc_offset_minutes
              );
            END IF;
          ELSE
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

  END IF;
END $$;
