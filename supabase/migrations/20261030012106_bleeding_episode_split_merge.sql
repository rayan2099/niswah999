-- SPLIT AND MERGE PERIODS (period tracking cases PT-045, PT-046;
-- app-wide journeys NJ-101..NJ-104 and NJ-279), 2026-10-30.
--
-- Two periods recorded as one can be split, and two recorded separately
-- can be merged. Both only ever regroup what she recorded:
--
-- * No observation is rewritten, re-dated or deleted. Observations keep
--   their ids, dates, flows and correction chains; only the period they
--   belong to (episode_id) changes, and the revision row lists every id
--   that moved.
-- * Days she did not answer stay unanswered. A merge does not fill the
--   gap between the two periods, and a split does not invent an end for
--   the first part: she gives its first clean day, or says she is not
--   sure (end_precision 'unknown', 20261029130000).
-- * Each call is one transaction: everything applies or nothing does
--   (NJ-104). Without p_confirm the call raises SQLSTATE NW422 with the
--   number of entries that would move, so the app can show a preview and
--   nothing is written (NJ-101, NJ-103).
-- * Each period carries its revision token (updated_at); a period changed
--   on another device in between is refused with NW409 (NJ-279).
-- * Every action is idempotent on its client operation id and appends a
--   before/after snapshot to bleeding_episode_revisions. undo_episode_split
--   and undo_episode_merge put the previous grouping back, and are refused
--   (NW409) once either period changed or gained an entry after it.
-- * A delayed operation cannot recreate what a merge folded away: the
--   start operation of the second period and the end operation of the
--   first are tombstoned (NW410), as reopen_episode already does.
--
-- Interpretation is not decided here. The app computes predictions and
-- fiqh state from the resulting periods exactly as for any other period.
--
-- Additive except for widening the revisions action CHECK constraint
-- (dropped and re-added with four more values, idempotent). Requires
-- 20261029100000, 20261029120000 and 20261029130000.

ALTER TABLE public.bleeding_episode_revisions
  DROP CONSTRAINT IF EXISTS bleeding_episode_revisions_action_check;
ALTER TABLE public.bleeding_episode_revisions
  ADD CONSTRAINT bleeding_episode_revisions_action_check CHECK (action IN (
    'correct_start', 'correct_end', 'reopen', 'remove', 'restore',
    'remove_observation', 'restore_observation',
    'split', 'merge', 'undo_split', 'undo_merge'));

