-- Regression for
-- supabase/migrations/20261021110000_tracking_rls_initplan_and_fk_indexes.sql:
-- the tracking tables' RLS policies evaluate auth.uid() once per statement
-- (InitPlan) without changing who can read or write what, the policy
-- rewrite refuses to touch a policy whose text drifted, re-running the
-- migration is a no-op, and every foreign key on the tracking tables has a
-- covering index (account deletion and single cycle_entries deletes no
-- longer scan whole tables).
--
-- Run only on a scratch database built by run_sql_checks.sh. Exits non-zero
-- (ON_ERROR_STOP) on the first failed assertion; prints ALL PASSED otherwise.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;

\echo '--- 1. no tracking policy calls auth.uid() per row'
DO $$
DECLARE v text;
BEGIN
  SELECT string_agg(format('%s.%s', tablename, policyname), ', ') INTO v
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN ('bleeding_episodes', 'bleeding_observations',
      'cycle_baselines', 'madhhab_history', 'cycle_entries', 'symptoms_log',
      'prayer_log', 'adah_ledger', 'istihadah_episodes', 'nifas_records',
      'pregnancy_records', 'pregnancy_profile', 'cycle_logs', 'users')
    AND (regexp_replace(coalesce(qual, ''), '\( SELECT auth\.uid\(\) AS uid\)', '', 'g') LIKE '%auth.uid()%'
      OR regexp_replace(coalesce(with_check, ''), '\( SELECT auth\.uid\(\) AS uid\)', '', 'g') LIKE '%auth.uid()%');
  ASSERT v IS NULL, format('FAIL: bare auth.uid() left in %s', v);
END $$;

\echo '--- 2. rewritten policies keep command, roles, permissiveness and meaning'
DO $$
DECLARE v text;
BEGIN
  SELECT string_agg(format('%s.%s', tablename, policyname), ', ') INTO v
  FROM pg_policies
  WHERE schemaname = 'public'
    AND (qual LIKE '%SELECT auth.uid()%' OR with_check LIKE '%SELECT auth.uid()%')
    AND (roles <> '{public}' OR permissive <> 'PERMISSIVE');
  ASSERT v IS NULL, format('FAIL: roles/permissive changed on %s', v);

  ASSERT (SELECT cmd FROM pg_policies WHERE tablename = 'cycle_entries'
          AND policyname = 'cycle_entries_own') = 'ALL',
    'FAIL: cycle_entries_own is no longer FOR ALL';
  ASSERT (SELECT qual FROM pg_policies WHERE tablename = 'cycle_entries'
          AND policyname = 'cycle_entries_own') = 'can_access_user(user_id)',
    'FAIL: cycle_entries_own USING changed';
  ASSERT (SELECT with_check FROM pg_policies WHERE tablename = 'users'
          AND policyname = 'users_update_own') = '(( SELECT auth.uid() AS uid) = id)',
    'FAIL: users_update_own WITH CHECK is not the wrapped own-row check';
  ASSERT (SELECT cmd FROM pg_policies WHERE tablename = 'bleeding_episodes'
          AND policyname = 'bleeding_episodes_update_own') = 'UPDATE',
    'FAIL: bleeding_episodes_update_own command changed';
END $$;

INSERT INTO auth.users (id, email) VALUES
  ('a0000000-0000-4000-8000-00000000000a', 'a@example.invalid'),
  ('b0000000-0000-4000-8000-00000000000b', 'b@example.invalid');
INSERT INTO public.cycle_entries (user_id, date) VALUES
  ('a0000000-0000-4000-8000-00000000000a', current_date),
  ('b0000000-0000-4000-8000-00000000000b', current_date);
INSERT INTO public.cycle_logs (user_id, start_date) VALUES
  ('a0000000-0000-4000-8000-00000000000a', current_date),
  ('b0000000-0000-4000-8000-00000000000b', current_date);
INSERT INTO public.pregnancy_profile (user_id)
VALUES ('b0000000-0000-4000-8000-00000000000b');

