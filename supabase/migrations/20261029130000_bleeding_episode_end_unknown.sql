-- PT-002: an ended period whose end she does not remember.
--
-- Onboarding asks "Is it still happening?". "No, it has stopped" then
-- "I'm not sure exactly when" used to save no period at all, so the start
-- she did remember was lost. It is now saved as an ENDED episode with
-- end_precision = 'unknown' and no end date, no end time and no closing
-- "no bleeding" entry. Nothing about the end is invented.
--
-- Rules for such an episode:
-- * For overlap checks it occupies only its start day (the last day that
--   is known). Its true end may be later; that is not guessed.
-- * correct_episode_end gives it its first real end ("Edit this period").
-- * The app uses its start for cycle timing but never its length, and
--   shows no fiqh ruling that depends on it.
--
-- Constraints are widened, never narrowed: every existing row still
-- satisfies them. Functions are CREATE OR REPLACE with unchanged
-- signatures, so their grants are kept. Re-running is a no-op.

-- 1. Constraints ----------------------------------------------------------------

ALTER TABLE public.bleeding_episodes
  DROP CONSTRAINT IF EXISTS bleeding_episodes_precision_check;
ALTER TABLE public.bleeding_episodes
  ADD CONSTRAINT bleeding_episodes_precision_check
  CHECK (start_precision IN ('exact_time', 'approximate_time', 'date_only')
    AND (end_precision IS NULL
      OR end_precision IN ('exact_time', 'approximate_time', 'date_only', 'unknown')));

ALTER TABLE public.bleeding_episodes
  DROP CONSTRAINT IF EXISTS bleeding_episodes_end_metadata_consistency_check;
ALTER TABLE public.bleeding_episodes
  ADD CONSTRAINT bleeding_episodes_end_metadata_consistency_check
  CHECK (
    (end_date IS NULL AND end_precision IS NULL AND end_source IS NULL)
    OR (end_date IS NOT NULL AND end_precision IS NOT NULL
        AND end_precision <> 'unknown' AND end_source IS NOT NULL)
    OR (lifecycle_status = 'ended' AND end_date IS NULL
        AND end_precision = 'unknown' AND end_source IS NOT NULL)
  );

ALTER TABLE public.bleeding_episodes
  DROP CONSTRAINT IF EXISTS bleeding_episodes_end_precision_time_check;
ALTER TABLE public.bleeding_episodes
  ADD CONSTRAINT bleeding_episodes_end_precision_time_check
  CHECK (
    end_precision IS NULL
    OR (end_precision IN ('date_only', 'unknown') AND end_time IS NULL)
    OR (end_precision IN ('exact_time', 'approximate_time')
      AND end_time IS NOT NULL)
  );

-- 2. Last known day for overlap rules: an unknown end occupies its start day.

CREATE OR REPLACE FUNCTION public.start_bleeding_episode(p_client_operation_id uuid, p_start_date date, p_start_precision text, p_start_time timestamp with time zone, p_flow text, p_observed_time timestamp with time zone, p_precision text, p_timezone text, p_utc_offset_minutes integer, p_symptoms jsonb DEFAULT NULL::jsonb, p_notes text DEFAULT NULL::text)
 RETURNS TABLE(episode_id uuid, observation_id uuid)
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
      SELECT max(coalesce(e.end_date, e.start_date)) INTO v_overlapping_end
      FROM public.bleeding_episodes e
      WHERE e.user_id = v_user_id
        AND e.lifecycle_status = 'ended'
        AND coalesce(e.end_date, e.start_date) >= p_start_date;
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