-- 1. split_episode -----------------------------------------------------------
-- The period becomes two: the first keeps its id and start and ends with
-- p_first_end_date as its first clean day (or an unknown end when NULL);
-- a new period starts on p_second_start_date, which must have bleeding
-- recorded, and takes over the original end (or stays open) and every
-- entry dated on or after that day.
CREATE OR REPLACE FUNCTION public.split_episode(
  p_client_operation_id uuid,
  p_episode_id uuid,
  p_second_start_date date,
  p_first_end_date date,
  p_timezone text,
  p_utc_offset_minutes integer,
  p_expected_updated_at timestamptz DEFAULT NULL,
  p_confirm boolean DEFAULT false
)
RETURNS TABLE (episode_id uuid, second_episode_id uuid, revision_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_revision_id uuid;
  v_episode public.bleeding_episodes;
  v_before jsonb;
  v_moved uuid[];
  v_second_id uuid := gen_random_uuid();
  v_closing uuid;
BEGIN
  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, p_episode_id, p_expected_updated_at);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY
      SELECT r.episode_id, (r.after_state->>'second_episode_id')::uuid, r.id
      FROM public.bleeding_episode_revisions r WHERE r.id = v_revision_id;
    RETURN;
  END IF;

  SELECT * INTO v_episode FROM public.bleeding_episodes e WHERE e.id = p_episode_id;
  v_before := public.bleeding_episode_snapshot(p_episode_id);

  IF p_second_start_date IS NULL THEN
    RAISE EXCEPTION 'the second period''s start date is required';
  END IF;
  IF p_second_start_date <= v_episode.start_date THEN
    RAISE EXCEPTION 'the second period must start after % (got %)',
      v_episode.start_date, p_second_start_date;
  END IF;
  IF v_episode.end_date IS NOT NULL AND p_second_start_date >= v_episode.end_date THEN
    RAISE EXCEPTION 'the second period must start before this period ended (%)',
      v_episode.end_date;
  END IF;
  IF p_second_start_date > public.bleeding_local_today(p_utc_offset_minutes) THEN
    RAISE EXCEPTION 'the second period cannot start in the future (got %)',
      p_second_start_date;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.bleeding_effective_observations(p_episode_id) o
    WHERE o.observed_date = p_second_start_date
      AND o.flow IN ('spotting', 'light', 'medium', 'heavy', 'uncertain')
  ) THEN
    RAISE EXCEPTION 'no bleeding is recorded on %; a period can only start on a day with bleeding recorded',
      p_second_start_date;
  END IF;

  IF p_first_end_date IS NOT NULL THEN
    IF p_first_end_date <= v_episode.start_date
       OR p_first_end_date >= p_second_start_date THEN
      RAISE EXCEPTION 'the first period''s end (%) must fall after its start and before the second period starts',
        p_first_end_date;
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.bleeding_effective_observations(p_episode_id) o
      WHERE o.observed_date >= p_first_end_date
        AND o.observed_date < p_second_start_date
        AND o.flow IN ('spotting', 'light', 'medium', 'heavy', 'uncertain')
    ) THEN
      RAISE EXCEPTION 'bleeding is recorded between % and %; choose a later end for the first period',
        p_first_end_date, p_second_start_date;
    END IF;
  END IF;

  -- A correction chain must never end up split across two periods.
  IF EXISTS (
    SELECT 1 FROM public.bleeding_observations o
    JOIN public.bleeding_observations s ON s.supersedes_id = o.id
    WHERE o.episode_id = p_episode_id
      AND (o.observed_date >= p_second_start_date) <> (s.observed_date >= p_second_start_date)
  ) THEN
    RAISE EXCEPTION 'a corrected entry spans %; correct it first', p_second_start_date;
  END IF;

  SELECT coalesce(array_agg(o.id ORDER BY o.observed_date, o.reported_at), '{}')
    INTO v_moved
  FROM public.bleeding_observations o
  WHERE o.episode_id = p_episode_id AND o.observed_date >= p_second_start_date;

  IF NOT p_confirm THEN
    RAISE EXCEPTION '% entries would move to the second period', cardinality(v_moved)
      USING ERRCODE = 'NW422',
            DETAIL = cardinality(v_moved)::text;
  END IF;

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state, after_state
  ) VALUES (
    v_user_id, p_episode_id, p_client_operation_id, 'split',
    jsonb_build_object(
      'episode', v_before,
      'moved_observation_ids', to_jsonb(v_moved),
      'kept_observation_ids', (
        SELECT coalesce(jsonb_agg(o.id), '[]'::jsonb) FROM public.bleeding_observations o
        WHERE o.episode_id = p_episode_id AND o.observed_date < p_second_start_date)),
    '{}'::jsonb
  ) RETURNING id INTO v_revision_id;

  -- End the first part first: frees the one-open-period slot and the
  -- end operation id for the second part.
  UPDATE public.bleeding_episodes
  SET lifecycle_status = 'ended',
      continuation_certainty = NULL,
      end_date = p_first_end_date,
      end_precision = CASE WHEN p_first_end_date IS NULL THEN 'unknown' ELSE 'date_only' END,
      end_time = NULL,
      end_source = 'user_reported_historical',
      end_client_operation_id = NULL
  WHERE id = p_episode_id;

  INSERT INTO public.bleeding_episodes (
    id, user_id, lifecycle_status, continuation_certainty, start_date,
    start_precision, start_time, start_source, end_date, end_precision,
    end_time, end_source, end_client_operation_id
  ) VALUES (
    v_second_id, v_user_id, v_episode.lifecycle_status,
    v_episode.continuation_certainty, p_second_start_date, 'date_only', NULL,
    'user_reported_historical', v_episode.end_date, v_episode.end_precision,
    v_episode.end_time, v_episode.end_source, v_episode.end_client_operation_id
  );

  UPDATE public.bleeding_observations o SET episode_id = v_second_id
  WHERE o.id = ANY(v_moved);

  -- The first part's first clean day, unless she already recorded it.
  IF p_first_end_date IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.bleeding_effective_observations(p_episode_id) o
    WHERE o.observed_date = p_first_end_date AND o.flow = 'none'
  ) THEN
    PERFORM set_config('niswah.restoring_episode', p_episode_id::text, true);
    INSERT INTO public.bleeding_observations (
      user_id, episode_id, observed_date, observed_time, precision, flow,
      source, timezone, utc_offset_minutes
    ) VALUES (
      v_user_id, p_episode_id, p_first_end_date, NULL, 'date_only', 'none',
      'user_reported_historical', p_timezone, p_utc_offset_minutes
    ) RETURNING id INTO v_closing;
    PERFORM set_config('niswah.restoring_episode', '', true);
  END IF;

  UPDATE public.bleeding_episode_revisions
  SET after_state = jsonb_build_object(
        'first', public.bleeding_episode_snapshot(p_episode_id),
        'second', public.bleeding_episode_snapshot(v_second_id),
        'second_episode_id', v_second_id,
        'closing_observation_id', v_closing)
  WHERE id = v_revision_id;

  RETURN QUERY SELECT p_episode_id, v_second_id, v_revision_id;
