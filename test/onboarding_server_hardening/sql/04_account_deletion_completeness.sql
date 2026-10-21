-- Onboarding/server hardening regression: delete_my_account()
-- removes every health row of the caller, including canonical bleeding data
-- with a correction chain (self-referencing supersedes_id, NO ACTION FK) and
-- madhhab_history, and leaves the other user's rows untouched. Also checks
-- statically that every public table with a per-user uuid column is covered
-- by an ON DELETE CASCADE FK (or the dedicated rate-limit deletion trigger)
-- — including knowledge_citations.user_id, which had no FK before
-- 20261021100000_onboarding_server_hardening.sql.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;

\echo '--- static: every per-user column cascades from the account'
DO $$
DECLARE r record; v_missing text := '';
BEGIN
  FOR r IN
    SELECT c.table_name, c.column_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
    WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE'
      AND c.data_type = 'uuid'
      AND c.column_name IN ('user_id', 'sender_id', 'participant_one',
                            'participant_two')
  LOOP
    IF r.table_name = 'ai_rate_limit_counters' THEN CONTINUE; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint k
      JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
      WHERE k.contype = 'f' AND k.conrelid = ('public.' || r.table_name)::regclass
        AND a.attname = r.column_name AND k.confdeltype = 'c'
        AND k.confrelid IN ('public.users'::regclass, 'auth.users'::regclass)
    ) THEN
      v_missing := v_missing || r.table_name || '.' || r.column_name || ' ';
    END IF;
  END LOOP;
  IF v_missing <> '' THEN
    RAISE EXCEPTION 'FAIL: not deleted with the account: %', v_missing;
  END IF;
END $$;

INSERT INTO auth.users (id) VALUES
  ('a1000000-0000-0000-0000-0000000000a1'),
  ('b1000000-0000-0000-0000-0000000000b1') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id) VALUES
  ('a1000000-0000-0000-0000-0000000000a1'),
  ('b1000000-0000-0000-0000-0000000000b1') ON CONFLICT DO NOTHING;

CREATE FUNCTION pg_temp.seed() RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_ep uuid; v_obs uuid;
BEGIN
  SELECT episode_id INTO v_ep FROM public.record_onboarding_menstrual_history(
    gen_random_uuid(), 180, current_date - 9, 'date_only', NULL, 'open',
    'confirmed', NULL, NULL, NULL, 5, 28);
  PERFORM public.record_bleeding_observation(gen_random_uuid(), v_ep,
    current_date - 8, 'date_only', 'heavy', 180);
  SELECT o.id INTO v_obs FROM public.bleeding_observations o
   WHERE o.episode_id = v_ep AND o.observed_date = current_date - 8;
  PERFORM public.correct_observation(gen_random_uuid(), v_obs,
    current_date - 8, 'date_only', 'medium', 180);
  PERFORM public.end_bleeding_episode(gen_random_uuid(), v_ep,
    current_date - 3, 'date_only', NULL, NULL, 'date_only', NULL, 180);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.seed() TO authenticated;

BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'a1000000-0000-0000-0000-0000000000a1';
SELECT pg_temp.seed();
INSERT INTO public.madhhab_history (user_id, previous_selection_state,
  new_selection_state, new_madhhab, source)
VALUES (auth.uid(), 'unset', 'selected', 'hanafi', 'onboarding');
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'b1000000-0000-0000-0000-0000000000b1';
SELECT pg_temp.seed();
COMMIT;

\echo '--- A deletes her account'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'a1000000-0000-0000-0000-0000000000a1';
SELECT public.delete_my_account();
COMMIT;

DO $$
DECLARE r record; n bigint;
BEGIN
  FOR r IN SELECT table_name FROM information_schema.columns
           WHERE table_schema = 'public' AND column_name = 'user_id'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE user_id = %L',
      r.table_name, 'a1000000-0000-0000-0000-0000000000a1') INTO n;
    IF n <> 0 THEN
      RAISE EXCEPTION 'FAIL: % rows of the deleted user remain in %', n, r.table_name;
    END IF;
  END LOOP;
  ASSERT (SELECT count(*) FROM public.bleeding_observations
          WHERE user_id = 'b1000000-0000-0000-0000-0000000000b1') >= 3,
    'FAIL: the other user''s data was affected';
END $$;

\echo 'ALL PASSED'