CREATE OR REPLACE FUNCTION public.correct_episode_start(p_client_operation_id uuid, p_episode_id uuid, p_new_start_date date, p_flow text, p_timezone text, p_utc_offset_minutes integer, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_retract_conflicting boolean DEFAULT false)
 RETURNS TABLE(episode_id uuid, revision_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_revision_id uuid;
  v_episode public.bleeding_episodes;
  v_before jsonb;
  v_conflicting uuid[];
  v_retract uuid[] := '{}';
  v_prior_end date;
BEGIN
  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, p_episode_id, p_expected_updated_at);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY SELECT p_episode_id, v_revision_id;
    RETURN;
  END IF;

  SELECT * INTO v_episode FROM public.bleeding_episodes WHERE id = p_episode_id;
  v_before := public.bleeding_episode_snapshot(p_episode_id);

  IF p_new_start_date IS NULL THEN
    RAISE EXCEPTION 'a new start date is required';
  END IF;
  IF p_flow IS NULL OR p_flow NOT IN ('spotting', 'light', 'medium', 'heavy', 'uncertain') THEN
    RAISE EXCEPTION 'flow must be spotting, light, medium, heavy or uncertain';
  END IF;
  IF p_new_start_date = v_episode.start_date THEN
    RAISE EXCEPTION 'the new start date is the same as the current one';
  END IF;
  IF p_new_start_date > public.bleeding_local_today(p_utc_offset_minutes) THEN
    RAISE EXCEPTION 'start_date cannot be in the future (got %)', p_new_start_date;
  END IF;
  IF v_episode.end_date IS NOT NULL AND p_new_start_date > v_episode.end_date THEN
    RAISE EXCEPTION 'the start (%) cannot be after the end (%)',
      p_new_start_date, v_episode.end_date;
  END IF;

  -- Same overlap rule as start_bleeding_episode: an episode may not start
  -- on or before the end of an earlier episode.
  SELECT max(coalesce(e.end_date, e.start_date)) INTO v_prior_end
  FROM public.bleeding_episodes e
  WHERE e.user_id = v_user_id AND e.id <> p_episode_id
    AND e.start_date < v_episode.start_date
    AND coalesce(e.end_date, e.start_date) >= p_new_start_date;
  IF v_prior_end IS NOT NULL THEN
    RAISE EXCEPTION 'start_date (%) overlaps an episode that ended on %',
      p_new_start_date, v_prior_end;
  END IF;
  -- ...nor reach back over another episode entirely.
  IF EXISTS (
    SELECT 1 FROM public.bleeding_episodes e
    WHERE e.user_id = v_user_id AND e.id <> p_episode_id
      AND e.start_date >= p_new_start_date AND e.start_date < v_episode.start_date
  ) THEN
    RAISE EXCEPTION 'start_date (%) would cover another episode', p_new_start_date;
  END IF;

  IF p_new_start_date > v_episode.start_date THEN
    SELECT coalesce(array_agg(o.id), '{}') INTO v_conflicting
    FROM public.bleeding_effective_observations(p_episode_id) o
    WHERE o.observed_date < p_new_start_date;
    IF cardinality(v_conflicting) > 0 THEN
      IF NOT p_retract_conflicting THEN
        RAISE EXCEPTION '% entries are recorded before %', cardinality(v_conflicting), p_new_start_date
          USING ERRCODE = 'NW422',
                DETAIL = cardinality(v_conflicting)::text;
      END IF;
      v_retract := public.bleeding_observation_chains(v_conflicting);
    END IF;
  END IF;

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state,
    after_state, retracted_observation_ids
  ) VALUES (
    v_user_id, p_episode_id, p_client_operation_id, 'correct_start', v_before,
    '{}'::jsonb, v_retract
  ) RETURNING id INTO v_revision_id;

  PERFORM public.bleeding_archive_observations(v_user_id, v_retract, v_revision_id);

  UPDATE public.bleeding_episodes
  SET start_date = p_new_start_date,
      start_precision = 'date_only',
      start_time = NULL,
      start_source = 'user_reported_historical'
  WHERE id = p_episode_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.bleeding_effective_observations(p_episode_id) o
    WHERE o.observed_date = p_new_start_date
      AND o.flow IN ('spotting', 'light', 'medium', 'heavy', 'uncertain')
  ) THEN
    PERFORM set_config('niswah.restoring_episode', p_episode_id::text, true);
    INSERT INTO public.bleeding_observations (
      user_id, episode_id, observed_date, observed_time, precision, flow,
      source, timezone, utc_offset_minutes, client_operation_id
    ) VALUES (
      v_user_id, p_episode_id, p_new_start_date, NULL, 'date_only', p_flow,
      'user_reported_historical', p_timezone, p_utc_offset_minutes, NULL
    );
    PERFORM set_config('niswah.restoring_episode', '', true);
  END IF;

  UPDATE public.bleeding_episode_revisions
  SET after_state = public.bleeding_episode_snapshot(p_episode_id)
  WHERE id = v_revision_id;

  RETURN QUERY SELECT p_episode_id, v_revision_id;
