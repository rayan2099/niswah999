-- Regression for
-- supabase/migrations/20261029100000_bleeding_episode_corrections.sql
-- (period tracking cases PT-027, PT-051..PT-057, PT-060, PT-145, PT-148,
-- PT-156): a woman can move the start or end of a period, undo an end she
-- did not mean and remove a period and put it back, without losing history,
-- without overlapping periods, without another account reaching her data,
-- and without a delayed operation undoing what she did.
--
-- Run only on a scratch database built by run_sql_checks.sh. Exits non-zero
-- (ON_ERROR_STOP) on the first failed assertion; prints ALL PASSED otherwise.
-- Dates are relative to current_date (UTC offset 0) so the future-date guard
-- never interferes. Synthetic users only.
\set ON_ERROR_STOP 1
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


\echo '--- 1. PT-051 start moved earlier: new start observation, days between stay unrecorded'
DO $$
DECLARE ep uuid; rev text;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('10000000-0000-4000-8000-000000000001', 5);
  PERFORM pg_temp.end_a('10000000-0000-4000-8000-000000000002', ep, 1);
  rev := pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '10000000-0000-4000-8000-000000000003', %L, current_date - 8, 'light', 'UTC', 0)$q$, ep));
  ASSERT (SELECT start_date FROM public.bleeding_episodes WHERE id = ep) = current_date - 8,
    'FAIL: start_date not moved';
  ASSERT pg_temp.effective_dates(ep) = '8:light,5:medium,1:none',
    format('FAIL: effective observations %s', pg_temp.effective_dates(ep));
  ASSERT (SELECT action FROM public.bleeding_episode_revisions WHERE id = rev::uuid) = 'correct_start';
  ASSERT (SELECT (before_state->>'start_date')::date FROM public.bleeding_episode_revisions
          WHERE id = rev::uuid) = current_date - 5, 'FAIL: before snapshot lost';
  ASSERT (SELECT (after_state->>'start_date')::date FROM public.bleeding_episode_revisions
          WHERE id = rev::uuid) = current_date - 8, 'FAIL: after snapshot wrong';
  -- Idempotent: same operation again returns the same revision, no change.
  ASSERT pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '10000000-0000-4000-8000-000000000003', %L, current_date - 9, 'light', 'UTC', 0)$q$, ep)) = rev,
    'FAIL: replay did not return the original revision';
  ASSERT (SELECT start_date FROM public.bleeding_episodes WHERE id = ep) = current_date - 8,
    'FAIL: replay changed the start';
  ASSERT (SELECT count(*) FROM public.bleeding_episode_revisions) = 1, 'FAIL: replay duplicated';
END $$;

\echo '--- 2. PT-051 start moved later: conflicting entries need confirmation, then are archived'
DO $$
DECLARE ep uuid; first_obs uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('20000000-0000-4000-8000-000000000001', 6);
  first_obs := (SELECT id FROM public.bleeding_observations WHERE episode_id = ep);
  INSERT INTO public.cycle_entries (id, user_id, date) VALUES
    (first_obs, 'a0000000-0000-4000-8000-00000000000a', current_date - 6);
  PERFORM pg_temp.observe_a('20000000-0000-4000-8000-000000000002', ep, 3, 'heavy');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '20000000-0000-4000-8000-000000000003', %L, current_date - 3, 'light', 'UTC', 0)$q$, ep),
    'NW422', '1 entries are recorded before%', 'later start without confirmation');
  ASSERT (SELECT start_date FROM public.bleeding_episodes WHERE id = ep) = current_date - 6,
    'FAIL: rejected change still moved the start';
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '20000000-0000-4000-8000-000000000004', %L, current_date - 3, 'light', 'UTC', 0,
      NULL, true)$q$, ep));
  ASSERT (SELECT start_date FROM public.bleeding_episodes WHERE id = ep) = current_date - 3;
  -- The heavy entry already on the new start date is kept as the start; no
  -- extra observation is invented.
  ASSERT pg_temp.effective_dates(ep) = '3:heavy',
    format('FAIL: effective observations %s', pg_temp.effective_dates(ep));
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_observations_archive WHERE id = first_obs),
    'FAIL: retracted observation not archived';
  ASSERT NOT EXISTS (SELECT 1 FROM public.cycle_entries WHERE id = first_obs),
    'FAIL: mirror of the retracted observation still in cycle_entries';
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_operation_tombstones
                 WHERE client_operation_id = '20000000-0000-4000-8000-000000000001'),
    'FAIL: retracted start operation not tombstoned';
  -- PT-145-style resurrection: the original start, replayed late, is refused.
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_episode('20000000-0000-4000-8000-000000000005', %L)$q$, ep));
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT episode_id FROM public.start_bleeding_episode('20000000-0000-4000-8000-000000000001',
       current_date - 6, 'date_only', NULL, 'medium', NULL, 'date_only', 'UTC', 0)$q$,
    'NW410', NULL, 'replayed start after removal');
