-- Regression for
-- supabase/migrations/20261029130000_bleeding_episode_end_unknown.sql
-- (period tracking case PT-002): "it has stopped, I'm not sure when" keeps
-- the known start as an ended period whose end is unknown, invents no end,
-- and every overlap, correction and restore rule still holds around it.
--
-- Run only on a scratch database built by run_sql_checks.sh. Synthetic
-- users only.

SET client_min_messages = warning;

INSERT INTO auth.users (id, email) VALUES
  ('a0000000-0000-4000-8000-00000000000a', 'a@example.invalid'),
  ('b0000000-0000-4000-8000-00000000000b', 'b@example.invalid');

-- Runs p_sql as authenticated user p_uid and returns the first column of
-- the first row as text (NULL when no row).
CREATE FUNCTION pg_temp.as_user(p_uid text, p_sql text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE p_sql INTO v;
  EXECUTE 'RESET ROLE';
  RETURN v;
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  RAISE;
END $$;

-- Runs p_sql as p_uid and requires it to fail with p_state (and, when
-- given, a message LIKE p_pattern).
CREATE FUNCTION pg_temp.expect_error(p_uid text, p_sql text, p_state text,
  p_pattern text, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM pg_temp.as_user(p_uid, p_sql);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> p_state OR (p_pattern IS NOT NULL AND SQLERRM NOT LIKE p_pattern) THEN
      RAISE EXCEPTION 'FAIL %: expected % like "%", got % "%"',
        p_label, p_state, p_pattern, SQLSTATE, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: expected an error but the call succeeded', p_label;
END $$;

CREATE FUNCTION pg_temp.reset() RETURNS void LANGUAGE sql AS $$
  TRUNCATE public.bleeding_episodes, public.bleeding_observations,
    public.bleeding_episode_revisions, public.bleeding_episodes_archive,
    public.bleeding_observations_archive, public.bleeding_operation_tombstones,
    public.cycle_entries CASCADE;
$$;

-- Starts an episode for A on today - p_days_ago with operation p_op.
CREATE FUNCTION pg_temp.start_a(p_op text, p_days_ago int) RETURNS uuid
LANGUAGE sql AS $$
  SELECT pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT episode_id FROM public.start_bleeding_episode(%L::uuid, %L::date,
       'date_only', NULL, 'medium', NULL, 'date_only', 'UTC', 0)$q$,
    p_op, current_date - p_days_ago))::uuid;
$$;

CREATE FUNCTION pg_temp.end_a(p_op text, p_ep uuid, p_days_ago int) RETURNS void
LANGUAGE sql AS $$
  SELECT pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT closing_observation_id FROM public.end_bleeding_episode(%L::uuid, %L::uuid,
       %L::date, 'date_only', NULL, NULL, 'date_only', 'UTC', 0)$q$,
    p_op, p_ep, current_date - p_days_ago));
$$;

CREATE FUNCTION pg_temp.observe_a(p_op text, p_ep uuid, p_days_ago int, p_flow text) RETURNS uuid
LANGUAGE sql AS $$
  SELECT pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT observation_id FROM public.record_bleeding_observation(%L::uuid, %L::uuid,
       %L::date, 'date_only', %L, 0)$q$,
    p_op, p_ep, current_date - p_days_ago, p_flow))::uuid;
$$;

CREATE FUNCTION pg_temp.effective_dates(p_ep uuid) RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(format('%s:%s', current_date - o.observed_date, o.flow), ','
           ORDER BY o.observed_date, o.flow)
  FROM public.bleeding_observations o
  WHERE o.episode_id = p_ep
    AND NOT EXISTS (SELECT 1 FROM public.bleeding_observations s WHERE s.supersedes_id = o.id);
$$;




-- Onboarding answer "stopped, not sure when" for A, started p_days_ago.
CREATE FUNCTION pg_temp.onboard_unknown_end(p_op text, p_days_ago int) RETURNS uuid
LANGUAGE sql AS $$
  SELECT pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT episode_id FROM public.record_onboarding_menstrual_history(
       %L::uuid, 0, %L::date, 'date_only', NULL, 'ended', NULL, NULL, 'unknown', NULL, NULL, NULL)$q$,
    p_op, current_date - p_days_ago))::uuid;