END;
$function$;

-- 3. Setting the first real end of a period whose end was unknown.

CREATE OR REPLACE FUNCTION public.correct_episode_end(p_client_operation_id uuid, p_episode_id uuid, p_new_end_date date, p_timezone text, p_utc_offset_minutes integer, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_retract_conflicting boolean DEFAULT false)
 RETURNS TABLE(episode_id uuid, revision_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_revision_id uuid;
  v_episode public.bleeding_episodes;
  v_before jsonb;
  v_closing uuid;
  v_conflicting uuid[];
  v_retract uuid[] := '{}';
BEGIN
  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, p_episode_id, p_expected_updated_at);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY SELECT p_episode_id, v_revision_id;
    RETURN;
  END IF;

  SELECT * INTO v_episode FROM public.bleeding_episodes WHERE id = p_episode_id;
  v_before := public.bleeding_episode_snapshot(p_episode_id);

  IF v_episode.lifecycle_status <> 'ended' THEN
    RAISE EXCEPTION 'episode % is not ended', p_episode_id;
  END IF;
  IF p_new_end_date IS NULL THEN
    RAISE EXCEPTION 'a new end date is required';
  END IF;
  IF p_new_end_date = v_episode.end_date THEN
    RAISE EXCEPTION 'the new end date is the same as the current one';
  END IF;
  IF p_new_end_date < v_episode.start_date THEN
    RAISE EXCEPTION 'end_date (%) precedes episode start (%)',
      p_new_end_date, v_episode.start_date;
  END IF;
  IF p_new_end_date > public.bleeding_local_today(p_utc_offset_minutes) THEN
    RAISE EXCEPTION 'end_date cannot be in the future (got %)', p_new_end_date;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.bleeding_episodes e
    WHERE e.user_id = v_user_id AND e.id <> p_episode_id
      AND e.start_date > v_episode.start_date
      AND e.start_date <= p_new_end_date
  ) THEN
    RAISE EXCEPTION 'end_date (%) overlaps the next episode', p_new_end_date;
  END IF;

  -- The current closing observation: the latest effective "none" on the
  -- current end date.
  SELECT o.id INTO v_closing
  FROM public.bleeding_effective_observations(p_episode_id) o
  WHERE o.flow = 'none' AND o.observed_date = v_episode.end_date
  ORDER BY o.reported_at DESC
  LIMIT 1;

  -- An end that was unknown (PT-002) is being set for the first time:
  -- any bleeding recorded after the new end contradicts it, as for an
  -- earlier end.
  IF v_episode.end_date IS NULL OR p_new_end_date < v_episode.end_date THEN
    SELECT coalesce(array_agg(o.id), '{}') INTO v_conflicting
    FROM public.bleeding_effective_observations(p_episode_id) o
    WHERE o.observed_date > p_new_end_date
      AND o.id IS DISTINCT FROM v_closing
      AND o.flow IN ('spotting', 'light', 'medium', 'heavy', 'uncertain');
    IF cardinality(v_conflicting) > 0 THEN
      IF NOT p_retract_conflicting THEN
        RAISE EXCEPTION '% entries are recorded after %', cardinality(v_conflicting), p_new_end_date
          USING ERRCODE = 'NW422',
                DETAIL = cardinality(v_conflicting)::text;
      END IF;
      v_retract := public.bleeding_observation_chains(v_conflicting);
    END IF;
  END IF;

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state,
    after_state, retracted_observation_ids
  ) VALUES (
    v_user_id, p_episode_id, p_client_operation_id, 'correct_end', v_before,
    '{}'::jsonb, v_retract
  ) RETURNING id INTO v_revision_id;

  PERFORM public.bleeding_archive_observations(v_user_id, v_retract, v_revision_id);

  UPDATE public.bleeding_episodes
  SET end_date = p_new_end_date,
      end_precision = 'date_only',
      end_time = NULL,
      end_source = 'user_reported_historical'
  WHERE id = p_episode_id;

  -- A correction of the closing observation; when none exists (it was
  -- archived by an earlier change), a new closing fact on the ended episode.
  PERFORM set_config('niswah.restoring_episode', p_episode_id::text, true);
  INSERT INTO public.bleeding_observations (
    user_id, episode_id, observed_date, observed_time, precision, flow,
    source, timezone, utc_offset_minutes, supersedes_id, client_operation_id
  ) VALUES (
    v_user_id, p_episode_id, p_new_end_date, NULL, 'date_only', 'none',
    'user_reported_historical', p_timezone, p_utc_offset_minutes, v_closing, NULL
  );
  PERFORM set_config('niswah.restoring_episode', '', true);
  -- Moving it means a "none" no longer on the old date: drop its mirror.
  IF v_closing IS NOT NULL THEN
    DELETE FROM public.cycle_entries c WHERE c.id = v_closing AND c.user_id = v_user_id;
  END IF;

  UPDATE public.bleeding_episode_revisions
  SET after_state = public.bleeding_episode_snapshot(p_episode_id)
  WHERE id = v_revision_id;

  RETURN QUERY SELECT p_episode_id, v_revision_id;