END $$;

\echo '--- 3. PT-054 corrections never overlap another period'
DO $$
DECLARE e1 uuid; e2 uuid;
BEGIN
  PERFORM pg_temp.reset();
  e1 := pg_temp.start_a('30000000-0000-4000-8000-000000000001', 40);
  PERFORM pg_temp.end_a('30000000-0000-4000-8000-000000000002', e1, 35);
  e2 := pg_temp.start_a('30000000-0000-4000-8000-000000000003', 10);
  PERFORM pg_temp.end_a('30000000-0000-4000-8000-000000000004', e2, 5);
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '30000000-0000-4000-8000-000000000005', %L, current_date - 35, 'light', 'UTC', 0)$q$, e2),
    'P0001', '%overlaps an episode that ended%', 'start onto previous end');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '30000000-0000-4000-8000-000000000006', %L, current_date - 45, 'light', 'UTC', 0)$q$, e2),
    'P0001', '%overlaps%', 'start over a whole earlier episode');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '30000000-0000-4000-8000-000000000007', %L, current_date - 10, 'UTC', 0)$q$, e1),
    'P0001', '%overlaps the next episode%', 'end onto next start');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '30000000-0000-4000-8000-000000000008', %L, current_date + 1, 'light', 'UTC', 0)$q$, e2),
    'P0001', '%future%', 'future start');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '30000000-0000-4000-8000-000000000009', %L, current_date - 12, 'UTC', 0)$q$, e2),
    'P0001', '%precedes episode start%', 'end before start');
  ASSERT (SELECT count(*) FROM public.bleeding_episode_revisions) = 0,
    'FAIL: a rejected correction left a revision';
END $$;

\echo '--- 4. PT-052 end moved: closing observation corrected, history kept'
DO $$
DECLARE ep uuid; closing uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('40000000-0000-4000-8000-000000000001', 9);
  PERFORM pg_temp.observe_a('40000000-0000-4000-8000-000000000002', ep, 6, 'light');
  PERFORM pg_temp.end_a('40000000-0000-4000-8000-000000000003', ep, 4);
  closing := (SELECT id FROM public.bleeding_observations WHERE episode_id = ep AND flow = 'none');
  INSERT INTO public.cycle_entries (id, user_id, date) VALUES
    (closing, 'a0000000-0000-4000-8000-00000000000a', current_date - 4);
  -- Later end: the old closing "none" is superseded, not deleted.
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '40000000-0000-4000-8000-000000000004', %L, current_date - 2, 'UTC', 0)$q$, ep));
  ASSERT (SELECT end_date FROM public.bleeding_episodes WHERE id = ep) = current_date - 2;
  ASSERT pg_temp.effective_dates(ep) = '9:medium,6:light,2:none',
    format('FAIL: effective observations %s', pg_temp.effective_dates(ep));
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_observations WHERE id = closing),
    'FAIL: original closing observation was deleted instead of superseded';
  ASSERT NOT EXISTS (SELECT 1 FROM public.cycle_entries WHERE id = closing),
    'FAIL: stale closing mirror left in cycle_entries';
  -- Earlier end past recorded bleeding: needs confirmation.
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '40000000-0000-4000-8000-000000000005', %L, current_date - 7, 'UTC', 0)$q$, ep),
    'NW422', '1 entries are recorded after%', 'earlier end over recorded bleeding');
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '40000000-0000-4000-8000-000000000006', %L, current_date - 7, 'UTC', 0, NULL, true)$q$, ep));
  ASSERT pg_temp.effective_dates(ep) = '9:medium,7:none',
    format('FAIL: effective observations %s', pg_temp.effective_dates(ep));
  ASSERT (SELECT count(*) FROM public.bleeding_episode_revisions WHERE episode_id = ep) = 2;
