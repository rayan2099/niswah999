-- Logging/sync hardening — canonical RPC regression script.
--
-- Asserts the write-boundary rules added by
-- supabase/migrations/20261018090000_bleeding_write_boundary_validation.sql.
-- Run against a scratch Postgres (not a shared environment) after:
--   1. a stub bootstrap: roles authenticated/anon/service_role; schema auth
--      with auth.uid() reading the GUC `test.uid`; public.users(id uuid pk)
--      holding 'aaaaaaaa-0000-0000-0000-000000000001'; public.can_access_user
--      and public.set_updated_at;
--   2. supabase/migrations 20260917090000 .. 20261018090000 in order.
-- `psql -v ON_ERROR_STOP=1 -f canonical_rpc_regression.sql` exits non-zero
-- on the first failed assertion and prints "ALL PASSED" otherwise. Dates
-- are relative to current_date so the future-date guard never interferes.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;
\pset tuples_only on
\pset format unaligned
SET test.uid = 'aaaaaaaa-0000-0000-0000-000000000001';

CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_sql text, p_pattern text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> 'P0001' OR SQLERRM NOT LIKE p_pattern THEN
      RAISE EXCEPTION 'expected P0001 like "%", got % "%"', p_pattern, SQLSTATE, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'expected a rejection like "%" but the call succeeded', p_pattern;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.reset() RETURNS void LANGUAGE sql AS $$
  TRUNCATE public.bleeding_episodes, public.bleeding_observations,
    public.cycle_baselines CASCADE;
$$;

CREATE OR REPLACE FUNCTION pg_temp.ep(p_op text) RETURNS uuid LANGUAGE sql AS $$
  SELECT id FROM public.bleeding_episodes WHERE client_operation_id = p_op::uuid;
$$;

CREATE OR REPLACE FUNCTION pg_temp.obs(p_op text) RETURNS uuid LANGUAGE sql AS $$
  SELECT id FROM public.bleeding_observations WHERE client_operation_id = p_op::uuid;
$$;

\echo '--- 1. a new episode may not start inside one that already ended'
SELECT pg_temp.reset();
SELECT public.start_bleeding_episode('10000000-0000-0000-0000-000000000001', current_date - 20, 'date_only', NULL, 'heavy', NULL, 'date_only', NULL, 180);
SELECT public.end_bleeding_episode('10000000-0000-0000-0000-000000000002', pg_temp.ep('10000000-0000-0000-0000-000000000001'), current_date - 14, 'date_only', NULL, NULL, 'date_only', NULL, 180);
SELECT pg_temp.expect_error(
  $q$SELECT public.start_bleeding_episode('10000000-0000-0000-0000-000000000003', current_date - 17, 'date_only', NULL, 'medium', NULL, 'date_only', NULL, 180)$q$,
  '%overlaps an episode that already ended%');
SELECT pg_temp.expect_error(
  $q$SELECT public.start_bleeding_episode('10000000-0000-0000-0000-000000000004', current_date - 14, 'date_only', NULL, 'medium', NULL, 'date_only', NULL, 180)$q$,
  '%overlaps an episode that already ended%');
-- the day after the end is a legitimate new episode
SELECT public.start_bleeding_episode('10000000-0000-0000-0000-000000000005', current_date - 13, 'date_only', NULL, 'medium', NULL, 'date_only', NULL, 180);
-- an idempotent replay of an already-saved start still succeeds
SELECT public.start_bleeding_episode('10000000-0000-0000-0000-000000000005', current_date - 13, 'date_only', NULL, 'medium', NULL, 'date_only', NULL, 180);
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM public.bleeding_episodes) = 2, 'exactly two episodes';
END $$;

\echo '--- 2. an episode may not end before bleeding already recorded in it'
SELECT pg_temp.reset();
SELECT public.start_bleeding_episode('20000000-0000-0000-0000-000000000001', current_date - 8, 'date_only', NULL, 'medium', NULL, 'date_only', NULL, 180);
SELECT public.record_bleeding_observation('20000000-0000-0000-0000-000000000002', pg_temp.ep('20000000-0000-0000-0000-000000000001'), current_date - 6, 'date_only', 'heavy', 180);
SELECT public.record_bleeding_observation('20000000-0000-0000-0000-000000000003', pg_temp.ep('20000000-0000-0000-0000-000000000001'), current_date - 5, 'date_only', 'heavy', 180);
SELECT pg_temp.expect_error(
  $q$SELECT public.end_bleeding_episode('20000000-0000-0000-0000-000000000004', pg_temp.ep('20000000-0000-0000-0000-000000000001'), current_date - 7, 'date_only', NULL, NULL, 'date_only', NULL, 180)$q$,
  '%precedes bleeding already recorded%');
