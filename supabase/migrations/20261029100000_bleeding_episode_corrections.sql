-- BLEEDING EPISODE CORRECTIONS (period tracking 200 cases, 2026-10-29)
--
-- Before this migration a woman who picked the wrong start or end date,
-- or tapped "period ended" by mistake, could never fix it: start_date is
-- column-revoked, correct_observation refuses to move the start or closing
-- observation (20261018090000 rule 4), there was no way to reopen an ended
-- episode, and no way to remove an episode at all. Cases PT-027, PT-051,
-- PT-052, PT-053, PT-054, PT-056, PT-057, PT-060 and PT-148 in
-- docs/period-tracking/PERIOD_TRACKING_200_CASES.md.
--
-- Five new SECURITY DEFINER RPCs, each idempotent on its own
-- p_client_operation_id and each optionally guarded by
-- p_expected_updated_at (another device changed the episode first ->
-- SQLSTATE NW409, the same code correct_observation already uses):
--
--   correct_episode_start  move the start earlier or later
--   correct_episode_end    move the end (first clean day) of an ended episode
--   reopen_episode         undo an end: the episode is open again
--   remove_episode         take an episode out of her history (undoable)
--   restore_episode        put a removed episode back, ids unchanged
--
-- Nothing she recorded is overwritten or deleted outright:
-- * every action appends a before/after snapshot to
--   bleeding_episode_revisions (append-only, readable by its owner);
-- * a moved end is a correction row (supersedes_id) like any other;
-- * observations that a change makes contradictory (bleeding recorded
--   before a later start, after an earlier end, or the closing "no
--   bleeding" of an undone end) are only taken out with her explicit
--   confirmation (p_retract_conflicting) and are moved, unchanged, to
--   bleeding_observations_archive; a removed episode moves with all its
--   observations to bleeding_episodes_archive. restore_episode moves them
--   back with the same ids.
-- * Without confirmation the RPC raises SQLSTATE NW422 naming how many
--   entries would be taken out, so the app can show a preview first.
--
-- A delayed operation must never undo a removal or a reopen: the client
-- operation ids of every archived row are written to
-- bleeding_operation_tombstones, and a BEFORE INSERT trigger on both
-- tracking tables rejects a row carrying a tombstoned id with SQLSTATE
-- NW410. So a queued start/end/observation replayed after she removed or
-- reopened the episode cannot recreate what she took out. restore_episode
-- clears the tombstones it archived.
--
-- The cycle_entries rows mirrored from archived or superseded observations
-- (cycle_entries.id = bleeding_observations.id, see
-- CycleEntriesProjection) are deleted here, server-side, so the AI context
-- and other cycle_entries readers stop seeing them even if the app never
-- syncs again. Restoring re-projects from the app.
--
-- Additive only: new tables, new functions, new triggers, and a CREATE OR
-- REPLACE of bleeding_observations_validate_insert that adds the tombstone
-- check and the restore-time allowance. No existing function signature,
-- grant, column or row changes. No DROP statements.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_episodes'
  ) THEN
    RETURN;
  END IF;

  -- 1. Revision log -------------------------------------------------------
  CREATE TABLE IF NOT EXISTS public.bleeding_episode_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    episode_id uuid NOT NULL,
    client_operation_id uuid NOT NULL,
    action text NOT NULL,
    before_state jsonb NOT NULL,
    after_state jsonb NOT NULL,
    retracted_observation_ids uuid[] NOT NULL DEFAULT '{}',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT bleeding_episode_revisions_action_check CHECK (action IN (
      'correct_start', 'correct_end', 'reopen', 'remove', 'restore'))
  );
  CREATE UNIQUE INDEX IF NOT EXISTS bleeding_episode_revisions_operation_unique
    ON public.bleeding_episode_revisions (user_id, client_operation_id);
  CREATE INDEX IF NOT EXISTS bleeding_episode_revisions_episode_idx
    ON public.bleeding_episode_revisions (episode_id, created_at);

  -- 2. Archive of removed / retracted rows (same columns + archive metadata)
  CREATE TABLE IF NOT EXISTS public.bleeding_episodes_archive (
    LIKE public.bleeding_episodes INCLUDING DEFAULTS,
    archived_at timestamptz NOT NULL DEFAULT now(),
    archived_by_revision uuid NOT NULL,
    PRIMARY KEY (id)
  );
  CREATE TABLE IF NOT EXISTS public.bleeding_observations_archive (
    LIKE public.bleeding_observations INCLUDING DEFAULTS,
    archived_at timestamptz NOT NULL DEFAULT now(),
    archived_by_revision uuid NOT NULL,
    PRIMARY KEY (id)
  );
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'bleeding_episodes_archive_user_fk') THEN
    ALTER TABLE public.bleeding_episodes_archive
      ADD CONSTRAINT bleeding_episodes_archive_user_fk
      FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'bleeding_observations_archive_user_fk') THEN
    ALTER TABLE public.bleeding_observations_archive
      ADD CONSTRAINT bleeding_observations_archive_user_fk
      FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
  CREATE INDEX IF NOT EXISTS bleeding_episodes_archive_user_idx
    ON public.bleeding_episodes_archive (user_id, archived_at DESC);
  CREATE INDEX IF NOT EXISTS bleeding_observations_archive_user_idx
    ON public.bleeding_observations_archive (user_id);
  CREATE INDEX IF NOT EXISTS bleeding_observations_archive_episode_idx
    ON public.bleeding_observations_archive (episode_id);

  -- 3. Tombstones for client operation ids of archived rows --------------
  CREATE TABLE IF NOT EXISTS public.bleeding_operation_tombstones (
    client_operation_id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    revision_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
  );
  CREATE INDEX IF NOT EXISTS bleeding_operation_tombstones_user_idx
    ON public.bleeding_operation_tombstones (user_id);
  CREATE INDEX IF NOT EXISTS bleeding_operation_tombstones_revision_idx
    ON public.bleeding_operation_tombstones (revision_id);

  -- Owner reads only; every write goes through the RPCs below.
  ALTER TABLE public.bleeding_episode_revisions ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.bleeding_episodes_archive ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.bleeding_observations_archive ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.bleeding_operation_tombstones ENABLE ROW LEVEL SECURITY;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'bleeding_episode_revisions'
      AND policyname = 'bleeding_episode_revisions_select_own') THEN
    CREATE POLICY bleeding_episode_revisions_select_own
      ON public.bleeding_episode_revisions
      FOR SELECT USING (user_id = (SELECT auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'bleeding_episodes_archive'
      AND policyname = 'bleeding_episodes_archive_select_own') THEN
    CREATE POLICY bleeding_episodes_archive_select_own
      ON public.bleeding_episodes_archive
      FOR SELECT USING (user_id = (SELECT auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'bleeding_observations_archive'
      AND policyname = 'bleeding_observations_archive_select_own') THEN
    CREATE POLICY bleeding_observations_archive_select_own
      ON public.bleeding_observations_archive
      FOR SELECT USING (user_id = (SELECT auth.uid()));
  END IF;

  REVOKE ALL ON public.bleeding_episode_revisions,
    public.bleeding_episodes_archive, public.bleeding_observations_archive,
    public.bleeding_operation_tombstones FROM anon, authenticated;
  GRANT SELECT ON public.bleeding_episode_revisions,
    public.bleeding_episodes_archive, public.bleeding_observations_archive
    TO authenticated;
  GRANT ALL ON public.bleeding_episode_revisions,
    public.bleeding_episodes_archive, public.bleeding_observations_archive,
    public.bleeding_operation_tombstones TO service_role;
END $$;

-- 4. Tombstone guard on both tracking tables -------------------------------
CREATE OR REPLACE FUNCTION public.bleeding_reject_tombstoned_operation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.client_operation_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.bleeding_operation_tombstones t
    WHERE t.client_operation_id = NEW.client_operation_id
  ) THEN
    RAISE EXCEPTION 'operation % was undone and cannot be applied again',
      NEW.client_operation_id
      USING ERRCODE = 'NW410';
  END IF;
  RETURN NEW;
END;
$function$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname = 'bleeding_episodes_reject_tombstoned') THEN
    CREATE TRIGGER bleeding_episodes_reject_tombstoned
      BEFORE INSERT ON public.bleeding_episodes
      FOR EACH ROW EXECUTE FUNCTION public.bleeding_reject_tombstoned_operation();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname = 'bleeding_observations_reject_tombstoned') THEN
    CREATE TRIGGER bleeding_observations_reject_tombstoned
      BEFORE INSERT ON public.bleeding_observations
      FOR EACH ROW EXECUTE FUNCTION public.bleeding_reject_tombstoned_operation();
  END IF;