END $$;

\echo '--- 5. PT-027 undo an accidental end; a replayed end cannot end it again'
DO $$
DECLARE ep uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('50000000-0000-4000-8000-000000000001', 3);
  PERFORM pg_temp.end_a('50000000-0000-4000-8000-000000000002', ep, 0);
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.reopen_episode('50000000-0000-4000-8000-000000000003', %L)$q$, ep));
  ASSERT (SELECT lifecycle_status || '/' || continuation_certainty || '/' || coalesce(end_date::text, '-')
          FROM public.bleeding_episodes WHERE id = ep) = 'open/confirmed/-',
    'FAIL: episode not reopened';
  ASSERT pg_temp.effective_dates(ep) = '3:medium', 'FAIL: closing observation still live';
  ASSERT (SELECT count(*) FROM public.bleeding_observations_archive) = 1,
    'FAIL: closing observation not archived';
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT closing_observation_id FROM public.end_bleeding_episode(
      '50000000-0000-4000-8000-000000000002', %L, current_date, 'date_only', NULL, NULL,
      'date_only', 'UTC', 0)$q$, ep),
    'NW410', NULL, 'replayed end after reopen');
  ASSERT (SELECT lifecycle_status FROM public.bleeding_episodes WHERE id = ep) = 'open',
    'FAIL: replayed end re-ended the episode';
  -- She can still end it for real, with a new operation.
  PERFORM pg_temp.end_a('50000000-0000-4000-8000-000000000004', ep, 1);
  ASSERT (SELECT lifecycle_status FROM public.bleeding_episodes WHERE id = ep) = 'ended';
  -- Only the latest episode may be reopened, and never beside an open one.
  PERFORM pg_temp.start_a('50000000-0000-4000-8000-000000000005', 0);
END $$;
DO $$
DECLARE older uuid;
BEGIN
  older := (SELECT id FROM public.bleeding_episodes WHERE lifecycle_status = 'ended');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.reopen_episode('50000000-0000-4000-8000-000000000006', %L)$q$, older),
    'P0001', '%another episode is open%', 'reopen beside an open episode');
END $$;

\echo '--- 6. PT-056/PT-057 remove a period, then put it back with the same ids'
DO $$
DECLARE ep uuid; ids_before text; ids_after text;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('60000000-0000-4000-8000-000000000001', 12);
  PERFORM pg_temp.observe_a('60000000-0000-4000-8000-000000000002', ep, 10, 'heavy');
  PERFORM pg_temp.end_a('60000000-0000-4000-8000-000000000003', ep, 8);
  INSERT INTO public.cycle_entries (id, user_id, date)
  SELECT o.id, o.user_id, o.observed_date FROM public.bleeding_observations o;
  ids_before := (SELECT string_agg(id::text, ',' ORDER BY id) FROM public.bleeding_observations);
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_episode('60000000-0000-4000-8000-000000000004', %L)$q$, ep));
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_episodes), 'FAIL: episode still live';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_observations), 'FAIL: observations still live';
  ASSERT NOT EXISTS (SELECT 1 FROM public.cycle_entries), 'FAIL: mirrors still in cycle_entries';
  ASSERT (SELECT count(*) FROM public.bleeding_observations_archive) = 3;
  -- Her own archive is readable to her (for "Undo"), not to B.
  ASSERT pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', 'SELECT count(*) FROM public.bleeding_episodes_archive') = '1';
  ASSERT pg_temp.as_user('b0000000-0000-4000-8000-00000000000b', 'SELECT count(*) FROM public.bleeding_episodes_archive') = '0',
    'FAIL: another account can see her removed period';
  ASSERT pg_temp.as_user('b0000000-0000-4000-8000-00000000000b', 'SELECT count(*) FROM public.bleeding_episode_revisions') = '0',
    'FAIL: another account can see her revision log';
  -- A queued daily entry for the removed period cannot bring it back.
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT observation_id FROM public.record_bleeding_observation(
      '60000000-0000-4000-8000-000000000002', %L, current_date - 10, 'date_only', 'heavy', 0)$q$, ep),
    'P0001', '%does not exist%', 'replayed observation after removal');
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_observations), 'FAIL: replay recreated data';
  -- Restore.
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_episode('60000000-0000-4000-8000-000000000005', %L)$q$, ep));
  ids_after := (SELECT string_agg(id::text, ',' ORDER BY id) FROM public.bleeding_observations);
  ASSERT ids_after = ids_before, 'FAIL: restored observations have different ids';
  ASSERT (SELECT lifecycle_status || '/' || (current_date - end_date)
          FROM public.bleeding_episodes WHERE id = ep) = 'ended/8', 'FAIL: restored state differs';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_episodes_archive), 'FAIL: archive not emptied';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_operation_tombstones),
    'FAIL: tombstones of a restored period kept';
  -- Restoring twice (same op) is a no-op; a fresh op finds nothing to restore.
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_episode('60000000-0000-4000-8000-000000000005', %L)$q$, ep));
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_episode('60000000-0000-4000-8000-000000000006', %L)$q$, ep),
    'P0001', '%does not exist%', 'restore of a live episode');
  ASSERT (SELECT count(*) FROM public.bleeding_episodes) = 1, 'FAIL: restore duplicated';