-- once the later report is corrected to no bleeding, only the earlier
-- heavy day still bounds the end
SELECT public.correct_observation('20000000-0000-0000-0000-000000000005', pg_temp.obs('20000000-0000-0000-0000-000000000003'), current_date - 5, 'date_only', 'none', 180);
SELECT pg_temp.expect_error(
  $q$SELECT public.end_bleeding_episode('20000000-0000-0000-0000-000000000006', pg_temp.ep('20000000-0000-0000-0000-000000000001'), current_date - 7, 'date_only', NULL, NULL, 'date_only', NULL, 180)$q$,
  '%precedes bleeding already recorded%');
SELECT public.end_bleeding_episode('20000000-0000-0000-0000-000000000007', pg_temp.ep('20000000-0000-0000-0000-000000000001'), current_date - 6, 'date_only', NULL, NULL, 'date_only', NULL, 180);
DO $$ BEGIN
  ASSERT (SELECT end_date FROM public.bleeding_episodes) = current_date - 6, 'ended on the last bleeding day';
END $$;

\echo '--- 3. a new observation may not precede its episode start'
SELECT pg_temp.reset();
SELECT public.start_bleeding_episode('30000000-0000-0000-0000-000000000001', current_date - 1, 'date_only', NULL, 'medium', NULL, 'date_only', NULL, 180);
SELECT pg_temp.expect_error(
  $q$SELECT public.record_bleeding_observation('30000000-0000-0000-0000-000000000002', pg_temp.ep('30000000-0000-0000-0000-000000000001'), current_date - 25, 'date_only', 'heavy', 180)$q$,
  '%precedes the episode start%');
SELECT public.record_bleeding_observation('30000000-0000-0000-0000-000000000003', pg_temp.ep('30000000-0000-0000-0000-000000000001'), current_date, 'date_only', 'heavy', 180);

\echo '--- 4. corrections cannot contradict the start/closing observations'
SELECT pg_temp.reset();
SELECT public.start_bleeding_episode('40000000-0000-0000-0000-000000000001', current_date - 8, 'date_only', NULL, 'medium', NULL, 'date_only', NULL, 180);
SELECT public.end_bleeding_episode('40000000-0000-0000-0000-000000000002', pg_temp.ep('40000000-0000-0000-0000-000000000001'), current_date - 4, 'date_only', NULL, NULL, 'date_only', NULL, 180);
SELECT pg_temp.expect_error(
  $q$SELECT public.correct_observation('40000000-0000-0000-0000-000000000003', pg_temp.obs('40000000-0000-0000-0000-000000000002'), current_date - 4, 'date_only', 'heavy', 180)$q$,
  '%closing observation of an ended episode cannot be corrected to bleeding%');
SELECT pg_temp.expect_error(
  $q$SELECT public.correct_observation('40000000-0000-0000-0000-000000000004', pg_temp.obs('40000000-0000-0000-0000-000000000001'), current_date - 8, 'date_only', 'none', 180)$q$,
  '%start observation of an episode cannot be corrected to no bleeding%');
SELECT pg_temp.expect_error(
  $q$SELECT public.correct_observation('40000000-0000-0000-0000-000000000005', pg_temp.obs('40000000-0000-0000-0000-000000000002'), current_date - 5, 'date_only', 'none', 180)$q$,
  '%closing observation of an episode cannot move to another date%');
-- allowed: closing -> uncertain, start -> heavy
SELECT public.correct_observation('40000000-0000-0000-0000-000000000006', pg_temp.obs('40000000-0000-0000-0000-000000000002'), current_date - 4, 'date_only', 'uncertain', 180);
SELECT public.correct_observation('40000000-0000-0000-0000-000000000007', pg_temp.obs('40000000-0000-0000-0000-000000000001'), current_date - 8, 'date_only', 'heavy', 180);
-- the rule follows the chain root: the closing fact's v2 still cannot become bleeding
SELECT pg_temp.expect_error(
  $q$SELECT public.correct_observation('40000000-0000-0000-0000-000000000008', pg_temp.obs('40000000-0000-0000-0000-000000000006'), current_date - 4, 'date_only', 'light', 180)$q$,
  '%closing observation of an ended episode cannot be corrected to bleeding%');