END $$;

-- 5. Observation insert validation: unchanged rules, plus one allowance --
-- restore_episode re-inserts the observations of an ENDED episode it is
-- putting back. It sets the transaction-local setting
-- niswah.restoring_episode to that episode's id; only then may a row with
-- no supersedes_id land on an ended episode. Clients have no INSERT grant
-- on this table and cannot reach this path except through restore_episode.
CREATE OR REPLACE FUNCTION public.bleeding_observations_validate_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $trigger$
DECLARE
  v_episode_user_id uuid;
  v_episode_status text;
  v_local_today date;
  v_supersedes_user_id uuid;
  v_supersedes_episode_id uuid;
  v_restoring boolean := coalesce(
    current_setting('niswah.restoring_episode', true), '') = NEW.episode_id::text;
BEGIN
  SELECT user_id, lifecycle_status
    INTO v_episode_user_id, v_episode_status
  FROM public.bleeding_episodes
  WHERE id = NEW.episode_id;

  IF v_episode_user_id IS NULL THEN
    RAISE EXCEPTION 'episode % does not exist', NEW.episode_id;
  END IF;

  IF NEW.user_id <> v_episode_user_id THEN
    RAISE EXCEPTION
      'bleeding_observations.user_id must match its episode''s owner';
  END IF;

  IF v_episode_status = 'ended' AND NEW.supersedes_id IS NULL
     AND NOT v_restoring THEN
    RAISE EXCEPTION
      'cannot add a new fact to an ended episode (%) — only a '
      'correction (supersedes_id) is permitted', NEW.episode_id;
  END IF;

  v_local_today := ((now() AT TIME ZONE 'UTC')
    + make_interval(mins => NEW.utc_offset_minutes))::date;
  IF NEW.observed_date > v_local_today THEN
    RAISE EXCEPTION
      'observed_date cannot be in the future (got %, local today is %)',
      NEW.observed_date, v_local_today;
  END IF;

  IF NEW.supersedes_id IS NOT NULL THEN
    SELECT user_id, episode_id INTO v_supersedes_user_id, v_supersedes_episode_id
    FROM public.bleeding_observations
    WHERE id = NEW.supersedes_id;

    IF v_supersedes_user_id IS NULL THEN
      RAISE EXCEPTION 'supersedes_id % does not exist', NEW.supersedes_id;
    END IF;
    IF v_supersedes_user_id <> NEW.user_id THEN
      RAISE EXCEPTION
        'a correction must belong to the same user as the observation it supersedes';
    END IF;
    IF v_supersedes_episode_id <> NEW.episode_id THEN
      RAISE EXCEPTION
        'a correction must belong to the same episode as the observation it supersedes';
    END IF;
  END IF;

  RETURN NEW;
