-- START BLEEDING EPISODE — ATOMIC, IDEMPOTENT RPC
--
-- Menstrual Data Integrity charter, Commit B. Starting to track bleeding
-- conceptually creates TWO rows together: an open bleeding_episodes row
-- and its first bleeding_observations row. A Postgres function's
-- statements all run inside the same transaction as the calling
-- statement — no explicit BEGIN/COMMIT needed for that atomicity.
--
-- PR #4 hardening pass (2026-09-18) — Blocker 1: the original version
-- only relied on `bleeding_episodes_one_open_per_user`'s unique-violation
-- to reject a second call. That proves a second call was rejected, but
-- never proves *why* — a genuine retry of an already-successful request
-- (response lost, app killed mid-request) is indistinguishable from a
-- second, different, legitimately-conflicting start. True idempotency:
-- the client generates `p_client_operation_id` once per logical action;
-- calling this RPC again with that same id returns the exact same
-- `episode_id`/`observation_id` it returned the first time — no
-- duplicate, no error — while a *different* id still correctly conflicts
-- against a genuinely already-open episode.
--
-- Blocker 4 — `p_start_source`/`p_source` are now real parameters, not a
-- hardcoded 'user_observed': the caller (Dart) classifies "today" vs. a
-- backdated report before ever calling this RPC, since only the caller
-- knows which the user actually chose.
--
-- Blocker 10 — the canonical write boundary re-validates "not in the
-- future" itself, in the reporter's own local date (derived from
-- `p_utc_offset_minutes`, never a named zone — see Blocker 7's rationale
-- in the schema migration) rather than trusting a client-side date-picker
-- bound, which a malformed or stale client could bypass entirely by
-- calling this RPC directly.
--
-- PR #4 final implementation wave, Hardening 5: now `SECURITY DEFINER`
-- with an explicit `SET search_path` — the schema migration revokes
-- every client-facing INSERT/UPDATE/DELETE grant on both tables this
-- function writes to, so an ordinary `authenticated`-role INSERT would
-- otherwise fail even from inside this function. RLS is bypassed once
-- SECURITY DEFINER (the function owner has BYPASSRLS), so it is no
-- longer a safety net here — every write below already used `v_user_id
-- := auth.uid()` exclusively (never a caller-supplied user id) and only
-- ever queries/inserts rows scoped to that same id, so ownership was
-- already self-contained and did not actually depend on RLS to be safe.
-- `EXECUTE` is revoked from `PUBLIC` (Postgres's default grant on
-- function creation) and re-granted only to `authenticated`.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_episodes'
  ) THEN

    -- Closure Blocker 4: drops the old 13-parameter overload
    -- (p_start_source/p_source, both caller-trusted) before creating the
    -- new 11-parameter one below — otherwise Postgres would keep both
    -- signatures simultaneously (it overloads by parameter list, not by
    -- name alone), leaving the old, unsafe entry point still callable.
    DROP FUNCTION IF EXISTS public.start_bleeding_episode(
      uuid, date, text, timestamptz, text, text, timestamptz, text, text,
      text, integer, jsonb, text
    );

    CREATE OR REPLACE FUNCTION public.start_bleeding_episode(
      p_client_operation_id uuid,
      p_start_date date,
      p_start_precision text,
      p_start_time timestamptz,
      p_flow text,
      p_observed_time timestamptz,
      p_precision text,
      p_timezone text,
      p_utc_offset_minutes integer,
      p_symptoms jsonb DEFAULT NULL,
      p_notes text DEFAULT NULL
    )
    RETURNS TABLE (episode_id uuid, observation_id uuid)
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

      -- Canonical write-boundary future-date rejection (Blocker 10) —
      -- offset-based, never dependent on `p_timezone` being a valid,
      -- recognized zone name (an abbreviation like "AST" would make
      -- `AT TIME ZONE` itself error, not gracefully degrade).
      v_local_today := ((now() AT TIME ZONE 'UTC')
        + make_interval(mins => p_utc_offset_minutes))::date;
      IF p_start_date > v_local_today THEN
        RAISE EXCEPTION
          'start_date cannot be in the future (got %, local today is %)',
          p_start_date, v_local_today;
      END IF;

      -- Closure Blocker 5 — precision/timestamp consistency, enforced
      -- here too (not only by the table's own CHECK constraint) so the
      -- failure is attributable to this specific call with a clear
      -- message, not a generic constraint-violation.
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

      -- Closure Blocker 4 — provenance is derived here, never trusted
      -- from the caller: reporting today's own local date is
      -- user_observed; any other (necessarily past) date is
      -- user_reported_historical. `p_start_source`/`p_source` are no
      -- longer accepted as parameters at all (see the signature above)
      -- — there is nothing left to ignore, so there is nothing a
      -- malicious or malformed caller could ever override.
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

    REVOKE ALL ON FUNCTION public.start_bleeding_episode(
      uuid, date, text, timestamptz, text, timestamptz, text, text,
      integer, jsonb, text
    ) FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION public.start_bleeding_episode(
      uuid, date, text, timestamptz, text, timestamptz, text, text,
      integer, jsonb, text
    ) TO authenticated;

  END IF;
END $$;
