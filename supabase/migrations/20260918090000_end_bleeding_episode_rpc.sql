-- END BLEEDING EPISODE — ATOMIC, IDEMPOTENT RPC
--
-- Menstrual Data Integrity charter, PR #4 hardening pass (2026-09-18) —
-- Blocker 2. The original end path was two separate client-issued calls:
-- UPDATE bleeding_episodes (status -> ended), then INSERT a closing
-- flow:none observation. If the second call failed after the first
-- succeeded, the episode was closed with no factual record of its own
-- closure — silently violating the same "episode + its evidence must
-- exist together" invariant `start_bleeding_episode` already protects.
--
-- Mirrors `start_bleeding_episode`'s own atomicity and idempotency
-- pattern: one function, one transaction, a `client_operation_id` that
-- makes a retried "end" call return the original closing observation
-- rather than erroring or double-closing. Also validates, at the
-- canonical write boundary (never trusting the client alone):
-- ownership, that the episode is genuinely open, that end_date is not
-- before start_date, and that end_date is not in the future — the exact
-- same category of defense `start_bleeding_episode` applies, now applied
-- symmetrically to ending one.
--
-- `FOR UPDATE` locks the target episode row for the duration of this
-- transaction, so a concurrent end/correction request against the same
-- episode serializes behind this one rather than racing it.
--
-- Deliberately NOT `SECURITY DEFINER` — runs as the calling
-- `authenticated` role, so RLS and the column-level UPDATE grants from
-- the schema migration (Blocker 8) still apply.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_episodes'
  ) THEN

    CREATE OR REPLACE FUNCTION public.end_bleeding_episode(
      p_client_operation_id uuid,
      p_episode_id uuid,
      p_end_date date,
      p_end_precision text,
      p_end_source text,
      p_observed_time timestamptz,
      p_precision text,
      p_source text,
      p_timezone text,
      p_utc_offset_minutes integer
    )
    RETURNS TABLE (episode_id uuid, closing_observation_id uuid)
    LANGUAGE plpgsql
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_existing_observation_id uuid;
      v_episode_user_id uuid;
      v_episode_status text;
      v_episode_start date;
      v_closing_observation_id uuid;
      v_local_today date;
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

      IF v_episode_user_id IS NULL THEN
        RAISE EXCEPTION 'episode % does not exist', p_episode_id;
      END IF;
      IF v_episode_user_id <> v_user_id THEN
        RAISE EXCEPTION 'episode % does not belong to the calling user', p_episode_id;
      END IF;
      IF v_episode_status <> 'open' THEN
        RAISE EXCEPTION 'episode % is not open', p_episode_id;
      END IF;
      IF p_end_date < v_episode_start THEN
        RAISE EXCEPTION
          'end_date (%) precedes episode start (%)', p_end_date, v_episode_start;
      END IF;

      v_local_today := ((now() AT TIME ZONE 'UTC')
        + make_interval(mins => p_utc_offset_minutes))::date;
      IF p_end_date > v_local_today THEN
        RAISE EXCEPTION
          'end_date cannot be in the future (got %, local today is %)',
          p_end_date, v_local_today;
      END IF;

      UPDATE public.bleeding_episodes
      SET lifecycle_status = 'ended',
          continuation_certainty = NULL,
          end_date = p_end_date,
          end_precision = p_end_precision,
          end_source = p_end_source,
          end_client_operation_id = p_client_operation_id
      WHERE id = p_episode_id;

      INSERT INTO public.bleeding_observations (
        user_id, episode_id, observed_date, observed_time, precision, flow,
        source, timezone, utc_offset_minutes, client_operation_id
      ) VALUES (
        v_user_id, p_episode_id, p_end_date, p_observed_time, p_precision,
        'none', p_source, p_timezone, p_utc_offset_minutes, p_client_operation_id
      ) RETURNING id INTO v_closing_observation_id;

      RETURN QUERY SELECT p_episode_id, v_closing_observation_id;
    END;
    $function$;

    GRANT EXECUTE ON FUNCTION public.end_bleeding_episode(
      uuid, uuid, date, text, text, timestamptz, text, text, text, integer
    ) TO authenticated;

  END IF;
END $$;
