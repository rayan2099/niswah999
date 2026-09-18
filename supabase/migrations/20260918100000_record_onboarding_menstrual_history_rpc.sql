-- RECORD ONBOARDING MENSTRUAL HISTORY — ATOMIC, IDEMPOTENT RPC
--
-- Menstrual Data Integrity charter, PR #4 completion wave, Fix A. The
-- previous onboarding path called two separate client requests
-- (createEpisode, then saveBaseline). A failure between them — episode
-- succeeds, baseline fails, she taps Retry — had no way to tell a genuine
-- retry apart from a new submission: retrying could duplicate an ended
-- historical episode, conflict against an already-open one, or show a
-- false "failed" state for data that had actually already saved.
--
-- One RPC, one transaction, one client_operation_id covering the whole
-- logical "record what I told you during onboarding" action. Both the
-- episode and the baseline are optional (she may have answered one, both,
-- or neither with "I'm not sure") — presence is inferred from which
-- fields are non-null, not a separate boolean flag. Retrying with the
-- same operation id returns the original episode_id/baseline_id (each
-- possibly null, exactly matching what was actually submitted the first
-- time) rather than re-inserting anything.
--
-- Future-date rejection mirrors start_bleeding_episode/
-- end_bleeding_episode's own offset-based boundary check — a historical
-- start/end reported through onboarding is still validated at the
-- canonical write boundary, not merely by the date picker.
--
-- Deliberately NOT SECURITY DEFINER: runs as the calling `authenticated`
-- role so every table's own RLS/column-grant rules still apply as a
-- second, independent layer.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_episodes'
  ) THEN

    CREATE OR REPLACE FUNCTION public.record_onboarding_menstrual_history(
      p_client_operation_id uuid,
      p_utc_offset_minutes integer,
      p_start_date date DEFAULT NULL,
      p_start_precision text DEFAULT NULL,
      p_start_source text DEFAULT NULL,
      p_lifecycle_status text DEFAULT NULL,
      p_continuation_certainty text DEFAULT NULL,
      p_end_date date DEFAULT NULL,
      p_end_precision text DEFAULT NULL,
      p_end_source text DEFAULT NULL,
      p_usual_bleeding_duration_days integer DEFAULT NULL,
      p_usual_cycle_length_days integer DEFAULT NULL
    )
    RETURNS TABLE (episode_id uuid, baseline_id uuid)
    LANGUAGE plpgsql
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_episode_id uuid;
      v_baseline_id uuid;
      v_local_today date;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION
          'record_onboarding_menstrual_history requires an authenticated user';
      END IF;

      -- Idempotent replay: this exact operation already ran. Each part
      -- (episode, baseline) was written with this same operation id if
      -- and only if it was actually submitted the first time, so
      -- checking both independently correctly reconstructs "what was
      -- actually saved" without assuming both were present.
      SELECT e.id INTO v_episode_id
      FROM public.bleeding_episodes e
      WHERE e.client_operation_id = p_client_operation_id AND e.user_id = v_user_id;

      SELECT b.id INTO v_baseline_id
      FROM public.cycle_baselines b
      WHERE b.client_operation_id = p_client_operation_id AND b.user_id = v_user_id;

      IF v_episode_id IS NOT NULL OR v_baseline_id IS NOT NULL THEN
        RETURN QUERY SELECT v_episode_id, v_baseline_id;
        RETURN;
      END IF;

      IF p_start_date IS NOT NULL THEN
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

        INSERT INTO public.bleeding_episodes (
          user_id, lifecycle_status, continuation_certainty, start_date,
          start_precision, start_source, end_date, end_precision, end_source,
          client_operation_id
        ) VALUES (
          v_user_id, p_lifecycle_status, p_continuation_certainty, p_start_date,
          p_start_precision, p_start_source, p_end_date, p_end_precision,
          p_end_source, p_client_operation_id
        ) RETURNING id INTO v_episode_id;
      END IF;

      IF p_usual_bleeding_duration_days IS NOT NULL
        OR p_usual_cycle_length_days IS NOT NULL
      THEN
        INSERT INTO public.cycle_baselines (
          user_id, usual_bleeding_duration_days, usual_cycle_length_days,
          client_operation_id
        ) VALUES (
          v_user_id, p_usual_bleeding_duration_days, p_usual_cycle_length_days,
          p_client_operation_id
        ) RETURNING id INTO v_baseline_id;
      END IF;

      RETURN QUERY SELECT v_episode_id, v_baseline_id;
    END;
    $function$;

    GRANT EXECUTE ON FUNCTION public.record_onboarding_menstrual_history(
      uuid, integer, date, text, text, text, text, date, text, text,
      integer, integer
    ) TO authenticated;

  END IF;
END $$;