END;
$function$;

-- 2. merge_episodes ----------------------------------------------------------
-- Two neighbouring periods become one: the first keeps its id and start
-- and takes over the second's end (or stays open when the second is);
-- every entry of the second moves to it unchanged, its own closing "no
-- bleeding" entry included, and the days between them stay unanswered.
-- The second period goes to bleeding_episodes_archive so the merge can be
-- undone with the same ids.
CREATE OR REPLACE FUNCTION public.merge_episodes(
  p_client_operation_id uuid,
  p_first_episode_id uuid,
  p_second_episode_id uuid,
  p_expected_first_updated_at timestamptz DEFAULT NULL,
  p_expected_second_updated_at timestamptz DEFAULT NULL,
  p_confirm boolean DEFAULT false
)
RETURNS TABLE (episode_id uuid, revision_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_revision_id uuid;
  v_first public.bleeding_episodes;
  v_second public.bleeding_episodes;
  v_before_first jsonb;
  v_moved uuid[];
BEGIN
  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, p_first_episode_id, p_expected_first_updated_at);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY SELECT p_first_episode_id, v_revision_id;
    RETURN;
  END IF;

  IF p_second_episode_id IS NULL OR p_second_episode_id = p_first_episode_id THEN
    RAISE EXCEPTION 'two different periods are required';
  END IF;
  SELECT * INTO v_first FROM public.bleeding_episodes e WHERE e.id = p_first_episode_id;
  SELECT * INTO v_second FROM public.bleeding_episodes e
  WHERE e.id = p_second_episode_id FOR UPDATE;
  IF v_second.user_id IS NULL OR v_second.user_id <> v_user_id THEN
    RAISE EXCEPTION
      'episode % does not exist or does not belong to the calling user',
      p_second_episode_id;
  END IF;
  IF p_expected_second_updated_at IS NOT NULL
     AND v_second.updated_at IS DISTINCT FROM p_expected_second_updated_at THEN
    RAISE EXCEPTION
      'episode % changed since it was loaded; reload and try again', p_second_episode_id
      USING ERRCODE = 'NW409';
  END IF;

  IF v_first.start_date >= v_second.start_date THEN
    RAISE EXCEPTION 'the first period must start before the second';
  END IF;
  IF v_first.lifecycle_status <> 'ended' THEN
    RAISE EXCEPTION 'the first period is still open';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.bleeding_episodes e
    WHERE e.user_id = v_user_id
      AND e.id NOT IN (p_first_episode_id, p_second_episode_id)
      AND e.start_date > v_first.start_date
      AND e.start_date < v_second.start_date
  ) THEN
    RAISE EXCEPTION 'another period lies between them; only neighbouring periods can be merged';
  END IF;

  SELECT coalesce(array_agg(o.id ORDER BY o.observed_date, o.reported_at), '{}')
    INTO v_moved
  FROM public.bleeding_observations o WHERE o.episode_id = p_second_episode_id;

  IF NOT p_confirm THEN
    RAISE EXCEPTION '% entries would move into the first period', cardinality(v_moved)
      USING ERRCODE = 'NW422',
            DETAIL = cardinality(v_moved)::text;
  END IF;

  v_before_first := public.bleeding_episode_snapshot(p_first_episode_id);
  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state, after_state
  ) VALUES (
    v_user_id, p_first_episode_id, p_client_operation_id, 'merge',
    jsonb_build_object(
      'first', v_before_first,
      'second', to_jsonb(v_second) - 'user_id',
      'moved_observation_ids', to_jsonb(v_moved),
      'kept_observation_ids', (
        SELECT coalesce(jsonb_agg(o.id), '[]'::jsonb) FROM public.bleeding_observations o
        WHERE o.episode_id = p_first_episode_id)),
    '{}'::jsonb
  ) RETURNING id INTO v_revision_id;

  -- A delayed "start" of the second period or "end" of the first must not
  -- bring the old grouping back.
  INSERT INTO public.bleeding_operation_tombstones (client_operation_id, user_id, revision_id)
  SELECT x, v_user_id, v_revision_id
  FROM unnest(ARRAY[v_second.client_operation_id, v_first.end_client_operation_id]) AS x
  WHERE x IS NOT NULL
  ON CONFLICT (client_operation_id) DO NOTHING;

  UPDATE public.bleeding_observations o SET episode_id = p_first_episode_id
  WHERE o.id = ANY(v_moved);

  INSERT INTO public.bleeding_episodes_archive
  SELECT e.*, now(), v_revision_id FROM public.bleeding_episodes e
  WHERE e.id = p_second_episode_id;
  DELETE FROM public.bleeding_episodes e WHERE e.id = p_second_episode_id;

  UPDATE public.bleeding_episodes
  SET lifecycle_status = v_second.lifecycle_status,
      continuation_certainty = v_second.continuation_certainty,
      end_date = v_second.end_date,
      end_precision = v_second.end_precision,
      end_time = v_second.end_time,
      end_source = v_second.end_source,
      end_client_operation_id = v_second.end_client_operation_id
  WHERE id = p_first_episode_id;

  UPDATE public.bleeding_episode_revisions
  SET after_state = public.bleeding_episode_snapshot(p_first_episode_id)
  WHERE id = v_revision_id;

  RETURN QUERY SELECT p_first_episode_id, v_revision_id;