$$;

\echo '--- 1. PT-002 onboarding saves the known start; the end stays unknown, nothing invented'
DO $$
DECLARE ep uuid; e public.bleeding_episodes;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.onboard_unknown_end('21000000-0000-4000-8000-000000000001', 20);
  SELECT * INTO e FROM public.bleeding_episodes WHERE id = ep;
  ASSERT e.lifecycle_status = 'ended', 'FAIL: not ended';
  ASSERT e.continuation_certainty IS NULL, 'FAIL: continuation set';
  ASSERT e.start_date = current_date - 20, 'FAIL: start lost';
  ASSERT e.end_date IS NULL AND e.end_time IS NULL, 'FAIL: an end was invented';
  ASSERT e.end_precision = 'unknown', format('FAIL: end_precision %s', e.end_precision);
  ASSERT e.end_source = 'user_reported_historical', 'FAIL: end_source';
  ASSERT pg_temp.effective_dates(ep) = '20:uncertain',
    format('FAIL: observations %s (no closing entry may exist)', pg_temp.effective_dates(ep));
  -- Replay of the same operation: same episode, nothing added.
  ASSERT pg_temp.onboard_unknown_end('21000000-0000-4000-8000-000000000001', 20) = ep, 'FAIL: replay';
  -- The same answer under a new operation id reuses it.
  ASSERT pg_temp.onboard_unknown_end('21000000-0000-4000-8000-000000000002', 20) = ep, 'FAIL: duplicate';
  ASSERT (SELECT count(*) FROM public.bleeding_episodes WHERE user_id = 'a0000000-0000-4000-8000-00000000000a') = 1,
    'FAIL: duplicate episode';
END $$;

\echo '--- 2. contradictory end answers are refused'
DO $$
BEGIN
  PERFORM pg_temp.reset();
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT episode_id FROM public.record_onboarding_menstrual_history(
       '22000000-0000-4000-8000-000000000001', 0, current_date - 9, 'date_only', NULL,
       'ended', NULL, current_date - 4, 'unknown', NULL, NULL, NULL)$q$,
    'P0001', '%unknown end%', 'unknown end with an end date');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT episode_id FROM public.record_onboarding_menstrual_history(
       '22000000-0000-4000-8000-000000000002', 0, current_date - 9, 'date_only', NULL,
       'open', 'confirmed', NULL, 'unknown', NULL, NULL, NULL)$q$,
    'P0001', '%unknown end%', 'unknown end on an open episode');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT episode_id FROM public.record_onboarding_menstrual_history(
       '22000000-0000-4000-8000-000000000003', 0, current_date - 9, 'date_only', NULL,
       'ended', NULL, NULL, NULL, NULL, NULL, NULL)$q$,
    'P0001', '%needs an end date or end_precision unknown%', 'ended with no end at all');
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_episodes WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'),
    'FAIL: a refused answer saved something';
  -- The table itself refuses a half-described end.
  BEGIN
    INSERT INTO public.bleeding_episodes (user_id, lifecycle_status, start_date, start_precision,
      start_source, end_precision, end_source)
    VALUES ('a0000000-0000-4000-8000-00000000000a', 'open', current_date - 3, 'date_only',
      'user_reported_historical', 'unknown', 'user_reported_historical');
    RAISE EXCEPTION 'FAIL: open episode with an unknown end accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.bleeding_episodes (user_id, lifecycle_status, start_date, start_precision,
      start_source, end_date, end_precision, end_source)
    VALUES ('a0000000-0000-4000-8000-00000000000a', 'ended', current_date - 3, 'date_only',
      'user_reported_historical', current_date - 1, 'unknown', 'user_reported_historical');
    RAISE EXCEPTION 'FAIL: an end date marked unknown accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