END;
$function$;

-- 4. Restoring next to a period whose end is unknown.

CREATE OR REPLACE FUNCTION public.restore_episode(p_client_operation_id uuid, p_episode_id uuid)
 RETURNS TABLE(episode_id uuid, revision_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_revision_id uuid;
  v_archived public.bleeding_episodes_archive;
  v_obs public.bleeding_observations_archive;
  v_until date;
BEGIN
  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, p_episode_id, NULL, true);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY SELECT p_episode_id, v_revision_id;
    RETURN;
  END IF;

  SELECT * INTO v_archived FROM public.bleeding_episodes_archive WHERE id = p_episode_id;

  IF v_archived.lifecycle_status = 'open' AND EXISTS (
    SELECT 1 FROM public.bleeding_episodes e
    WHERE e.user_id = v_user_id AND e.lifecycle_status = 'open'
  ) THEN
    RAISE EXCEPTION 'another episode is open; it cannot be restored as open';
  END IF;

  v_until := CASE
    WHEN v_archived.end_date IS NOT NULL THEN v_archived.end_date
    WHEN v_archived.lifecycle_status = 'ended' THEN v_archived.start_date
    ELSE public.bleeding_local_today(0) + 1
  END;
  IF EXISTS (
    SELECT 1 FROM public.bleeding_episodes e
    WHERE e.user_id = v_user_id
      AND e.start_date <= v_until
      AND coalesce(e.end_date,
            CASE WHEN e.lifecycle_status = 'ended' THEN e.start_date
                 ELSE 'infinity'::date END) >= v_archived.start_date
  ) THEN
    RAISE EXCEPTION 'the removed episode overlaps a period recorded since';
  END IF;

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state,
    after_state
  ) VALUES (
    v_user_id, p_episode_id, p_client_operation_id, 'restore',
    jsonb_build_object('removed', true), '{}'::jsonb
  ) RETURNING id INTO v_revision_id;

  -- Lift only this removal's tombstones first, so its rows may re-enter.
  DELETE FROM public.bleeding_operation_tombstones t
  WHERE t.revision_id = v_archived.archived_by_revision AND t.user_id = v_user_id;

  INSERT INTO public.bleeding_episodes
  SELECT (jsonb_populate_record(NULL::public.bleeding_episodes,
            to_jsonb(v_archived) - 'archived_at' - 'archived_by_revision')).*;

  PERFORM set_config('niswah.restoring_episode', p_episode_id::text, true);
  FOR v_obs IN
    SELECT * FROM public.bleeding_observations_archive a
    WHERE a.episode_id = p_episode_id
      AND a.archived_by_revision = v_archived.archived_by_revision
    ORDER BY a.reported_at, a.created_at
  LOOP
    INSERT INTO public.bleeding_observations
    SELECT (jsonb_populate_record(NULL::public.bleeding_observations,
              to_jsonb(v_obs) - 'archived_at' - 'archived_by_revision')).*;
  END LOOP;
  PERFORM set_config('niswah.restoring_episode', '', true);

  DELETE FROM public.bleeding_observations_archive a
  WHERE a.episode_id = p_episode_id
    AND a.archived_by_revision = v_archived.archived_by_revision;
  DELETE FROM public.bleeding_episodes_archive WHERE id = p_episode_id;

  UPDATE public.bleeding_episode_revisions
  SET after_state = public.bleeding_episode_snapshot(p_episode_id)
  WHERE id = v_revision_id;

  RETURN QUERY SELECT p_episode_id, v_revision_id;