CREATE FUNCTION pg_temp.expect_denied(p_uid text, p_sql text, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
    RETURN;
  END;
  EXECUTE 'RESET ROLE';
  RAISE EXCEPTION 'FAIL: % was allowed', p_label;
END $$;

CREATE FUNCTION pg_temp.plan(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; v text := '';
BEGIN
  FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) ' || p_sql LOOP v := v || r || E'\n'; END LOOP;
  RETURN v;
END $$;

\echo '--- 3. own rows only, as before'
BEGIN;
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-00000000000a', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM public.cycle_entries) = 1,
    'FAIL: cycle_entries visibility changed';
  ASSERT (SELECT count(*) FROM public.cycle_logs) = 1,
    'FAIL: cycle_logs visibility changed';
  ASSERT (SELECT count(*) FROM public.pregnancy_profile) = 0,
    'FAIL: another user''s pregnancy_profile is visible';
END $$;
-- Own writes still pass the wrapped WITH CHECK.
INSERT INTO public.cycle_entries (user_id, date)
VALUES ('a0000000-0000-4000-8000-00000000000a', current_date - 1);
INSERT INTO public.cycle_logs (user_id, start_date)
VALUES ('a0000000-0000-4000-8000-00000000000a', current_date - 30);
INSERT INTO public.pregnancy_profile (user_id)
VALUES ('a0000000-0000-4000-8000-00000000000a');
UPDATE public.users SET display_name = 'A'
WHERE id = 'a0000000-0000-4000-8000-00000000000a';
DO $$ BEGIN
  -- Another user's row is untouched by an UPDATE (USING filters it out).
  UPDATE public.cycle_logs SET notes = 'x'
  WHERE user_id = 'b0000000-0000-4000-8000-00000000000b';
  ASSERT NOT FOUND, 'FAIL: updated another user''s cycle_logs row';
END $$;
COMMIT;

BEGIN;
SELECT pg_temp.expect_denied('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.cycle_entries (user_id, date)
     VALUES ('b0000000-0000-4000-8000-00000000000b', current_date)$q$,
  'cycle_entries insert for another user');
SELECT pg_temp.expect_denied('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.cycle_logs (user_id, start_date)
     VALUES ('b0000000-0000-4000-8000-00000000000b', current_date)$q$,
  'cycle_logs insert for another user');
SELECT pg_temp.expect_denied('a0000000-0000-4000-8000-00000000000a',
  $q$UPDATE public.cycle_entries SET user_id = 'b0000000-0000-4000-8000-00000000000b'
     WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'$q$,
  'moving a cycle_entries row to another user');
SELECT pg_temp.expect_denied('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.pregnancy_profile (user_id)
     VALUES ('b0000000-0000-4000-8000-00000000000b')$q$,
  'pregnancy_profile insert for another user');
COMMIT;

\echo '--- 4. the rewrite is planned as an InitPlan'
BEGIN;
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-00000000000a', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  ASSERT pg_temp.plan('SELECT * FROM public.cycle_logs') LIKE '%InitPlan%',
    'FAIL: cycle_logs policy is not an InitPlan';
  ASSERT pg_temp.plan('SELECT * FROM public.pregnancy_profile') LIKE '%InitPlan%',
    'FAIL: pregnancy_profile policy is not an InitPlan';
END $$;
ROLLBACK;

\echo '--- 5. every tracking foreign key has a covering index'
DO $$
DECLARE v text;
BEGIN
  SELECT string_agg(format('%s(%s)', c.conrelid::regclass, a.attname), ', ') INTO v
  FROM pg_constraint c
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
  WHERE c.contype = 'f'
    AND array_length(c.conkey, 1) = 1
    AND c.conrelid::regclass::text IN ('bleeding_episodes',
      'bleeding_observations', 'cycle_baselines', 'cycle_entries',
      'symptoms_log', 'nifas_records', 'pregnancy_records',
      'istihadah_episodes', 'cycle_logs', 'adah_ledger', 'prayer_log',
      'pregnancy_profile', 'madhhab_history')
    AND NOT EXISTS (
      SELECT 1 FROM pg_index i
      WHERE i.indrelid = c.conrelid AND i.indkey[0] = c.conkey[1]
    );
  ASSERT v IS NULL, format('FAIL: unindexed foreign keys: %s', v);
END $$;

\echo '--- 6. the kept indexes serve the app''s and RPCs'' query shapes'
BEGIN;
SET LOCAL enable_seqscan = off;
SET LOCAL enable_bitmapscan = off;
DO $$ BEGIN
  ASSERT pg_temp.plan($q$SELECT * FROM public.bleeding_observations
    WHERE episode_id = 'c0000000-0000-4000-8000-00000000000c' ORDER BY observed_date$q$)
    LIKE '%bleeding_observations_episode_idx%',
    'FAIL: getObservationsForEpisode shape does not use bleeding_observations_episode_idx';
  ASSERT pg_temp.plan($q$SELECT * FROM public.bleeding_observations
    WHERE user_id = 'c0000000-0000-4000-8000-00000000000c' ORDER BY observed_date DESC$q$)
    LIKE '%bleeding_observations_user_date_idx%',
    'FAIL: per-user observation read does not use bleeding_observations_user_date_idx';
  ASSERT pg_temp.plan($q$SELECT * FROM public.bleeding_episodes
    WHERE user_id = 'c0000000-0000-4000-8000-00000000000c' ORDER BY start_date DESC$q$)
    LIKE '%bleeding_episodes_user_start_idx%',
    'FAIL: getEpisodesForUser shape does not use bleeding_episodes_user_start_idx';
  ASSERT pg_temp.plan($q$SELECT * FROM public.cycle_baselines
    WHERE user_id = 'c0000000-0000-4000-8000-00000000000c' ORDER BY reported_at DESC LIMIT 1$q$)
    LIKE '%cycle_baselines_user_reported_idx%',
    'FAIL: getBaseline shape does not use cycle_baselines_user_reported_idx';
  ASSERT pg_temp.plan($q$SELECT * FROM public.cycle_logs
    WHERE user_id = 'c0000000-0000-4000-8000-00000000000c' ORDER BY start_date DESC$q$)
    LIKE '%cycle_logs_user_start_idx%',
    'FAIL: CycleLogRepository shape does not use cycle_logs_user_start_idx';
  ASSERT pg_temp.plan($q$SELECT 1 FROM public.symptoms_log
    WHERE cycle_entry_id = 'c0000000-0000-4000-8000-00000000000c'$q$)
    LIKE '%symptoms_log_cycle_entry_id_idx%',
    'FAIL: cycle_entries delete check does not use symptoms_log_cycle_entry_id_idx';
END $$;
ROLLBACK;

\echo '--- 7. re-running the migration is a no-op'
CREATE TEMP TABLE before_policies AS
  SELECT tablename, policyname, cmd, roles, qual, with_check FROM pg_policies
  WHERE schemaname = 'public';
\ir ../../supabase/migrations/20261021110000_tracking_rls_initplan_and_fk_indexes.sql
DO $$ BEGIN
  ASSERT NOT EXISTS (
    (SELECT tablename, policyname, cmd, roles, qual, with_check FROM pg_policies
     WHERE schemaname = 'public'
     EXCEPT SELECT * FROM before_policies)
    UNION ALL
    (SELECT * FROM before_policies
     EXCEPT SELECT tablename, policyname, cmd, roles, qual, with_check
     FROM pg_policies WHERE schemaname = 'public')),
    'FAIL: re-running the migration changed a policy';
END $$;

\echo '--- 8. a drifted policy stops the migration instead of being rewritten'
ALTER POLICY cycle_entries_own ON public.cycle_entries
  WITH CHECK (auth.uid() = user_id AND date IS NOT NULL);
\set ON_ERROR_STOP 0
\ir ../../supabase/migrations/20261021110000_tracking_rls_initplan_and_fk_indexes.sql
\set ON_ERROR_STOP 1
SELECT :'LAST_ERROR_MESSAGE' LIKE 'tracking_rls_initplan: policy cycle_entries.cycle_entries_own is%'
  AS drift_refused \gset
\if :drift_refused
\else
  \echo 'FAIL: a drifted policy was not refused'
  SELECT 1/0;
\endif
DO $$ BEGIN
  ASSERT (SELECT with_check FROM pg_policies WHERE tablename = 'cycle_entries'
          AND policyname = 'cycle_entries_own')
         = '((auth.uid() = user_id) AND (date IS NOT NULL))',
    'FAIL: a drifted policy was rewritten';
END $$;

\echo ALL PASSED