END;
$function$;

-- 3. undo_episode_split ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.undo_episode_split(
  p_client_operation_id uuid,
  p_split_revision_id uuid
)
RETURNS TABLE (episode_id uuid, revision_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_revision_id uuid;
  v_split public.bleeding_episode_revisions;
  v_second_id uuid;
  v_before jsonb;
  v_moved uuid[];
  v_kept uuid[];
  v_closing uuid;
BEGIN
  SELECT * INTO v_split FROM public.bleeding_episode_revisions r
  WHERE r.id = p_split_revision_id AND r.user_id = v_user_id AND r.action = 'split';
  IF v_split.id IS NULL THEN
    RAISE EXCEPTION 'split % does not exist or does not belong to the calling user',
      p_split_revision_id;
  END IF;

  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, v_split.episode_id,
    (v_split.after_state->'first'->>'updated_at')::timestamptz);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY SELECT v_split.episode_id, v_revision_id;
    RETURN;
  END IF;

  v_second_id := (v_split.after_state->>'second_episode_id')::uuid;
  v_closing := (v_split.after_state->>'closing_observation_id')::uuid;
  v_before := v_split.before_state->'episode';
  SELECT coalesce(array_agg(x::uuid), '{}') INTO v_moved
  FROM jsonb_array_elements_text(v_split.before_state->'moved_observation_ids') AS x;
  SELECT coalesce(array_agg(x::uuid), '{}') INTO v_kept
  FROM jsonb_array_elements_text(v_split.before_state->'kept_observation_ids') AS x;

  PERFORM 1 FROM public.bleeding_episodes e WHERE e.id = v_second_id FOR UPDATE;
  IF NOT EXISTS (
    SELECT 1 FROM public.bleeding_episodes e
    WHERE e.id = v_second_id
      AND e.updated_at = (v_split.after_state->'second'->>'updated_at')::timestamptz
  ) OR EXISTS (
    SELECT 1 FROM public.bleeding_observations o
    WHERE o.episode_id IN (v_split.episode_id, v_second_id)
      AND NOT (o.id = ANY(v_moved || v_kept))
      AND o.id IS DISTINCT FROM v_closing
  ) OR (
    SELECT count(*) FROM public.bleeding_observations o
    WHERE (o.id = ANY(v_moved) AND o.episode_id = v_second_id)
       OR (o.id = ANY(v_kept) AND o.episode_id = v_split.episode_id)
  ) <> cardinality(v_moved) + cardinality(v_kept) THEN
    RAISE EXCEPTION 'the periods changed after the split; it can no longer be undone'
      USING ERRCODE = 'NW409';
  END IF;

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state,
    after_state, retracted_observation_ids
  ) VALUES (
    v_user_id, v_split.episode_id, p_client_operation_id, 'undo_split',
    jsonb_build_object('split_revision_id', v_split.id), '{}'::jsonb,
    CASE WHEN v_closing IS NULL THEN '{}'::uuid[] ELSE ARRAY[v_closing] END
  ) RETURNING id INTO v_revision_id;

  -- The first clean day the split added is taken out again (archived).
  IF v_closing IS NOT NULL THEN
    PERFORM public.bleeding_archive_observations(v_user_id, ARRAY[v_closing], v_revision_id);
  END IF;

  UPDATE public.bleeding_observations o SET episode_id = v_split.episode_id
  WHERE o.id = ANY(v_moved);
  DELETE FROM public.bleeding_episodes e WHERE e.id = v_second_id;

  UPDATE public.bleeding_episodes
  SET lifecycle_status = v_before->>'lifecycle_status',
      continuation_certainty = v_before->>'continuation_certainty',
      end_date = (v_before->>'end_date')::date,
      end_precision = v_before->>'end_precision',
      end_time = (v_before->>'end_time')::timestamptz,
      end_source = v_before->>'end_source',
      end_client_operation_id = (v_before->>'end_client_operation_id')::uuid
  WHERE id = v_split.episode_id;

  UPDATE public.bleeding_episode_revisions
  SET after_state = public.bleeding_episode_snapshot(v_split.episode_id)
  WHERE id = v_revision_id;

  RETURN QUERY SELECT v_split.episode_id, v_revision_id;
