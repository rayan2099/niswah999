-- Regression for
-- supabase/migrations/20261029120000_bleeding_observation_removal.sql
-- (period tracking case PT-055): one day's entry can be removed and put
-- back, never the start or an ended period's end, never by another
-- account, and a queued replay cannot bring a removed entry back.
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

CREATE TEMP TABLE pg_temp_tokens (ep uuid, token timestamptz, mid uuid);
GRANT ALL ON pg_temp_tokens TO authenticated;

CREATE FUNCTION pg_temp.reset() RETURNS void LANGUAGE sql AS $$
  TRUNCATE public.bleeding_episodes, public.bleeding_observations,
    public.bleeding_episode_revisions, public.bleeding_episodes_archive,
    public.bleeding_observations_archive, public.bleeding_operation_tombstones,
    public.cycle_entries CASCADE;
  DELETE FROM pg_temp_tokens;
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



\echo '--- 1. PT-055 one day removed: archived with its mirror, tombstoned, period kept'
-- Setup in its own transaction, so the token loaded here predates the removal.
DO $$
DECLARE ep uuid; mid uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('11000000-0000-4000-8000-000000000001', 6);
  mid := pg_temp.observe_a('11000000-0000-4000-8000-000000000002', ep, 4, 'heavy');
  PERFORM pg_temp.observe_a('11000000-0000-4000-8000-000000000003', ep, 3, 'light');
  INSERT INTO public.cycle_entries (id, user_id, date) VALUES (mid, 'a0000000-0000-4000-8000-00000000000a', current_date - 4);
  INSERT INTO pg_temp_tokens SELECT ep, updated_at, mid FROM public.bleeding_episodes WHERE id = ep;
END $$;
DO $$
DECLARE ep uuid := (SELECT ep FROM pg_temp_tokens); mid uuid := (SELECT mid FROM pg_temp_tokens); rev text;
BEGIN
  rev := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('11000000-0000-4000-8000-000000000004', %L)$q$, mid));
  ASSERT pg_temp.effective_dates(ep) = '6:medium,3:light',
    format('FAIL: effective observations %s', pg_temp.effective_dates(ep));
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_observations_archive WHERE id = mid AND archived_by_revision = rev::uuid),
    'FAIL: removed entry not archived';
  ASSERT NOT EXISTS (SELECT 1 FROM public.cycle_entries WHERE id = mid), 'FAIL: mirror kept';
  ASSERT (SELECT action FROM public.bleeding_episode_revisions WHERE id = rev::uuid) = 'remove_observation';
  ASSERT (SELECT lifecycle_status FROM public.bleeding_episodes WHERE id = ep) = 'open',
    'FAIL: removing a day changed the period';
  ASSERT pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('11000000-0000-4000-8000-000000000004', %L)$q$, mid)) = rev,
    'FAIL: replay did not return the original revision';
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT observation_id FROM public.record_bleeding_observation(
      '11000000-0000-4000-8000-000000000002', %L, current_date - 4, 'date_only', 'heavy', 0)$q$, ep),
    'NW410', NULL, 'replayed entry after removal');
END $$;
-- A period edit opened before the removal is now stale (separate statement).
DO $$
BEGIN
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '11000000-0000-4000-8000-000000000005', %L, current_date - 7, 'light', 'UTC', 0, %L)$q$,
    (SELECT ep FROM pg_temp_tokens), (SELECT token FROM pg_temp_tokens)),
    'NW409', NULL, 'edit with a token from before the removal');
END $$;

\echo '--- 2. PT-055/PT-057 Undo puts the same entry back; refused over a newer entry'
DO $$
DECLARE ep uuid; mid uuid; rev text; again uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('12000000-0000-4000-8000-000000000001', 6);
  mid := pg_temp.observe_a('12000000-0000-4000-8000-000000000002', ep, 4, 'heavy');
  rev := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('12000000-0000-4000-8000-000000000003', %L)$q$, mid));
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_observation('12000000-0000-4000-8000-000000000004', %L)$q$, rev));
  ASSERT pg_temp.effective_dates(ep) = '6:medium,4:heavy',
    format('FAIL: effective observations %s', pg_temp.effective_dates(ep));
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_observations WHERE id = mid), 'FAIL: id changed on restore';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_observations_archive), 'FAIL: archive not emptied';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_operation_tombstones), 'FAIL: tombstone kept';
  -- Remove again, record a new entry on that day, then Undo is refused.
  rev := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('12000000-0000-4000-8000-000000000005', %L)$q$, mid));
  again := pg_temp.observe_a('12000000-0000-4000-8000-000000000006', ep, 4, 'light');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_observation('12000000-0000-4000-8000-000000000007', %L)$q$, rev),
    'P0001', '%a newer entry exists%', 'restore over a newer entry');
  ASSERT pg_temp.effective_dates(ep) = '6:medium,4:light', 'FAIL: refused restore changed data';
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_observations_archive WHERE id = mid),
    'FAIL: refused restore lost the archived entry';
END $$;