END $$;

\echo '--- 7. a removed period cannot be restored over one recorded since'
DO $$
DECLARE ep uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('70000000-0000-4000-8000-000000000001', 12);
  PERFORM pg_temp.end_a('70000000-0000-4000-8000-000000000002', ep, 8);
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_episode('70000000-0000-4000-8000-000000000003', %L)$q$, ep));
  PERFORM pg_temp.start_a('70000000-0000-4000-8000-000000000004', 10);
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.restore_episode('70000000-0000-4000-8000-000000000005', %L)$q$, ep),
    'P0001', '%overlaps a period recorded since%', 'restore over a newer period');
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_episodes_archive WHERE id = ep),
    'FAIL: refused restore lost the archived period';
END $$;

\echo '--- 8. PT-060/PT-148 a stale edit from another device is refused'
-- Separate statements = separate transactions, so updated_at moves.
CREATE TEMP TABLE stale_edit (ep uuid, loaded_at timestamptz);
GRANT ALL ON stale_edit TO authenticated;
DO $$
DECLARE ep uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('80000000-0000-4000-8000-000000000001', 9);
  PERFORM pg_temp.end_a('80000000-0000-4000-8000-000000000002', ep, 4);
  INSERT INTO stale_edit SELECT id, updated_at FROM public.bleeding_episodes WHERE id = ep;
END $$;
-- Device 1 moves the end with the token it loaded.
DO $$
BEGIN
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '80000000-0000-4000-8000-000000000003', %L, current_date - 3, 'UTC', 0, %L)$q$,
    (SELECT ep FROM stale_edit), (SELECT loaded_at FROM stale_edit)));
END $$;
-- Device 2 still holds the same, now stale, token.
DO $$
BEGIN
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '80000000-0000-4000-8000-000000000004', %L, current_date - 2, 'UTC', 0, %L)$q$,
    (SELECT ep FROM stale_edit), (SELECT loaded_at FROM stale_edit)),
    'NW409', '%changed since it was loaded%', 'stale end correction');
  ASSERT (SELECT end_date FROM public.bleeding_episodes WHERE id = (SELECT ep FROM stale_edit))
    = current_date - 3, 'FAIL: stale edit overwrote the newer one';
END $$;