END;
$function$;

-- 5. Onboarding saves "stopped, not sure when".

CREATE OR REPLACE FUNCTION public.record_onboarding_menstrual_history(p_client_operation_id uuid, p_utc_offset_minutes integer, p_start_date date DEFAULT NULL::date, p_start_precision text DEFAULT NULL::text, p_start_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_lifecycle_status text DEFAULT NULL::text, p_continuation_certainty text DEFAULT NULL::text, p_end_date date DEFAULT NULL::date, p_end_precision text DEFAULT NULL::text, p_end_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_usual_bleeding_duration_days integer DEFAULT NULL::integer, p_usual_cycle_length_days integer DEFAULT NULL::integer)
 RETURNS TABLE(episode_id uuid, baseline_id uuid, episode_conflict boolean, conflicting_episode_id uuid, conflicting_start_date date)
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
    -- PT-002: "it has stopped, I'm not sure when" is an ended episode
    -- whose end is unknown: no end date, no end time, no closing entry.
    IF p_end_precision = 'unknown' AND (p_end_date IS NOT NULL
        OR p_end_time IS NOT NULL OR p_lifecycle_status IS DISTINCT FROM 'ended') THEN
      RAISE EXCEPTION 'an unknown end needs an ended episode with no end date or time';
    END IF;
    IF p_lifecycle_status = 'ended' AND p_end_date IS NULL
      AND p_end_precision IS DISTINCT FROM 'unknown' THEN
      RAISE EXCEPTION 'an ended episode needs an end date or end_precision unknown';
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
      ELSIF p_end_precision = 'unknown' THEN
        SELECT e.id INTO v_episode_id
        FROM public.bleeding_episodes e
        WHERE e.user_id = v_user_id AND e.lifecycle_status = 'ended'
          AND e.start_date = p_start_date AND e.end_date IS NULL
        LIMIT 1;
      END IF;

      IF v_episode_id IS NULL THEN
        SELECT e.start_date, coalesce(e.end_date, e.start_date)
          INTO v_overlap_start, v_overlap_end
        FROM public.bleeding_episodes e
        WHERE e.user_id = v_user_id AND e.lifecycle_status = 'ended'
          AND coalesce(e.end_date, e.start_date) >= p_start_date
          AND (p_end_date IS NULL OR e.start_date <= p_end_date)
        ORDER BY coalesce(e.end_date, e.start_date) DESC
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
        CASE WHEN p_end_date IS NULL THEN NULL ELSE p_end_precision END,
        p_end_time, v_derived_end_source, p_client_operation_id
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
          continuation_certainty = p_continuation_certainty,
          end_precision = CASE WHEN p_end_precision = 'unknown' THEN 'unknown'
                               ELSE end_precision END,
          end_source = CASE WHEN p_end_precision = 'unknown' THEN 'user_reported_historical'
                            ELSE end_source END
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