END;
$trigger$;

-- 6. Shared helpers (internal; not callable by clients) ----------------------

-- The episode as a jsonb snapshot for the revision log.
CREATE OR REPLACE FUNCTION public.bleeding_episode_snapshot(p_episode_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT to_jsonb(e) - 'user_id' FROM public.bleeding_episodes e
  WHERE e.id = p_episode_id;
$function$;

-- Ids of the observations of an episode that are the current value of
-- their fact (no correction supersedes them).
CREATE OR REPLACE FUNCTION public.bleeding_effective_observations(p_episode_id uuid)
RETURNS SETOF public.bleeding_observations
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT o.* FROM public.bleeding_observations o
  WHERE o.episode_id = p_episode_id
    AND NOT EXISTS (SELECT 1 FROM public.bleeding_observations s
                    WHERE s.supersedes_id = o.id);
$function$;

-- Every observation in the correction chains ending at p_tips (the tips
-- themselves and everything they supersede, transitively).
CREATE OR REPLACE FUNCTION public.bleeding_observation_chains(p_tips uuid[])
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH RECURSIVE chain(id, supersedes_id) AS (
    SELECT o.id, o.supersedes_id FROM public.bleeding_observations o
    WHERE o.id = ANY(p_tips)
    UNION
    SELECT o.id, o.supersedes_id FROM public.bleeding_observations o
    JOIN chain c ON o.id = c.supersedes_id
  )
  SELECT coalesce(array_agg(id), '{}') FROM chain;
$function$;

-- Moves observations (whole chains) to the archive, tombstones their
-- operation ids and deletes their cycle_entries mirrors. Rows are moved
-- newest-first so a correction never outlives the row it supersedes
-- inside the live table's self-reference.
CREATE OR REPLACE FUNCTION public.bleeding_archive_observations(
  p_user_id uuid, p_ids uuid[], p_revision_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.bleeding_observations;
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

  FOR v_row IN
    SELECT o.* FROM public.bleeding_observations o
    WHERE o.id = ANY(p_ids) AND o.user_id = p_user_id
    ORDER BY o.reported_at DESC, o.created_at DESC
  LOOP
    DELETE FROM public.bleeding_observations WHERE id = v_row.id;
  END LOOP;
END;
$function$;

-- Common preamble: authenticated caller, idempotent replay, ownership,
-- optimistic concurrency, per-user serialization. Returns the existing
-- revision id when this operation already ran (the caller then returns it
-- unchanged), or NULL to proceed.
CREATE OR REPLACE FUNCTION public.bleeding_episode_mutation_begin(
  p_user_id uuid,
  p_client_operation_id uuid,
  p_episode_id uuid,
  p_expected_updated_at timestamptz,
  p_from_archive boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_revision_id uuid;
  v_owner uuid;
  v_updated_at timestamptz;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'an authenticated user is required';
  END IF;
  IF p_client_operation_id IS NULL OR p_episode_id IS NULL THEN
    RAISE EXCEPTION 'client operation id and episode id are required';
  END IF;

  -- One episode mutation at a time per user, so overlap checks below see
  -- a stable set of episodes.
  PERFORM pg_advisory_xact_lock(hashtextextended('bleeding_episodes:' || p_user_id::text, 0));

  SELECT r.id INTO v_revision_id
  FROM public.bleeding_episode_revisions r
  WHERE r.user_id = p_user_id AND r.client_operation_id = p_client_operation_id;
  IF v_revision_id IS NOT NULL THEN
    RETURN v_revision_id;
  END IF;

  IF p_from_archive THEN
    SELECT a.user_id, a.updated_at INTO v_owner, v_updated_at
    FROM public.bleeding_episodes_archive a WHERE a.id = p_episode_id;
  ELSE
    SELECT e.user_id, e.updated_at INTO v_owner, v_updated_at
    FROM public.bleeding_episodes e WHERE e.id = p_episode_id FOR UPDATE;
  END IF;

  -- Same message whether it does not exist or is someone else's.
  IF v_owner IS NULL OR v_owner <> p_user_id THEN
    RAISE EXCEPTION
      'episode % does not exist or does not belong to the calling user',
      p_episode_id;
  END IF;

  IF p_expected_updated_at IS NOT NULL
     AND v_updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION
      'episode % changed since it was loaded; reload and try again', p_episode_id
      USING ERRCODE = 'NW409';
  END IF;

  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bleeding_local_today(p_utc_offset_minutes integer)
RETURNS date
LANGUAGE sql
STABLE
AS $function$
  SELECT ((now() AT TIME ZONE 'UTC')
    + make_interval(mins => coalesce(p_utc_offset_minutes, 0)))::date;
$function$;

-- 7. correct_episode_start ----------------------------------------------------
-- Earlier: a new start observation (flow p_flow) is recorded on the new
-- date; the days between stay "not recorded". Later: observations dated
-- before the new start contradict it; with p_retract_conflicting they are
-- archived (whole correction chains), otherwise NW422. If no bleeding is
-- recorded on the new start date, a new observation with p_flow is added.
CREATE OR REPLACE FUNCTION public.correct_episode_start(
  p_client_operation_id uuid,
  p_episode_id uuid,
  p_new_start_date date,
  p_flow text,
  p_timezone text,
  p_utc_offset_minutes integer,
  p_expected_updated_at timestamptz DEFAULT NULL,
  p_retract_conflicting boolean DEFAULT false
)
RETURNS TABLE (episode_id uuid, revision_id uuid)
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
  SELECT max(e.end_date) INTO v_prior_end
  FROM public.bleeding_episodes e
  WHERE e.user_id = v_user_id AND e.id <> p_episode_id
    AND e.start_date < v_episode.start_date
    AND e.end_date >= p_new_start_date;
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

-- 8. correct_episode_end ------------------------------------------------------
-- Ended episodes only (an open one is ended with end_bleeding_episode).
-- The closing "no bleeding" observation is corrected to the new date
-- (a normal supersedes_id correction). Bleeding recorded on or after the
-- new end contradicts it: archived with p_retract_conflicting, else NW422.
CREATE OR REPLACE FUNCTION public.correct_episode_end(
  p_client_operation_id uuid,
  p_episode_id uuid,
  p_new_end_date date,
  p_timezone text,
  p_utc_offset_minutes integer,
  p_expected_updated_at timestamptz DEFAULT NULL,
  p_retract_conflicting boolean DEFAULT false
)
RETURNS TABLE (episode_id uuid, revision_id uuid)
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

  IF p_new_end_date < v_episode.end_date THEN
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

-- 9. reopen_episode -----------------------------------------------------------
-- Undo an end she did not mean. The closing observation chain is archived
-- and its operation id tombstoned (a replayed end cannot end it again).
-- Refused when another episode is open or a later episode exists.
CREATE OR REPLACE FUNCTION public.reopen_episode(
  p_client_operation_id uuid,
  p_episode_id uuid,
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
  v_episode public.bleeding_episodes;
  v_before jsonb;
  v_closing uuid[];
  v_retract uuid[];
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
  IF EXISTS (SELECT 1 FROM public.bleeding_episodes e
             WHERE e.user_id = v_user_id AND e.lifecycle_status = 'open') THEN
    RAISE EXCEPTION 'another episode is open; end it before reopening this one';
  END IF;
  IF EXISTS (SELECT 1 FROM public.bleeding_episodes e
             WHERE e.user_id = v_user_id AND e.id <> p_episode_id
               AND e.start_date > v_episode.start_date) THEN
    RAISE EXCEPTION 'a later episode exists; only the most recent episode can be reopened';
  END IF;

  SELECT coalesce(array_agg(o.id), '{}') INTO v_closing
  FROM public.bleeding_effective_observations(p_episode_id) o
  WHERE o.flow = 'none' AND o.observed_date = v_episode.end_date;
  v_retract := public.bleeding_observation_chains(v_closing);

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state,
    after_state, retracted_observation_ids
  ) VALUES (
    v_user_id, p_episode_id, p_client_operation_id, 'reopen', v_before,
    '{}'::jsonb, v_retract
  ) RETURNING id INTO v_revision_id;

  PERFORM public.bleeding_archive_observations(v_user_id, v_retract, v_revision_id);
  IF v_episode.end_client_operation_id IS NOT NULL THEN
    INSERT INTO public.bleeding_operation_tombstones (client_operation_id, user_id, revision_id)
    VALUES (v_episode.end_client_operation_id, v_user_id, v_revision_id)
    ON CONFLICT (client_operation_id) DO NOTHING;
  END IF;

  UPDATE public.bleeding_episodes
  SET lifecycle_status = 'open',
      continuation_certainty = 'confirmed',
      end_date = NULL,
      end_precision = NULL,
      end_time = NULL,
      end_source = NULL,
      end_client_operation_id = NULL
  WHERE id = p_episode_id;

  UPDATE public.bleeding_episode_revisions
  SET after_state = public.bleeding_episode_snapshot(p_episode_id)
  WHERE id = v_revision_id;

  RETURN QUERY SELECT p_episode_id, v_revision_id;
END;
$function$;

-- 10. remove_episode ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.remove_episode(
  p_client_operation_id uuid,
  p_episode_id uuid,
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
  v_before jsonb;
  v_all uuid[];
  v_episode public.bleeding_episodes;
BEGIN
  v_revision_id := public.bleeding_episode_mutation_begin(
    v_user_id, p_client_operation_id, p_episode_id, p_expected_updated_at);
  IF v_revision_id IS NOT NULL THEN
    RETURN QUERY SELECT p_episode_id, v_revision_id;
    RETURN;
  END IF;

  SELECT * INTO v_episode FROM public.bleeding_episodes WHERE id = p_episode_id;
  v_before := public.bleeding_episode_snapshot(p_episode_id);
  SELECT coalesce(array_agg(o.id), '{}') INTO v_all
  FROM public.bleeding_observations o WHERE o.episode_id = p_episode_id;

  INSERT INTO public.bleeding_episode_revisions (
    user_id, episode_id, client_operation_id, action, before_state,
    after_state, retracted_observation_ids
  ) VALUES (
    v_user_id, p_episode_id, p_client_operation_id, 'remove', v_before,
    jsonb_build_object('removed', true), v_all
  ) RETURNING id INTO v_revision_id;

  PERFORM public.bleeding_archive_observations(v_user_id, v_all, v_revision_id);

  INSERT INTO public.bleeding_episodes_archive
  SELECT e.*, now(), v_revision_id FROM public.bleeding_episodes e
  WHERE e.id = p_episode_id;

  INSERT INTO public.bleeding_operation_tombstones (client_operation_id, user_id, revision_id)
  SELECT x, v_user_id, v_revision_id
  FROM unnest(ARRAY[v_episode.client_operation_id, v_episode.end_client_operation_id]) AS x
  WHERE x IS NOT NULL
  ON CONFLICT (client_operation_id) DO NOTHING;

  DELETE FROM public.bleeding_episodes WHERE id = p_episode_id;

  RETURN QUERY SELECT p_episode_id, v_revision_id;
END;
$function$;

-- 11. restore_episode ---------------------------------------------------------
-- Puts back an episode removed by remove_episode, with the same ids, if it
-- still fits: no overlap with her current episodes, and no second open
-- episode. The observations retracted by later corrections of OTHER
-- revisions are not touched.
CREATE OR REPLACE FUNCTION public.restore_episode(
  p_client_operation_id uuid,
  p_episode_id uuid
)
RETURNS TABLE (episode_id uuid, revision_id uuid)
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

  v_until := coalesce(v_archived.end_date, public.bleeding_local_today(0) + 1);
  IF EXISTS (
    SELECT 1 FROM public.bleeding_episodes e
    WHERE e.user_id = v_user_id
      AND e.start_date <= v_until
      AND coalesce(e.end_date, 'infinity'::date) >= v_archived.start_date
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

-- 12. Grants ------------------------------------------------------------------
-- Internal helpers: nobody but the owner (and service_role) may call them.
REVOKE ALL ON FUNCTION public.bleeding_episode_snapshot(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bleeding_effective_observations(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bleeding_observation_chains(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bleeding_archive_observations(uuid, uuid[], uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bleeding_episode_mutation_begin(uuid, uuid, uuid, timestamptz, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bleeding_local_today(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bleeding_reject_tombstoned_operation() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.correct_episode_start(uuid, uuid, date, text, text, integer, timestamptz, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.correct_episode_end(uuid, uuid, date, text, integer, timestamptz, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reopen_episode(uuid, uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_episode(uuid, uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.restore_episode(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.correct_episode_start(uuid, uuid, date, text, text, integer, timestamptz, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.correct_episode_end(uuid, uuid, date, text, integer, timestamptz, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reopen_episode(uuid, uuid, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.remove_episode(uuid, uuid, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.restore_episode(uuid, uuid) TO authenticated, service_role;
