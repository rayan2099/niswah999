-- CORRECT OBSERVATION — ATOMIC, IDEMPOTENT, EPISODE-STATE-AGNOSTIC RPC
--
-- Menstrual Data Integrity charter, PR #4 completion wave — Hardening 2's
-- own explicit requirement: now that an ended episode rejects every new
-- fact unconditionally (see the schema migration's
-- `bleeding_observations_validate_insert`), a genuine correction to
-- something reported *before* the episode closed still needs a real,
-- controlled path — a correction is not the same operation as adding a
-- new event, and must remain possible after an episode ends.
--
-- The episode a correction belongs to is resolved FROM the observation
-- being corrected (`p_supersedes_id`), not taken as a separate caller-
-- supplied parameter — this means a correction can never be misdirected
-- at the wrong episode even by a malformed/malicious caller, and the
-- validation trigger's own same-user/same-episode check on
-- `supersedes_id` still applies as a second, independent layer.
--
-- Idempotent like every other write RPC in this model: retrying with the
-- same `client_operation_id` returns the original correction's id rather
-- than creating a second one.
--
-- Deliberately NOT SECURITY DEFINER — runs as the calling `authenticated`
-- role, so RLS and the validation trigger both still apply in full.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_observations'
  ) THEN

    CREATE OR REPLACE FUNCTION public.correct_observation(
      p_client_operation_id uuid,
      p_supersedes_id uuid,
      p_observed_date date,
      p_precision text,
      p_flow text,
      p_source text,
      p_utc_offset_minutes integer,
      p_observed_time timestamptz DEFAULT NULL,
      p_timezone text DEFAULT NULL,
      p_symptoms jsonb DEFAULT NULL,
      p_notes text DEFAULT NULL
    )
    RETURNS TABLE (observation_id uuid)
    LANGUAGE plpgsql
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_episode_id uuid;
      v_existing_id uuid;
      v_new_id uuid;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'correct_observation requires an authenticated user';
      END IF;

      -- Idempotent replay: this exact correction already succeeded.
      SELECT id INTO v_existing_id
      FROM public.bleeding_observations
      WHERE client_operation_id = p_client_operation_id AND user_id = v_user_id;

      IF v_existing_id IS NOT NULL THEN
        RETURN QUERY SELECT v_existing_id;
        RETURN;
      END IF;

      -- The episode is resolved from the target, not a separate
      -- parameter — a correction can only ever be filed against the
      -- episode its own target genuinely belongs to. Also confirms
      -- ownership: the WHERE clause only matches a row the caller
      -- actually owns.
      SELECT episode_id INTO v_episode_id
      FROM public.bleeding_observations
      WHERE id = p_supersedes_id AND user_id = v_user_id;

      IF v_episode_id IS NULL THEN
        RAISE EXCEPTION
          'supersedes_id % does not exist or does not belong to the calling user',
          p_supersedes_id;
      END IF;

      -- The rest (no fork/cycle, no future date, same-user/same-episode
      -- re-confirmed) is enforced by bleeding_observations_validate_insert
      -- and bleeding_observations_supersedes_once — this INSERT is
      -- deliberately not a SECURITY DEFINER bypass of either.
      INSERT INTO public.bleeding_observations (
        user_id, episode_id, observed_date, observed_time, precision, flow,
        source, timezone, utc_offset_minutes, symptoms, notes,
        supersedes_id, client_operation_id
      ) VALUES (
        v_user_id, v_episode_id, p_observed_date, p_observed_time, p_precision,
        p_flow, p_source, p_timezone, p_utc_offset_minutes, p_symptoms, p_notes,
        p_supersedes_id, p_client_operation_id
      ) RETURNING id INTO v_new_id;

      RETURN QUERY SELECT v_new_id;
    END;
    $function$;

    GRANT EXECUTE ON FUNCTION public.correct_observation(
      uuid, uuid, date, text, text, text, integer, timestamptz, text,
      jsonb, text
    ) TO authenticated;

  END IF;
END $$;