\echo '--- 9. another account can never correct, reopen, remove or restore her periods'
DO $$
DECLARE ep uuid; arch uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('90000000-0000-4000-8000-000000000001', 9);
  PERFORM pg_temp.end_a('90000000-0000-4000-8000-000000000002', ep, 4);
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.correct_episode_start(
      '90000000-0000-4000-8000-000000000003', %L, current_date - 10, 'light', 'UTC', 0)$q$, ep),
    'P0001', '%does not exist or does not belong%', 'B corrects A start');
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.correct_episode_end(
      '90000000-0000-4000-8000-000000000004', %L, current_date - 2, 'UTC', 0)$q$, ep),
    'P0001', '%does not exist or does not belong%', 'B corrects A end');
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.reopen_episode('90000000-0000-4000-8000-000000000005', %L)$q$, ep),
    'P0001', '%does not exist or does not belong%', 'B reopens A');
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.remove_episode('90000000-0000-4000-8000-000000000006', %L)$q$, ep),
    'P0001', '%does not exist or does not belong%', 'B removes A');
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_episode('90000000-0000-4000-8000-000000000007', %L)$q$, ep));
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.restore_episode('90000000-0000-4000-8000-000000000008', %L)$q$, ep),
    'P0001', '%does not exist or does not belong%', 'B restores A');
  -- Same operation id from another account is not treated as a replay.
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.restore_episode('90000000-0000-4000-8000-000000000007', %L)$q$, ep),
    'P0001', '%does not exist or does not belong%', 'B replays A operation id');
  -- No direct writes to the new tables.
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$INSERT INTO public.bleeding_operation_tombstones (client_operation_id, user_id, revision_id)
       VALUES (gen_random_uuid(), 'a0000000-0000-4000-8000-00000000000a', gen_random_uuid()) RETURNING 1$q$,
    '42501', NULL, 'direct tombstone insert');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    'DELETE FROM public.bleeding_episodes_archive RETURNING 1', '42501', NULL, 'direct archive delete');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    'DELETE FROM public.bleeding_episode_revisions RETURNING 1', '42501', NULL, 'direct revision delete');
  -- Internal helpers are not callable.
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT public.bleeding_archive_observations('a0000000-0000-4000-8000-00000000000a', '{}', gen_random_uuid())::text$q$,
    '42501', NULL, 'internal helper call');
  ASSERT NOT has_function_privilege('anon', 'public.remove_episode(uuid, uuid, timestamptz)', 'EXECUTE'),
    'FAIL: anon can call remove_episode';
  -- Every function the corrections migrations add has a pinned search_path
  -- (Supabase advisor lint 0011).
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('bleeding_reject_tombstoned_operation', 'bleeding_observations_validate_insert',
        'bleeding_episode_snapshot', 'bleeding_effective_observations', 'bleeding_observation_chains',
        'bleeding_archive_observations', 'bleeding_episode_mutation_begin', 'bleeding_local_today',
        'correct_episode_start', 'correct_episode_end', 'reopen_episode', 'remove_episode', 'restore_episode')
      AND NOT coalesce(p.proconfig, '{}') && ARRAY['search_path=public']
  ), 'FAIL: a corrections function has a mutable search_path';
END $$;

\echo '--- 10. PT-156 account deletion removes archive, revisions and tombstones too'
DO $$
DECLARE ep uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('a1000000-0000-4000-8000-000000000001', 9);
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.remove_episode('a1000000-0000-4000-8000-000000000002', %L)$q$, ep));
  DELETE FROM auth.users WHERE id = 'a0000000-0000-4000-8000-00000000000a';
  DELETE FROM public.users WHERE id = 'a0000000-0000-4000-8000-00000000000a';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_episodes_archive)
     AND NOT EXISTS (SELECT 1 FROM public.bleeding_observations_archive)
     AND NOT EXISTS (SELECT 1 FROM public.bleeding_episode_revisions)
     AND NOT EXISTS (SELECT 1 FROM public.bleeding_operation_tombstones),
    'FAIL: deleted account left tracking history behind';
  -- A write still queued from the deleted account cannot recreate data.
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT episode_id FROM public.start_bleeding_episode(gen_random_uuid(),
       current_date, 'date_only', NULL, 'medium', NULL, 'date_only', 'UTC', 0)$q$,
    '23503', NULL, 'write after account deletion');
END $$;

\echo '--- 11. re-running the migration is a no-op'
\ir ../../supabase/migrations/20261029100000_bleeding_episode_corrections.sql

\echo 'ALL PASSED'
