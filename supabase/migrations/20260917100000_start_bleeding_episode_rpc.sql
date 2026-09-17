-- START BLEEDING EPISODE — ATOMIC RPC
--
-- Menstrual Data Integrity charter, Commit B (2026-09-17). Starting to
-- track bleeding conceptually creates TWO rows together: an active
-- bleeding_episodes row and its first bleeding_observations row. Doing
-- these as two separate client-issued INSERTs risks exactly the failure
-- mode the charter forbids: a partial failure between them leaves an
-- episode with no observation, or (impossible given the FK, but worth
-- naming) an observation referencing an episode that doesn't exist.
--
-- A Postgres function's statements all run inside the same transaction
-- as the calling statement — no explicit BEGIN/COMMIT needed here for
-- that atomicity. A double-tap (two rapid, separate RPC calls) is made
-- safe not through a separate idempotency key, but because the FIRST
-- call's episode INSERT already satisfies
-- bleeding_episodes_one_active_per_user (Commit A) — the SECOND call's
-- episode INSERT then fails that same partial unique index, which rolls
-- back its entire transaction before the observation INSERT ever runs.
-- The Dart caller (BleedingEpisodeRepositoryImpl.startEpisode) treats
-- that specific unique-violation as "you already have an active episode"
-- rather than a generic failure.
--
-- Deliberately NOT `SECURITY DEFINER`: runs as the calling `authenticated`
-- role so both tables' ordinary RLS INSERT policies (Commit A) still
-- apply as a second, independent layer of defense — this function is a
-- convenience for atomicity, not a privilege escalation.
--
-- Guarded the same way as every other migration in this repo (see
-- 20260914120000_madhhab_authority_state.sql) — a safe no-op on a
-- migrations-before-baseline fresh bootstrap, a real DDL statement
-- everywhere else.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bleeding_episodes'
  ) THEN

    CREATE OR REPLACE FUNCTION public.start_bleeding_episode(
      p_start_date date,
      p_start_precision text,
      p_start_time timestamptz,
      p_flow text,
      p_observed_time timestamptz,
      p_precision text,
      p_timezone text,
      p_symptoms jsonb DEFAULT NULL,
      p_notes text DEFAULT NULL
    )
    RETURNS TABLE (episode_id uuid, observation_id uuid)
    LANGUAGE plpgsql
    AS $function$
    DECLARE
      v_user_id uuid := auth.uid();
      v_episode_id uuid;
      v_observation_id uuid;
    BEGIN
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'start_bleeding_episode requires an authenticated user';
      END IF;

      INSERT INTO public.bleeding_episodes (
        user_id, status, start_date, start_precision, start_time, start_source
      ) VALUES (
        v_user_id, 'active', p_start_date, p_start_precision, p_start_time, 'user_observed'
      ) RETURNING id INTO v_episode_id;

      INSERT INTO public.bleeding_observations (
        user_id, episode_id, observed_date, observed_time, precision, flow,
        source, timezone, symptoms, notes
      ) VALUES (
        v_user_id, v_episode_id, p_start_date, p_observed_time, p_precision,
        p_flow, 'user_observed', p_timezone, p_symptoms, p_notes
      ) RETURNING id INTO v_observation_id;

      RETURN QUERY SELECT v_episode_id, v_observation_id;
    END;
    $function$;

    GRANT EXECUTE ON FUNCTION public.start_bleeding_episode(
      date, text, timestamptz, text, timestamptz, text, text, jsonb, text
    ) TO authenticated;

  END IF;
END $$;
