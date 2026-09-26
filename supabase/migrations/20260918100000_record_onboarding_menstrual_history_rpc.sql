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
-- PR #4 final implementation wave, Hardening 5: now `SECURITY DEFINER`
-- with an explicit `SET search_path` — the schema migration revokes
-- every client-facing INSERT grant on the tables this function writes
-- to. Ownership was already self-contained before this change (every
-- INSERT here uses `v_user_id := auth.uid()` exclusively, never a
-- caller-supplied id), so bypassing RLS changes nothing about its
-- safety. `EXECUTE` is revoked from `PUBLIC` and re-granted only to
-- `authenticated`.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_episodes'
  ) THEN

    -- Closure Blocker 4: drops the old 12-parameter overload
    -- (p_start_source/p_end_source, both caller-trusted) before creating
    -- the new one below — see start_bleeding_episode's identical note.
    DROP FUNCTION IF EXISTS public.record_onboarding_menstrual_history(
      uuid, integer, date, text, text, text, text, date, text, text,
      integer, integer
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
    RETURNS TABLE (episode_id uuid, baseline_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_episode_id uuid;
      v_baseline_id uuid;
      v_local_today date;
      v_derived_start_source text;
      v_derived_end_source text;
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

        -- Closure Blocker 5 — precision/timestamp consistency, mirroring
        -- start_bleeding_episode/end_bleeding_episode's identical checks.
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

        -- Closure Blocker 4 — derived here, never trusted from the
        -- caller; see start_bleeding_episode's identical rationale. An
        -- onboarding submission made the same local day the bleeding
        -- itself started/ended is honestly `user_observed`; anything
        -- earlier is `user_reported_historical` — the ordinary case for
        -- onboarding, which is fundamentally reporting history.
        v_derived_start_source := CASE WHEN p_start_date = v_local_today
          THEN 'user_observed' ELSE 'user_reported_historical' END;
        -- Only derived when an end was actually reported — the episode's
        -- own end-metadata consistency constraint requires end_source be
        -- null whenever end_date is null, and `p_end_date = v_local_today`
        -- would otherwise evaluate to NULL (neither true nor false),
        -- falling through to the ELSE branch and fabricating a source for
        -- an end that was never reported.
        v_derived_end_source := CASE
          WHEN p_end_date IS NULL THEN NULL
          WHEN p_end_date = v_local_today THEN 'user_observed'
          ELSE 'user_reported_historical'
        END;

        -- The episode row is inserted 'open' regardless of what
        -- p_lifecycle_status actually is — a placeholder, immediately
        -- overwritten below, that only exists so the observation
        -- INSERTs right after this can happen while
        -- bleeding_observations_validate_insert's "an ended episode
        -- accepts no new fact" rule does not yet apply. Mirrors
        -- end_bleeding_episode's identical ordering trick (insert the
        -- evidence first, transition the episode's real status after).
        -- continuation_certainty is likewise a placeholder — the
        -- lifecycle_status='open' CHECK constraint requires it non-null
        -- here regardless of what the caller's final state will be.
        INSERT INTO public.bleeding_episodes (
          user_id, lifecycle_status, continuation_certainty, start_date,
          start_precision, start_time, start_source, end_date, end_precision,
          end_time, end_source, client_operation_id
        ) VALUES (
          v_user_id, 'open', 'confirmed', p_start_date,
          p_start_precision, p_start_time, v_derived_start_source, p_end_date,
          p_end_precision, p_end_time, v_derived_end_source, p_client_operation_id
        ) RETURNING id INTO v_episode_id;

        -- Closure Blocker 3 — an episode must never exist without its own
        -- backing evidence (the same invariant start_bleeding_episode/
        -- end_bleeding_episode already protect atomically). The flow
        -- itself was never asked during onboarding, so it is recorded as
        -- `uncertain` rather than inventing a specific level — the
        -- canonical Fiqh evidence adapter already excludes `uncertain`
        -- days rather than fabricating a FlowLevel for them, so this
        -- stays honest all the way through.
        INSERT INTO public.bleeding_observations (
          user_id, episode_id, observed_date, observed_time, precision, flow,
          source, utc_offset_minutes, client_operation_id
        ) VALUES (
          v_user_id, v_episode_id, p_start_date, p_start_time, p_start_precision,
          'uncertain', v_derived_start_source, p_utc_offset_minutes,
          p_client_operation_id
        );

        IF p_end_date IS NOT NULL THEN
          -- No client_operation_id here: the unique index on that column
          -- allows only one row per operation id, and the start
          -- observation above already claimed p_client_operation_id for
          -- this call. This closing observation needs no independent
          -- replay lookup of its own — the outer episode/baseline check
          -- above already guards the whole insert block from re-running.
          INSERT INTO public.bleeding_observations (
            user_id, episode_id, observed_date, observed_time, precision, flow,
            source, utc_offset_minutes
          ) VALUES (
            v_user_id, v_episode_id, p_end_date, p_end_time, p_end_precision,
            'none', v_derived_end_source, p_utc_offset_minutes
          );
        END IF;

        -- Only now does the episode transition to its real, caller-
        -- intended final state — both bleeding_observations inserts
        -- above already happened while it was still genuinely 'open'.
        UPDATE public.bleeding_episodes
        SET lifecycle_status = p_lifecycle_status,
            continuation_certainty = p_continuation_certainty
        WHERE id = v_episode_id;
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