\echo '--- 4b. onboarding-reported history: its closing row has no operation id'
SELECT pg_temp.reset();
SELECT public.record_onboarding_menstrual_history('4b000000-0000-0000-0000-000000000001', 180, p_start_date => current_date - 30, p_start_precision => 'date_only', p_lifecycle_status => 'ended', p_end_date => current_date - 25, p_end_precision => 'date_only');
SELECT pg_temp.expect_error(
  $q$SELECT public.correct_observation('4b000000-0000-0000-0000-000000000002', (SELECT id FROM public.bleeding_observations WHERE client_operation_id IS NULL), current_date - 25, 'date_only', 'heavy', 180)$q$,
  '%closing observation of an ended episode cannot be corrected to bleeding%');
SELECT pg_temp.expect_error(
  $q$SELECT public.correct_observation('4b000000-0000-0000-0000-000000000003', pg_temp.obs('4b000000-0000-0000-0000-000000000001'), current_date - 30, 'date_only', 'none', 180)$q$,
  '%start observation of an episode cannot be corrected to no bleeding%');

\echo '--- 5. onboarding "ended on E" for the same open episode actually ends it (and is idempotent)'
SELECT pg_temp.reset();
SELECT public.start_bleeding_episode('50000000-0000-0000-0000-000000000001', current_date - 9, 'date_only', NULL, 'medium', NULL, 'date_only', NULL, 180);
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.record_onboarding_menstrual_history('50000000-0000-0000-0000-000000000002', 180, p_start_date => current_date - 9, p_start_precision => 'date_only', p_lifecycle_status => 'ended', p_end_date => current_date - 4, p_end_precision => 'date_only');
  ASSERT r.episode_id = pg_temp.ep('50000000-0000-0000-0000-000000000001'), 'reused the same episode';
  ASSERT NOT r.episode_conflict, 'no conflict';
  -- retry of the same operation: same episode, nothing duplicated
  SELECT * INTO r FROM public.record_onboarding_menstrual_history('50000000-0000-0000-0000-000000000002', 180, p_start_date => current_date - 9, p_start_precision => 'date_only', p_lifecycle_status => 'ended', p_end_date => current_date - 4, p_end_precision => 'date_only');
  ASSERT r.episode_id = pg_temp.ep('50000000-0000-0000-0000-000000000001'), 'replay returns the same episode';
  ASSERT (SELECT count(*) FROM public.bleeding_episodes) = 1, 'no second episode';
  ASSERT (SELECT lifecycle_status FROM public.bleeding_episodes) = 'ended', 'episode ended';
  ASSERT (SELECT end_date FROM public.bleeding_episodes) = current_date - 4, 'with her end date';
  ASSERT (SELECT count(*) FROM public.bleeding_observations
          WHERE flow = 'none' AND observed_date = current_date - 4) = 1,
    'exactly one closing observation';
END $$;

\echo '--- 6. after a conflict the app resubmits under a NEW operation id: her changed baseline is saved'
SELECT pg_temp.reset();
SELECT public.start_bleeding_episode('60000000-0000-0000-0000-000000000001', current_date - 3, 'date_only', NULL, 'medium', NULL, 'date_only', NULL, 180);
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.record_onboarding_menstrual_history('60000000-0000-0000-0000-00000000000a', 180, p_start_date => current_date - 6, p_start_precision => 'date_only', p_lifecycle_status => 'open', p_continuation_certainty => 'confirmed', p_usual_bleeding_duration_days => 5, p_usual_cycle_length_days => 28);
  ASSERT r.episode_conflict, 'different start date conflicts';
  SELECT * INTO r FROM public.record_onboarding_menstrual_history('60000000-0000-0000-0000-00000000000b', 180, p_usual_bleeding_duration_days => 7, p_usual_cycle_length_days => 30);
  ASSERT (SELECT usual_bleeding_duration_days FROM public.cycle_baselines
          WHERE client_operation_id = '60000000-0000-0000-0000-00000000000b') = 7,
    'the changed baseline is saved as a new estimate';
END $$;

\echo 'ALL PASSED'
