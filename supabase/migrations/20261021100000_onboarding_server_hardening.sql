-- ONBOARDING / SERVER HARDENING (proposed 2026-10-21, not applied to any
-- hosted project)
--
-- Findings from the onboarding/server review (2026-10-19); regression
-- scripts: test/onboarding_server_hardening/sql/. CREATE OR REPLACE with an
-- unchanged signature, so existing grants on the function are preserved.
-- No earlier migration is edited.
--
-- #3 record_onboarding_menstrual_history rejects (P0001) a replay of an
--    operation id that carries different dates or baseline values than the
--    id already recorded. Previously the first attempt's rows were returned
--    as if the changed answer had saved. The app now sends a changed answer
--    under a fresh id; this is the server-side backstop.
-- #5 Its fresh-insert path now follows the no-overlap rule that
--    start_bleeding_episode already enforces (20261018090000 #1): an
--    identical ended episode (same start and end) is reused instead of
--    duplicated when onboarding is answered again, and any other overlap
--    with an ended episode is rejected (P0001).
-- #14 cycle_baselines: a usual bleeding duration must be shorter than the
--    usual cycle length when both are given. Added NOT VALID so existing
--    rows (if any violate it) do not block the migration; every new row,
--    from both record_onboarding_menstrual_history and
--    save_baseline_estimate, is checked (23514).
-- Low: knowledge_citations.user_id had no foreign key, so a citation row
--    would survive account deletion. Nothing writes the table today; a
--    NOT VALID ON DELETE CASCADE FK closes it for every future row.

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
  v_prior record;
  v_overlap_start date;
  v_overlap_end date;
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

  -- NEW (finding #3): an operation id is one logical answer. A replay
  -- that carries DIFFERENT dates than what this id already recorded is
  -- not a retry — silently returning the first episode would drop her
  -- corrected answer while reporting success. Reject it instead; the
  -- app sends a changed answer under a fresh id.
  IF v_episode_id IS NOT NULL AND p_start_date IS NOT NULL THEN
    SELECT e.start_date, e.end_date INTO v_prior
    FROM public.bleeding_episodes e WHERE e.id = v_episode_id;
    IF v_prior.start_date IS DISTINCT FROM p_start_date
      OR (p_end_date IS NOT NULL
          AND v_prior.end_date IS DISTINCT FROM p_end_date)
    THEN
      RAISE EXCEPTION
        'onboarding operation % was already recorded with different dates',
        p_client_operation_id;
    END IF;
  END IF;

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
      -- NEW (finding #5): the fresh-insert path now honours the same
      -- no-overlap rule as start_bleeding_episode. An identical ended
      -- episode (same start and end — she answered onboarding again
      -- with the same truthful history) is reused, not duplicated;
      -- any other overlap with an ended episode is rejected.
      IF p_end_date IS NOT NULL THEN
        SELECT e.id INTO v_episode_id
        FROM public.bleeding_episodes e
        WHERE e.user_id = v_user_id AND e.lifecycle_status = 'ended'
          AND e.start_date = p_start_date AND e.end_date = p_end_date
        LIMIT 1;
      END IF;

      IF v_episode_id IS NULL THEN
        SELECT e.start_date, e.end_date
          INTO v_overlap_start, v_overlap_end
        FROM public.bleeding_episodes e
        WHERE e.user_id = v_user_id AND e.lifecycle_status = 'ended'
          AND e.end_date >= p_start_date
          AND (p_end_date IS NULL OR e.start_date <= p_end_date)
        ORDER BY e.end_date DESC
        LIMIT 1;
        IF v_overlap_end IS NOT NULL THEN
          RAISE EXCEPTION
            'start_date (%) overlaps an episode that already ended on % (started %)',
            p_start_date, v_overlap_end, v_overlap_start;
        END IF;
      END IF;
    END IF;

    IF v_episode_id IS NULL AND NOT v_episode_conflict THEN
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

  -- NEW (finding #3): same rule for the baseline part.
  IF v_baseline_id IS NOT NULL AND (
    p_usual_bleeding_duration_days IS NOT NULL
    OR p_usual_cycle_length_days IS NOT NULL
  ) AND EXISTS (
    SELECT 1 FROM public.cycle_baselines b
    WHERE b.id = v_baseline_id
      AND (b.usual_bleeding_duration_days IS DISTINCT FROM p_usual_bleeding_duration_days
        OR b.usual_cycle_length_days IS DISTINCT FROM p_usual_cycle_length_days)
  ) THEN
    RAISE EXCEPTION
      'onboarding operation % was already recorded with a different baseline',
      p_client_operation_id;
  END IF;

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

ALTER TABLE public.cycle_baselines
  DROP CONSTRAINT IF EXISTS cycle_baselines_duration_below_cycle_check;
ALTER TABLE public.cycle_baselines
  ADD CONSTRAINT cycle_baselines_duration_below_cycle_check
  CHECK (
    usual_bleeding_duration_days IS NULL
    OR usual_cycle_length_days IS NULL
    OR usual_bleeding_duration_days < usual_cycle_length_days
  ) NOT VALID;

ALTER TABLE public.knowledge_citations
  DROP CONSTRAINT IF EXISTS knowledge_citations_user_id_fkey;
ALTER TABLE public.knowledge_citations
  ADD CONSTRAINT knowledge_citations_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  NOT VALID;