\echo '--- 3. overlap rules treat an unknown end as its start day only'
DO $$
DECLARE ep uuid; later uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.onboard_unknown_end('23000000-0000-4000-8000-000000000001', 20);
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT episode_id FROM public.start_bleeding_episode('23000000-0000-4000-8000-000000000002',
       current_date - 20, 'date_only', NULL, 'medium', NULL, 'date_only', 'UTC', 0)$q$,
    'P0001', '%overlaps%', 'start on the unknown period''s start day');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT episode_id FROM public.record_onboarding_menstrual_history(
       '23000000-0000-4000-8000-000000000003', 0, current_date - 25, 'date_only', NULL,
       'ended', NULL, current_date - 18, 'date_only', NULL, NULL, NULL)$q$,
    'P0001', '%overlaps%', 'known period covering the unknown period''s start');
  later := pg_temp.start_a('23000000-0000-4000-8000-000000000004', 2);
  ASSERT (SELECT lifecycle_status FROM public.bleeding_episodes WHERE id = later) = 'open',
    'FAIL: a later period could not start';
  -- Moving the later period's start back onto the unknown one is refused.
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '23000000-0000-4000-8000-000000000005', %L, current_date - 20, 'light', 'UTC', 0)$q$, later),
    'P0001', '%overlaps%', 'later start moved onto the unknown period');
END $$;

\echo '--- 4. "Edit this period" sets the first real end'
DO $$
DECLARE ep uuid; rev text; e public.bleeding_episodes;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.onboard_unknown_end('24000000-0000-4000-8000-000000000001', 20);
  rev := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '24000000-0000-4000-8000-000000000002', %L, current_date - 14, 'UTC', 0)$q$, ep));
  SELECT * INTO e FROM public.bleeding_episodes WHERE id = ep;
  ASSERT e.end_date = current_date - 14 AND e.end_precision = 'date_only', 'FAIL: end not set';
  ASSERT pg_temp.effective_dates(ep) = '20:uncertain,14:none', format('FAIL: %s', pg_temp.effective_dates(ep));
  ASSERT (SELECT before_state->>'end_precision' FROM public.bleeding_episode_revisions WHERE id = rev::uuid) = 'unknown',
    'FAIL: history lost the unknown end';
END $$;

\echo '--- 5. removing and restoring periods next to an unknown end'
DO $$
DECLARE ep uuid; later uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.onboard_unknown_end('25000000-0000-4000-8000-000000000001', 30);
  later := pg_temp.start_a('25000000-0000-4000-8000-000000000002', 6);
  PERFORM pg_temp.end_a('25000000-0000-4000-8000-000000000003', later, 2);
  -- The unknown-end period removed and put back while a later one exists.
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_episode('25000000-0000-4000-8000-000000000004', %L)$q$, ep));
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_episode('25000000-0000-4000-8000-000000000005', %L)$q$, ep));
  ASSERT (SELECT end_precision FROM public.bleeding_episodes WHERE id = ep) = 'unknown', 'FAIL: restore changed the end';
  -- The later period removed and put back next to the unknown-end one.
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_episode('25000000-0000-4000-8000-000000000006', %L)$q$, later));
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_episode('25000000-0000-4000-8000-000000000007', %L)$q$, later));
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_episodes WHERE id = later), 'FAIL: later period not restored';
END $$;

\echo '--- 6. another account cannot see or change it; the functions keep a pinned search_path'
DO $$
DECLARE ep uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.onboard_unknown_end('26000000-0000-4000-8000-000000000001', 20);
  ASSERT pg_temp.as_user('b0000000-0000-4000-8000-00000000000b',
    format($q$SELECT count(*) FROM public.bleeding_episodes WHERE id = %L$q$, ep)) = '0',
    'FAIL: B can read A''s period';
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '26000000-0000-4000-8000-000000000002', %L, current_date - 14, 'UTC', 0)$q$, ep),
    'P0001', '%does not exist or does not belong%', 'B sets A''s end');
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('start_bleeding_episode', 'correct_episode_start', 'correct_episode_end',
                        'restore_episode', 'record_onboarding_menstrual_history')
      AND NOT coalesce(p.proconfig, '{}') && ARRAY['search_path=public']),
    'FAIL: mutable search_path';
END $$;

\echo '--- 7. re-running the migration is a no-op'
\ir ../../supabase/migrations/20261029130000_bleeding_episode_end_unknown.sql

\echo 'ALL PASSED'
