-- REMOVE ONE DAY'S ENTRY (period tracking case PT-055, 2026-10-29)
--
-- Before this migration a woman could correct a day's entry (a new row
-- superseding it) but never take it out: an entry logged on the wrong day,
-- or twice, stayed in her history. Builds on
-- 20261029100000_bleeding_episode_corrections.sql and uses the same model:
--
--   remove_observation   moves the entry's whole correction chain to
--                        bleeding_observations_archive, tombstones its
--                        operation ids (a queued replay cannot bring it
--                        back, NW410), deletes its cycle_entries mirrors
--                        and logs a revision. Undoable.
--   restore_observation  puts the removed entry back with the same ids,
--                        unless a newer entry now covers that day.
--
-- Two entries are never removed this way, because removing them would
-- leave a period without a start or an ended period without its end:
-- the start entry (change the start date or remove the period instead)
-- and the closing "no bleeding" entry of an ended period (use "I'm still
-- bleeding" or change the end date instead). Those raise NW423.
--
-- Both RPCs bump the episode's updated_at, so an edit form opened on
-- another device before the change is refused (NW409) like any other
-- change to the period. Both take the optional p_expected_updated_at.
--
-- Additive except for widening the revisions action CHECK constraint,
-- which is dropped and re-added with two more values (idempotent), and a
-- tie-safe replacement of bleeding_archive_observations (see below).

ALTER TABLE public.bleeding_episode_revisions
  DROP CONSTRAINT IF EXISTS bleeding_episode_revisions_action_check;
ALTER TABLE public.bleeding_episode_revisions
  ADD CONSTRAINT bleeding_episode_revisions_action_check CHECK (action IN (
    'correct_start', 'correct_end', 'reopen', 'remove', 'restore',
    'remove_observation', 'restore_observation'));

-- Archive helper from 20261029100000, made independent of timestamps: rows
-- are deleted tips-first along their correction chains (a row is deleted
-- only once nothing still live supersedes it), instead of by reported_at,
-- which ties when a correction and its target were written in the same
-- transaction. Same signature, same grants, same result.
CREATE OR REPLACE FUNCTION public.bleeding_archive_observations(
  p_user_id uuid, p_ids uuid[], p_revision_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN;
  END IF;

  INSERT INTO public.bleeding_observations_archive
  SELECT o.*, now(), p_revision_id
  FROM public.bleeding_observations o
  WHERE o.id = ANY(p_ids) AND o.user_id = p_user_id;

  INSERT INTO public.bleeding_operation_tombstones (client_operation_id, user_id, revision_id)
  SELECT o.client_operation_id, p_user_id, p_revision_id
  FROM public.bleeding_observations o
  WHERE o.id = ANY(p_ids) AND o.user_id = p_user_id
    AND o.client_operation_id IS NOT NULL
  ON CONFLICT (client_operation_id) DO NOTHING;

  DELETE FROM public.cycle_entries c
  WHERE c.id = ANY(p_ids) AND c.user_id = p_user_id;

  LOOP
    DELETE FROM public.bleeding_observations o
    WHERE o.id = ANY(p_ids) AND o.user_id = p_user_id
      AND NOT EXISTS (SELECT 1 FROM public.bleeding_observations s WHERE s.supersedes_id = o.id);
    EXIT WHEN NOT FOUND;
  END LOOP;

  IF EXISTS (SELECT 1 FROM public.bleeding_observations o
             WHERE o.id = ANY(p_ids) AND o.user_id = p_user_id) THEN
    RAISE EXCEPTION 'an entry to archive is still superseded by a live entry';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.bleeding_archive_observations(uuid, uuid[], uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.remove_observation(
  p_client_operation_id uuid,
  p_observation_id uuid,
  p_expected_updated_at timestamptz DEFAULT NULL
)
RETURNS TABLE (episode_id uuid, revision_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_revision_id uuid;
  v_obs public.bleeding_observations;
  v_tip public.bleeding_observations;
  v_episode public.bleeding_episodes;
  v_before jsonb;
  v_retract uuid[];
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'an authenticated user is required';
  END IF;

  -- Replay of this operation: return what it did, whatever exists now.
  SELECT r.episode_id, r.id INTO episode_id, revision_id
  FROM public.bleeding_episode_revisions r
  WHERE r.user_id = v_user_id AND r.client_operation_id = p_client_operation_id;
  IF revision_id IS NOT NULL THEN
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO v_obs FROM public.bleeding_observations o
  WHERE o.id = p_observation_id AND o.user_id = v_user_id;
  IF v_obs.id IS NULL THEN
    RAISE EXCEPTION
      'observation % does not exist or does not belong to the calling user',
      p_observation_id;
  END IF;

  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, v_obs.episode_id, p_expected_updated_at);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY SELECT v_obs.episode_id, v_revision_id;
    RETURN;
  END IF;

  -- The current value of this fact: the end of its correction chain.
  WITH RECURSIVE forward(id) AS (
    SELECT v_obs.id
    UNION
    SELECT s.id FROM public.bleeding_observations s JOIN forward f ON s.supersedes_id = f.id
  )
  SELECT o.* INTO v_tip FROM public.bleeding_observations o
  WHERE o.id IN (SELECT id FROM forward)
    AND NOT EXISTS (SELECT 1 FROM public.bleeding_observations s WHERE s.supersedes_id = o.id);

  SELECT * INTO v_episode FROM public.bleeding_episodes e WHERE e.id = v_obs.episode_id;

  IF v_tip.observed_date = v_episode.start_date
     AND v_tip.flow IN ('spotting', 'light', 'medium', 'heavy', 'uncertain')
     AND NOT EXISTS (
       SELECT 1 FROM public.bleeding_effective_observations(v_episode.id) o
       WHERE o.id <> v_tip.id AND o.observed_date = v_episode.start_date
         AND o.flow IN ('spotting', 'light', 'medium', 'heavy', 'uncertain')
     ) THEN
    RAISE EXCEPTION 'the start entry of a period cannot be removed on its own'
      USING ERRCODE = 'NW423';
  END IF;
  IF v_episode.lifecycle_status = 'ended' AND v_tip.flow = 'none'
     AND v_tip.observed_date = v_episode.end_date THEN
    RAISE EXCEPTION 'the end entry of an ended period cannot be removed on its own'
      USING ERRCODE = 'NW423';
  END IF;

  v_before := public.bleeding_episode_snapshot(v_episode.id);
  v_retract := public.bleeding_observation_chains(ARRAY[v_tip.id]);

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state,
    after_state, retracted_observation_ids
  ) VALUES (
    v_user_id, v_episode.id, p_client_operation_id, 'remove_observation', v_before,
    v_before, v_retract
  ) RETURNING id INTO v_revision_id;

  PERFORM public.bleeding_archive_observations(v_user_id, v_retract, v_revision_id);

  UPDATE public.bleeding_episodes SET updated_at = now() WHERE id = v_episode.id;
  UPDATE public.bleeding_episode_revisions
  SET after_state = public.bleeding_episode_snapshot(v_episode.id)
  WHERE id = v_revision_id;

  RETURN QUERY SELECT v_episode.id, v_revision_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.restore_observation(
  p_client_operation_id uuid,
  p_removal_revision_id uuid
)
RETURNS TABLE (episode_id uuid, revision_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_revision_id uuid;
  v_removal public.bleeding_episode_revisions;
  v_row public.bleeding_observations_archive;
  v_tip_date date;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'an authenticated user is required';
  END IF;

  SELECT * INTO v_removal FROM public.bleeding_episode_revisions r
  WHERE r.id = p_removal_revision_id AND r.user_id = v_user_id
    AND r.action = 'remove_observation';
  IF v_removal.id IS NULL THEN
    RAISE EXCEPTION
      'removal % does not exist or does not belong to the calling user',
      p_removal_revision_id;
  END IF;

  -- Ownership, replay and stale-edit checks on the (live) episode. A
  -- period removed since cannot take the entry back.
  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, v_removal.episode_id, NULL);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY SELECT v_removal.episode_id, v_revision_id;
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.bleeding_observations_archive a
                 WHERE a.archived_by_revision = v_removal.id AND a.user_id = v_user_id) THEN
    RAISE EXCEPTION 'nothing to restore for removal %', v_removal.id;
  END IF;

  -- The day the removed entry was the current value for.
  SELECT a.observed_date INTO v_tip_date
  FROM public.bleeding_observations_archive a
  WHERE a.archived_by_revision = v_removal.id AND a.user_id = v_user_id
    AND NOT EXISTS (SELECT 1 FROM public.bleeding_observations_archive s
                    WHERE s.archived_by_revision = v_removal.id AND s.supersedes_id = a.id)
  LIMIT 1;
  IF EXISTS (SELECT 1 FROM public.bleeding_effective_observations(v_removal.episode_id) o
             WHERE o.observed_date = v_tip_date) THEN
    RAISE EXCEPTION 'a newer entry exists on % ; the removed entry was not restored', v_tip_date;
  END IF;

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state,
    after_state, retracted_observation_ids
  ) VALUES (
    v_user_id, v_removal.episode_id, p_client_operation_id, 'restore_observation',
    public.bleeding_episode_snapshot(v_removal.episode_id), '{}'::jsonb, '{}'
  ) RETURNING id INTO v_revision_id;

  DELETE FROM public.bleeding_operation_tombstones t
  WHERE t.revision_id = v_removal.id AND t.user_id = v_user_id;

  PERFORM set_config('niswah.restoring_episode', v_removal.episode_id::text, true);
  -- Oldest link of each correction chain first, so every supersedes_id
  -- points at a row already back.
  FOR v_row IN
    WITH RECURSIVE removed AS (
      SELECT a.* FROM public.bleeding_observations_archive a
      WHERE a.archived_by_revision = v_removal.id AND a.user_id = v_user_id
    ), depth(id, d) AS (
      SELECT r.id, 0 FROM removed r
      WHERE r.supersedes_id IS NULL OR r.supersedes_id NOT IN (SELECT id FROM removed)
      UNION ALL
      SELECT r.id, depth.d + 1 FROM removed r JOIN depth ON r.supersedes_id = depth.id
    )
    SELECT r.* FROM removed r JOIN depth USING (id) ORDER BY depth.d
  LOOP
    INSERT INTO public.bleeding_observations
    SELECT (jsonb_populate_record(NULL::public.bleeding_observations,
              to_jsonb(v_row) - 'archived_at' - 'archived_by_revision')).*;
  END LOOP;
  PERFORM set_config('niswah.restoring_episode', '', true);

  DELETE FROM public.bleeding_observations_archive a
  WHERE a.archived_by_revision = v_removal.id AND a.user_id = v_user_id;

  UPDATE public.bleeding_episodes SET updated_at = now() WHERE id = v_removal.episode_id;
  UPDATE public.bleeding_episode_revisions
  SET after_state = public.bleeding_episode_snapshot(v_removal.episode_id)
  WHERE id = v_revision_id;

  RETURN QUERY SELECT v_removal.episode_id, v_revision_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.remove_observation(uuid, uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.restore_observation(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_observation(uuid, uuid, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.restore_observation(uuid, uuid) TO authenticated, service_role;