\echo '--- 3. a corrected entry is removed with its whole correction history'
DO $$
DECLARE ep uuid; orig uuid; fixed uuid; rev text;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('13000000-0000-4000-8000-000000000001', 6);
  orig := pg_temp.observe_a('13000000-0000-4000-8000-000000000002', ep, 4, 'heavy');
  fixed := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT observation_id FROM public.correct_observation('13000000-0000-4000-8000-000000000003', %L,
       current_date - 4, 'date_only', 'light', 0)$q$, orig))::uuid;
  -- Removing by the old (superseded) id removes the current value too.
  rev := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('13000000-0000-4000-8000-000000000004', %L)$q$, orig));
  ASSERT pg_temp.effective_dates(ep) = '6:medium', format('FAIL: %s', pg_temp.effective_dates(ep));
  ASSERT (SELECT count(*) FROM public.bleeding_observations_archive WHERE id IN (orig, fixed)) = 2,
    'FAIL: correction chain not archived together';
  -- Undo brings back the chain in order: the correction still wins.
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_observation('13000000-0000-4000-8000-000000000005', %L)$q$, rev));
  ASSERT pg_temp.effective_dates(ep) = '6:medium,4:light', format('FAIL: %s', pg_temp.effective_dates(ep));
  ASSERT (SELECT supersedes_id FROM public.bleeding_observations WHERE id = fixed) = orig,
    'FAIL: restored chain lost its link';
END $$;

\echo '--- 4. the start entry and an ended period''s end entry are protected (NW423)'
DO $$
DECLARE ep uuid; start_obs uuid; closing uuid; pure uuid; ep2 uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('14000000-0000-4000-8000-000000000001', 9);
  start_obs := (SELECT id FROM public.bleeding_observations WHERE episode_id = ep);
  PERFORM pg_temp.end_a('14000000-0000-4000-8000-000000000002', ep, 5);
  closing := (SELECT id FROM public.bleeding_observations WHERE episode_id = ep AND flow = 'none');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('14000000-0000-4000-8000-000000000003', %L)$q$, start_obs),
    'NW423', '%start entry%', 'remove start entry');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('14000000-0000-4000-8000-000000000004', %L)$q$, closing),
    'NW423', '%end entry%', 'remove closing entry');
  ASSERT (SELECT count(*) FROM public.bleeding_episode_revisions) = 0, 'FAIL: refusal left a revision';
  -- An observed "no bleeding" day inside an open period is an ordinary entry.
  ep2 := pg_temp.start_a('14000000-0000-4000-8000-000000000005', 3);
  pure := pg_temp.observe_a('14000000-0000-4000-8000-000000000006', ep2, 2, 'none');
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('14000000-0000-4000-8000-000000000007', %L)$q$, pure));
  ASSERT pg_temp.effective_dates(ep2) = '3:medium', format('FAIL: %s', pg_temp.effective_dates(ep2));
END $$;

\echo '--- 5. a middle day of an ENDED period can be removed and put back'
DO $$
DECLARE ep uuid; mid uuid; rev text;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('15000000-0000-4000-8000-000000000001', 9);
  mid := pg_temp.observe_a('15000000-0000-4000-8000-000000000002', ep, 7, 'heavy');
  PERFORM pg_temp.end_a('15000000-0000-4000-8000-000000000003', ep, 5);
  rev := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('15000000-0000-4000-8000-000000000004', %L)$q$, mid));
  ASSERT pg_temp.effective_dates(ep) = '9:medium,5:none', format('FAIL: %s', pg_temp.effective_dates(ep));
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_observation('15000000-0000-4000-8000-000000000005', %L)$q$, rev));
  ASSERT pg_temp.effective_dates(ep) = '9:medium,7:heavy,5:none', format('FAIL: %s', pg_temp.effective_dates(ep));
  ASSERT (SELECT lifecycle_status FROM public.bleeding_episodes WHERE id = ep) = 'ended';
END $$;

\echo '--- 6. Undo after the whole period was removed is refused; data stays archived'
DO $$
DECLARE ep uuid; mid uuid; rev text;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('16000000-0000-4000-8000-000000000001', 6);
  mid := pg_temp.observe_a('16000000-0000-4000-8000-000000000002', ep, 4, 'heavy');
  rev := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('16000000-0000-4000-8000-000000000003', %L)$q$, mid));
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_episode('16000000-0000-4000-8000-000000000004', %L)$q$, ep));
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_observation('16000000-0000-4000-8000-000000000005', %L)$q$, rev),
    'P0001', '%does not exist%', 'restore entry of a removed period');
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_observations_archive WHERE id = mid),
    'FAIL: entry lost';
END $$;

\echo '--- 7. another account can never remove or restore her entries'
DO $$
DECLARE ep uuid; mid uuid; rev text;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('17000000-0000-4000-8000-000000000001', 6);
  mid := pg_temp.observe_a('17000000-0000-4000-8000-000000000002', ep, 4, 'heavy');
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.remove_observation('17000000-0000-4000-8000-000000000003', %L)$q$, mid),
    'P0001', '%does not exist or does not belong%', 'B removes A entry');
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_observations WHERE id = mid), 'FAIL: B removed it';
  rev := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_observation('17000000-0000-4000-8000-000000000004', %L)$q$, mid));
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.restore_observation('17000000-0000-4000-8000-000000000005', %L)$q$, rev),
    'P0001', '%does not exist or does not belong%', 'B restores A entry');
  -- B replaying A's operation id is not a replay for B.
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.remove_observation('17000000-0000-4000-8000-000000000004', %L)$q$, mid),
    'P0001', '%does not exist or does not belong%', 'B reuses A operation id');
  ASSERT NOT has_function_privilege('anon', 'public.remove_observation(uuid, uuid, timestamptz)', 'EXECUTE');
  ASSERT NOT has_function_privilege('anon', 'public.restore_observation(uuid, uuid)', 'EXECUTE');
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('remove_observation', 'restore_observation')
      AND NOT coalesce(p.proconfig, '{}') && ARRAY['search_path=public']),
    'FAIL: mutable search_path';
END $$;

\echo '--- 8. re-running the migration is a no-op'
\ir ../../supabase/migrations/20261029120000_bleeding_observation_removal.sql

\echo 'ALL PASSED'
