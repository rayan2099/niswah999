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
-- PR #4 final implementation wave, Hardening 5: now `SECURITY DEFINER`
-- with an explicit `SET search_path` (the schema migration revokes the
-- client-facing INSERT grant this function relies on). Ownership was
-- already self-contained — the target lookup below is filtered by
-- `user_id = v_user_id` (never RLS visibility), so bypassing RLS changes
-- nothing about its safety. `EXECUTE` is revoked from `PUBLIC` and
-- re-granted only to `authenticated`.
--
-- Commit D7 — concurrent correction conflict: two devices can each start
-- from the same v1 and both attempt to supersede it while offline from
-- each other. `bleeding_observations_supersedes_once` already prevents
-- both from landing (a fork), but the loser must see a typed,
-- recognizable conflict — not a raw unique-violation, and never a
-- silent last-write-wins. Checked explicitly (not left to the unique
-- index alone) so the failure mode is a clean, documented `RAISE
-- EXCEPTION ... USING ERRCODE = 'NW409'` a client can pattern-match on
-- via `PostgrestException.code`, rather than parsing a Postgres
-- constraint-violation message string.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_observations'
  ) THEN

    -- Closure Blocker 4: drops the old 11-parameter overload (p_source,
    -- caller-trusted) before creating the new one below — see
    -- start_bleeding_episode's identical note.
    DROP FUNCTION IF EXISTS public.correct_observation(
      uuid, uuid, date, text, text, text, integer, timestamptz, text,
      jsonb, text
    );

    CREATE OR REPLACE FUNCTION public.correct_observation(
      p_client_operation_id uuid,
      p_supersedes_id uuid,
      p_observed_date date,
      p_precision text,
      p_flow text,
      p_utc_offset_minutes integer,
      p_observed_time timestamptz DEFAULT NULL,
      p_timezone text DEFAULT NULL,
      p_symptoms jsonb DEFAULT NULL,
      p_notes text DEFAULT NULL
    )
    RETURNS TABLE (observation_id uuid)
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
      SELECT episode_id INTO v_episode_id
      FROM public.bleeding_observations
      WHERE id = p_supersedes_id AND user_id = v_user_id;

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

    REVOKE ALL ON FUNCTION public.correct_observation(
      uuid, uuid, date, text, text, integer, timestamptz, text, jsonb, text
    ) FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION public.correct_observation(
      uuid, uuid, date, text, text, integer, timestamptz, text, jsonb, text
    ) TO authenticated;

    -- Commit D5 — effective-observation resolver: given ANY observation
    -- id in a revision chain (the original root or a later correction),
    -- returns the id of the chain's current tip (the row nothing else
    -- supersedes) — "the effective value" the UI/Fiqh layer must read,
    -- while the full chain itself remains available via a plain SELECT
    -- ordered by the chain (see getObservationsForEpisode /
    -- get_revision_history). STABLE, not VOLATILE: pure function of
    -- already-committed data, safe to call repeatedly/inline in a query.
    -- SECURITY DEFINER for the same reason as the RPCs above (SELECT is
    -- still granted to `authenticated`, but a plain client-side
    -- recursive CTE across `bleeding_observations` would otherwise stay
    -- correctly RLS-scoped to the caller's own rows anyway — this
    -- exists as a single shared, tested definition of "current tip"
    -- rather than duplicating the recursive walk in every caller, not
    -- to bypass any check).
    CREATE OR REPLACE FUNCTION public.effective_observation_id(p_observation_id uuid)
    RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $tip$
      WITH RECURSIVE chain AS (
        SELECT id, supersedes_id, 0 AS depth
        FROM public.bleeding_observations
        WHERE id = p_observation_id
        UNION ALL
        SELECT bo.id, bo.supersedes_id, c.depth + 1
        FROM public.bleeding_observations bo
        JOIN chain c ON bo.supersedes_id = c.id
      )
      SELECT id FROM chain ORDER BY depth DESC LIMIT 1;
    $tip$;

    REVOKE ALL ON FUNCTION public.effective_observation_id(uuid) FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION public.effective_observation_id(uuid) TO authenticated;

  END IF;
END $$;