END;
$function$;

-- 4. undo_episode_merge ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.undo_episode_merge(
  p_client_operation_id uuid,
  p_merge_revision_id uuid
)
RETURNS TABLE (episode_id uuid, second_episode_id uuid, revision_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_revision_id uuid;
  v_merge public.bleeding_episode_revisions;
  v_first jsonb;
  v_second_id uuid;
  v_archived public.bleeding_episodes_archive;
  v_moved uuid[];
  v_kept uuid[];
BEGIN
  SELECT * INTO v_merge FROM public.bleeding_episode_revisions r
  WHERE r.id = p_merge_revision_id AND r.user_id = v_user_id AND r.action = 'merge';
  IF v_merge.id IS NULL THEN
    RAISE EXCEPTION 'merge % does not exist or does not belong to the calling user',
      p_merge_revision_id;
  END IF;
  v_second_id := (v_merge.before_state->'second'->>'id')::uuid;

  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, v_merge.episode_id,
    (v_merge.after_state->>'updated_at')::timestamptz);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY SELECT v_merge.episode_id, v_second_id, v_revision_id;
    RETURN;
  END IF;

  v_first := v_merge.before_state->'first';
  SELECT coalesce(array_agg(x::uuid), '{}') INTO v_moved
  FROM jsonb_array_elements_text(v_merge.before_state->'moved_observation_ids') AS x;
  SELECT coalesce(array_agg(x::uuid), '{}') INTO v_kept
  FROM jsonb_array_elements_text(v_merge.before_state->'kept_observation_ids') AS x;
  SELECT * INTO v_archived FROM public.bleeding_episodes_archive a
  WHERE a.id = v_second_id AND a.archived_by_revision = v_merge.id;

  IF v_archived.id IS NULL OR EXISTS (
    SELECT 1 FROM public.bleeding_observations o
    WHERE o.episode_id = v_merge.episode_id AND NOT (o.id = ANY(v_moved || v_kept))
  ) OR (
    SELECT count(*) FROM public.bleeding_observations o
    WHERE o.id = ANY(v_moved || v_kept) AND o.episode_id = v_merge.episode_id
  ) <> cardinality(v_moved) + cardinality(v_kept) THEN
    RAISE EXCEPTION 'the period changed after the merge; it can no longer be undone'
      USING ERRCODE = 'NW409';
  END IF;

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state, after_state
  ) VALUES (
    v_user_id, v_merge.episode_id, p_client_operation_id, 'undo_merge',
    jsonb_build_object('merge_revision_id', v_merge.id), '{}'::jsonb
  ) RETURNING id INTO v_revision_id;

  -- The first period's own end comes back first, freeing the open slot and
  -- the second period's end operation id.
  UPDATE public.bleeding_episodes
  SET lifecycle_status = v_first->>'lifecycle_status',
      continuation_certainty = v_first->>'continuation_certainty',
      end_date = (v_first->>'end_date')::date,
      end_precision = v_first->>'end_precision',
      end_time = (v_first->>'end_time')::timestamptz,
      end_source = v_first->>'end_source',
      end_client_operation_id = (v_first->>'end_client_operation_id')::uuid
  WHERE id = v_merge.episode_id;

  DELETE FROM public.bleeding_operation_tombstones t
  WHERE t.revision_id = v_merge.id AND t.user_id = v_user_id;

  INSERT INTO public.bleeding_episodes
  SELECT (jsonb_populate_record(NULL::public.bleeding_episodes,
            to_jsonb(v_archived) - 'archived_at' - 'archived_by_revision')).*;
  DELETE FROM public.bleeding_episodes_archive a WHERE a.id = v_second_id;

  UPDATE public.bleeding_observations o SET episode_id = v_second_id
  WHERE o.id = ANY(v_moved);

  UPDATE public.bleeding_episode_revisions
  SET after_state = jsonb_build_object(
        'first', public.bleeding_episode_snapshot(v_merge.episode_id),
        'second', public.bleeding_episode_snapshot(v_second_id))
  WHERE id = v_revision_id;

  RETURN QUERY SELECT v_merge.episode_id, v_second_id, v_revision_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.split_episode(uuid, uuid, date, date, text, integer, timestamptz, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.merge_episodes(uuid, uuid, uuid, timestamptz, timestamptz, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.undo_episode_split(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.undo_episode_merge(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.split_episode(uuid, uuid, date, date, text, integer, timestamptz, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.merge_episodes(uuid, uuid, uuid, timestamptz, timestamptz, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.undo_episode_split(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.undo_episode_merge(uuid, uuid) TO authenticated, service_role;
