-- MENS-07: serialize concurrent corrections of the same observation so the
-- loser receives NW409 (a resolvable conflict), not a unique-index error.
-- Behaviour is otherwise identical to 20260919090000_correct_observation_rpc.sql.
CREATE OR REPLACE FUNCTION public.correct_observation(p_client_operation_id uuid, p_supersedes_id uuid, p_observed_date date, p_precision text, p_flow text, p_utc_offset_minutes integer, p_observed_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_timezone text DEFAULT NULL::text, p_symptoms jsonb DEFAULT NULL::jsonb, p_notes text DEFAULT NULL::text)
 RETURNS TABLE(observation_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_episode_id uuid;
      v_existing_id uuid;
      v_already_superseded_by uuid;
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
      --
      -- FOR UPDATE serializes two concurrent corrections of the SAME target:
      -- the second waits for the first to commit, then re-reads the chain
      -- below and gets the intended NW409 conflict. Without the lock both
      -- passed the check-then-insert and the loser hit the unique index
      -- (23505) — the fork was still prevented, but the app received a
      -- generic failure instead of the conflict it can resolve (found by
      -- the two-concurrent-writers acceptance test, MENS-07).
      SELECT episode_id INTO v_episode_id
      FROM public.bleeding_observations
      WHERE id = p_supersedes_id AND user_id = v_user_id
      FOR UPDATE;

      IF v_episode_id IS NULL THEN
        RAISE EXCEPTION
          'supersedes_id % does not exist or does not belong to the calling user',
          p_supersedes_id;
      END IF;

      -- D7 — concurrent correction conflict, checked explicitly rather
      -- than left to the unique index alone: if some other correction
      -- already superseded this exact target (a race between two
      -- devices, or a stale local view of the chain), `p_supersedes_id`
      -- is no longer the current tip — the caller's intended change must
      -- not silently fork or silently lose. A distinguishable ERRCODE
      -- lets the client recognize this specific case and show a real
      -- conflict-resolution UI rather than a generic failure.
      SELECT id INTO v_already_superseded_by
      FROM public.bleeding_observations
      WHERE supersedes_id = p_supersedes_id;

      IF v_already_superseded_by IS NOT NULL THEN
        RAISE EXCEPTION
          'observation % is no longer the current revision — it was '
          'already superseded by %', p_supersedes_id, v_already_superseded_by
          USING ERRCODE = 'NW409';
      END IF;

      -- Closure Blocker 5 — precision/timestamp consistency, mirroring
      -- every other write RPC's identical checks.
      IF p_precision = 'date_only' AND p_observed_time IS NOT NULL THEN
        RAISE EXCEPTION 'observed_time must be null when precision is date_only';
      END IF;
      IF p_precision IN ('exact_time', 'approximate_time')
        AND p_observed_time IS NULL
      THEN
        RAISE EXCEPTION 'observed_time is required when precision is %', p_precision;
      END IF;

      -- The rest (no fork/cycle, no future date, same-user/same-episode
      -- re-confirmed) is enforced by bleeding_observations_validate_insert
      -- and bleeding_observations_supersedes_once as independent layers
      -- underneath this explicit check — this function bypasses RLS
      -- (SECURITY DEFINER) but not the trigger, which still runs on
      -- every INSERT regardless of role.
      --
      -- Closure Blocker 4 — a correction's source is never a caller
      -- parameter at all: a correction is inherently an after-the-fact
      -- amendment to something already reported, even when filed the
      -- same day as the original observation, so it is never honestly
      -- "live observed" — always `user_reported_historical`, a fixed
      -- constant rather than something derived from today's date.
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
