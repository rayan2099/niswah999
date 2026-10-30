-- Regression for
-- supabase/migrations/20261030090000_bleeding_episode_split_merge.sql
-- (period tracking cases PT-045, PT-046; journeys NJ-101..NJ-104, NJ-279):
-- a period can be split in two and two neighbouring periods merged, with
-- a preview first, nothing she recorded rewritten, unanswered days left
-- unanswered, stale tokens refused, undo, and no access across accounts.
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



CREATE FUNCTION pg_temp.ep_count() RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.bleeding_episodes
  WHERE user_id = 'a0000000-0000-4000-8000-00000000000a';
$$;

CREATE FUNCTION pg_temp.token(p_ep uuid) RETURNS text LANGUAGE sql AS $$
  SELECT updated_at::text FROM public.bleeding_episodes WHERE id = p_ep;
$$;

-- One long period for A: bleeding 20, 18 days ago, clean 15, bleeding 12
-- and 10 days ago, ended with its first clean day 8 days ago.
CREATE FUNCTION pg_temp.long_period() RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE ep uuid;
BEGIN
  ep := pg_temp.start_a('30000000-0000-4000-8000-000000000001', 20);
  PERFORM pg_temp.observe_a('30000000-0000-4000-8000-000000000002', ep, 18, 'medium');
  PERFORM pg_temp.observe_a('30000000-0000-4000-8000-000000000003', ep, 15, 'none');
  PERFORM pg_temp.observe_a('30000000-0000-4000-8000-000000000004', ep, 12, 'medium');
  PERFORM pg_temp.observe_a('30000000-0000-4000-8000-000000000005', ep, 10, 'light');
  PERFORM pg_temp.end_a('30000000-0000-4000-8000-000000000006', ep, 8);
  RETURN ep;
END $$;

CREATE FUNCTION pg_temp.split(p_op text, p_ep uuid, p_second int, p_first_end int,
  p_confirm boolean) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT second_episode_id FROM public.split_episode(%L::uuid, %L::uuid,
       %L::date, %L::date, 'UTC', 0, %L::timestamptz, %L)$q$,
    p_op, p_ep, current_date - p_second,
    CASE WHEN p_first_end IS NULL THEN NULL ELSE current_date - p_first_end END,
    pg_temp.token(p_ep), p_confirm));
$$;

\echo '--- 1. split: a preview writes nothing; confirming makes two periods from the same entries'
DO $$
DECLARE ep uuid; second uuid; before_ids text; f public.bleeding_episodes; s public.bleeding_episodes;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.long_period();
  SELECT string_agg(id::text, ',' ORDER BY id) INTO before_ids FROM public.bleeding_observations WHERE user_id = 'a0000000-0000-4000-8000-00000000000a';
  BEGIN
    PERFORM pg_temp.split('31000000-0000-4000-8000-000000000001', ep, 12, 15, false);
    RAISE EXCEPTION 'FAIL: preview did not stop';
  EXCEPTION WHEN SQLSTATE 'NW422' THEN
    NULL;
  END;
  ASSERT pg_temp.ep_count() = 1, 'FAIL: preview wrote a period';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_episode_revisions WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'), 'FAIL: preview wrote a revision';

  second := pg_temp.split('31000000-0000-4000-8000-000000000002', ep, 12, 15, true)::uuid;
  ASSERT pg_temp.ep_count() = 2, 'FAIL: not two periods';
  SELECT * INTO f FROM public.bleeding_episodes WHERE id = ep;
  SELECT * INTO s FROM public.bleeding_episodes WHERE id = second;
  ASSERT f.lifecycle_status = 'ended' AND f.end_date = current_date - 15 AND f.end_precision = 'date_only',
    format('FAIL: first end %s %s', f.end_date, f.end_precision);
  ASSERT f.start_date = current_date - 20, 'FAIL: first start moved';
  ASSERT s.start_date = current_date - 12 AND s.lifecycle_status = 'ended'
    AND s.end_date = current_date - 8, 'FAIL: second period shape';
  ASSERT pg_temp.effective_dates(ep) = '20:medium,18:medium,15:none',
    format('FAIL: first entries %s', pg_temp.effective_dates(ep));
  ASSERT pg_temp.effective_dates(second) = '12:medium,10:light,8:none',
    format('FAIL: second entries %s', pg_temp.effective_dates(second));
  -- The 15-day "no bleeding" she recorded is the first part's end: nothing
  -- was added, nothing rewritten, every id is the same.
  ASSERT (SELECT string_agg(id::text, ',' ORDER BY id) FROM public.bleeding_observations WHERE user_id = 'a0000000-0000-4000-8000-00000000000a') = before_ids,
    'FAIL: entries were added, removed or re-created';
  -- Days she did not answer (19, 17, 16, 14, 13, ...) stay unanswered.
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_observations
                     WHERE user_id = 'a0000000-0000-4000-8000-00000000000a' AND observed_date IN (current_date - 19, current_date - 14)),
    'FAIL: an unanswered day was filled';
  -- Replay returns the same split.
  ASSERT pg_temp.split('31000000-0000-4000-8000-000000000002', ep, 12, 15, true)::uuid = second,
    'FAIL: replay';
  ASSERT pg_temp.ep_count() = 2, 'FAIL: replay split again';
END $$;

\echo '--- 2. split refusals'
DO $$
DECLARE ep uuid;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.long_period();
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.split_episode('32000000-0000-4000-8000-000000000001', %L,
       current_date - 14, NULL, 'UTC', 0, NULL, true)$q$, ep),
    'P0001', '%no bleeding is recorded%', 'second start on an unrecorded day');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.split_episode('32000000-0000-4000-8000-000000000002', %L,
       current_date - 10, current_date - 13, 'UTC', 0, NULL, true)$q$, ep),
    'P0001', '%bleeding is recorded between%', 'first end before recorded bleeding');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.split_episode('32000000-0000-4000-8000-000000000003', %L,
       current_date - 20, NULL, 'UTC', 0, NULL, true)$q$, ep),
    'P0001', '%must start after%', 'second start on the first start');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.split_episode('32000000-0000-4000-8000-000000000004', %L,
       current_date - 8, NULL, 'UTC', 0, NULL, true)$q$, ep),
    'P0001', '%before this period ended%', 'second start on the end day');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.split_episode('32000000-0000-4000-8000-000000000005', %L,
       current_date - 12, current_date - 15, 'UTC', 0, '2001-01-01', true)$q$, ep),
    'NW409', NULL, 'stale token');
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.split_episode('32000000-0000-4000-8000-000000000006', %L,
       current_date - 12, current_date - 15, 'UTC', 0, NULL, true)$q$, ep),
    'P0001', '%does not belong%', 'another account');
  ASSERT pg_temp.ep_count() = 1, 'FAIL: a refused split changed something';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_episode_revisions WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'), 'FAIL: refused split left a revision';
END $$;

\echo '--- 3. split an open period with an unknown first end; and an end that needs its clean day added'
DO $$
DECLARE ep uuid; second uuid; f public.bleeding_episodes; s public.bleeding_episodes;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('33000000-0000-4000-8000-000000000001', 9);
  PERFORM pg_temp.observe_a('33000000-0000-4000-8000-000000000002', ep, 4, 'medium');
  second := pg_temp.split('33000000-0000-4000-8000-000000000003', ep, 4, NULL, true)::uuid;
  SELECT * INTO f FROM public.bleeding_episodes WHERE id = ep;
  SELECT * INTO s FROM public.bleeding_episodes WHERE id = second;
  ASSERT f.lifecycle_status = 'ended' AND f.end_date IS NULL AND f.end_precision = 'unknown',
    'FAIL: unknown end not kept unknown';
  ASSERT s.lifecycle_status = 'open' AND s.continuation_certainty = 'confirmed', 'FAIL: second not open';
  ASSERT pg_temp.effective_dates(ep) = '9:medium', format('FAIL: %s', pg_temp.effective_dates(ep));

  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('33000000-0000-4000-8000-000000000004', 9);
  PERFORM pg_temp.observe_a('33000000-0000-4000-8000-000000000005', ep, 4, 'medium');
  second := pg_temp.split('33000000-0000-4000-8000-000000000006', ep, 4, 6, true)::uuid;
  ASSERT pg_temp.effective_dates(ep) = '9:medium,6:none',
    format('FAIL: first clean day not recorded: %s', pg_temp.effective_dates(ep));
END $$;

\echo '--- 4. undo a split: one period again with the same entries; refused once something changed'
DO $$
DECLARE ep uuid; second uuid; rev text; e public.bleeding_episodes;
BEGIN
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('34000000-0000-4000-8000-000000000001', 9);
  PERFORM pg_temp.observe_a('34000000-0000-4000-8000-000000000002', ep, 4, 'medium');
  second := pg_temp.split('34000000-0000-4000-8000-000000000003', ep, 4, 6, true)::uuid;
  rev := (SELECT id::text FROM public.bleeding_episode_revisions WHERE user_id = 'a0000000-0000-4000-8000-00000000000a' AND action = 'split');
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.undo_episode_split('34000000-0000-4000-8000-000000000004', %L)$q$, rev));
  ASSERT pg_temp.ep_count() = 1, 'FAIL: second period still there';
  SELECT * INTO e FROM public.bleeding_episodes WHERE id = ep;
  ASSERT e.lifecycle_status = 'open' AND e.end_date IS NULL AND e.end_precision IS NULL,
    'FAIL: original open state not back';
  ASSERT pg_temp.effective_dates(ep) = '9:medium,4:medium',
    format('FAIL: entries %s', pg_temp.effective_dates(ep));
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_observations_archive WHERE user_id = 'a0000000-0000-4000-8000-00000000000a' AND observed_date = current_date - 6),
    'FAIL: the added clean day was not archived';
  -- Replay is a no-op.
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.undo_episode_split('34000000-0000-4000-8000-000000000004', %L)$q$, rev));
  ASSERT pg_temp.ep_count() = 1, 'FAIL: replay';

  -- A new entry after a split makes it final.
  PERFORM pg_temp.reset();
  ep := pg_temp.start_a('34000000-0000-4000-8000-000000000005', 9);
  PERFORM pg_temp.observe_a('34000000-0000-4000-8000-000000000006', ep, 4, 'medium');
  second := pg_temp.split('34000000-0000-4000-8000-000000000007', ep, 4, 6, true)::uuid;
  PERFORM pg_temp.observe_a('34000000-0000-4000-8000-000000000008', second, 2, 'light');
  rev := (SELECT id::text FROM public.bleeding_episode_revisions WHERE user_id = 'a0000000-0000-4000-8000-00000000000a' AND action = 'split');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.undo_episode_split('34000000-0000-4000-8000-000000000009', %L)$q$, rev),
    'NW409', NULL, 'undo after a new entry');
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.undo_episode_split('34000000-0000-4000-8000-00000000000a', %L)$q$, rev),
    'P0001', '%does not belong%', 'undo by another account');
END $$;

-- Two neighbouring periods for A: 30..25 (clean 25) and 22..18 (clean 18).
CREATE FUNCTION pg_temp.two_periods() RETURNS uuid[] LANGUAGE plpgsql AS $$
DECLARE a uuid; b uuid;
BEGIN
  a := pg_temp.start_a('35000000-0000-4000-8000-000000000001', 30);
  PERFORM pg_temp.observe_a('35000000-0000-4000-8000-000000000002', a, 28, 'light');
  PERFORM pg_temp.end_a('35000000-0000-4000-8000-000000000003', a, 25);
  b := pg_temp.start_a('35000000-0000-4000-8000-000000000004', 22);
  PERFORM pg_temp.observe_a('35000000-0000-4000-8000-000000000005', b, 20, 'heavy');
  PERFORM pg_temp.end_a('35000000-0000-4000-8000-000000000006', b, 18);
  RETURN ARRAY[a, b];
END $$;

CREATE FUNCTION pg_temp.merge(p_op text, p_a uuid, p_b uuid, p_confirm boolean, p_uid text DEFAULT
  'a0000000-0000-4000-8000-00000000000a') RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.as_user(p_uid, format(
    $q$SELECT revision_id FROM public.merge_episodes(%L::uuid, %L::uuid, %L::uuid,
       %L::timestamptz, %L::timestamptz, %L)$q$,
    p_op, p_a, p_b, pg_temp.token(p_a), pg_temp.token(p_b), p_confirm));
$$;

\echo '--- 5. merge: preview writes nothing; confirming keeps every entry once, gap left unanswered'
DO $$
DECLARE eps uuid[]; e public.bleeding_episodes; before_ids text;
BEGIN
  PERFORM pg_temp.reset();
  eps := pg_temp.two_periods();
  SELECT string_agg(id::text, ',' ORDER BY id) INTO before_ids FROM public.bleeding_observations WHERE user_id = 'a0000000-0000-4000-8000-00000000000a';
  BEGIN
    PERFORM pg_temp.merge('36000000-0000-4000-8000-000000000001', eps[1], eps[2], false);
    RAISE EXCEPTION 'FAIL: preview did not stop';
  EXCEPTION WHEN SQLSTATE 'NW422' THEN NULL;
  END;
  ASSERT pg_temp.ep_count() = 2, 'FAIL: preview merged';

  PERFORM pg_temp.merge('36000000-0000-4000-8000-000000000002', eps[1], eps[2], true);
  ASSERT pg_temp.ep_count() = 1, 'FAIL: not one period';
  SELECT * INTO e FROM public.bleeding_episodes WHERE id = eps[1];
  ASSERT e.start_date = current_date - 30 AND e.end_date = current_date - 18
    AND e.lifecycle_status = 'ended', format('FAIL: merged shape %s..%s', e.start_date, e.end_date);
  ASSERT pg_temp.effective_dates(eps[1]) = '30:medium,28:light,25:none,22:medium,20:heavy,18:none',
    format('FAIL: entries %s', pg_temp.effective_dates(eps[1]));
  ASSERT (SELECT string_agg(id::text, ',' ORDER BY id) FROM public.bleeding_observations WHERE user_id = 'a0000000-0000-4000-8000-00000000000a') = before_ids,
    'FAIL: entries were added, removed or re-created';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_observations
                     WHERE user_id = 'a0000000-0000-4000-8000-00000000000a' AND observed_date IN (current_date - 24, current_date - 23)),
    'FAIL: the gap between them was filled';
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_episodes_archive WHERE id = eps[2]), 'FAIL: second not archived';
  -- A delayed start of the second period cannot bring it back: refused now
  -- because it overlaps, and tombstoned so it stays refused if the merged
  -- period is ever removed.
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT episode_id FROM public.start_bleeding_episode('35000000-0000-4000-8000-000000000004',
       current_date - 22, 'date_only', NULL, 'medium', NULL, 'date_only', 'UTC', 0)$q$,
    'P0001', '%overlaps%', 'replayed start of the merged-away period');
  ASSERT pg_temp.ep_count() = 1, 'FAIL: replayed start re-created the second period';
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_operation_tombstones
                 WHERE user_id = 'a0000000-0000-4000-8000-00000000000a' AND client_operation_id = '35000000-0000-4000-8000-000000000004'),
    'FAIL: start of the merged-away period not tombstoned';
  ASSERT EXISTS (SELECT 1 FROM public.bleeding_operation_tombstones
                 WHERE user_id = 'a0000000-0000-4000-8000-00000000000a' AND client_operation_id = '35000000-0000-4000-8000-000000000003'),
    'FAIL: end of the first period not tombstoned';
  -- Replay of the merge itself is a no-op.
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a',
    format($q$SELECT revision_id FROM public.merge_episodes('36000000-0000-4000-8000-000000000002', %L, %L)$q$,
      eps[1], eps[2]));
  ASSERT pg_temp.ep_count() = 1, 'FAIL: replay';
END $$;

\echo '--- 6. merge refusals'
DO $$
DECLARE eps uuid[]; c uuid;
BEGIN
  PERFORM pg_temp.reset();
  eps := pg_temp.two_periods();
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.merge_episodes('37000000-0000-4000-8000-000000000001', %L, %L, NULL, NULL, true)$q$,
    eps[2], eps[1]), 'P0001', '%must start before%', 'reversed order');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.merge_episodes('37000000-0000-4000-8000-000000000002', %L, %L, NULL, '2001-01-01', true)$q$,
    eps[1], eps[2]), 'NW409', NULL, 'stale second token');
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.merge_episodes('37000000-0000-4000-8000-000000000003', %L, %L, NULL, NULL, true)$q$,
    eps[1], eps[2]), 'P0001', '%does not belong%', 'another account');
  c := pg_temp.start_a('37000000-0000-4000-8000-000000000004', 10);
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.merge_episodes('37000000-0000-4000-8000-000000000005', %L, %L, NULL, NULL, true)$q$,
    eps[1], c), 'P0001', '%another period lies between%', 'not neighbours');
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.merge_episodes('37000000-0000-4000-8000-000000000006', %L, %L, NULL, NULL, true)$q$,
    c, eps[2]), 'P0001', '%must start before%', 'open period first');
  ASSERT pg_temp.ep_count() = 3, 'FAIL: a refused merge changed something';
END $$;

\echo '--- 7. undo a merge: both periods back with their own entries and ids'
DO $$
DECLARE eps uuid[]; rev text; a public.bleeding_episodes; b public.bleeding_episodes;
BEGIN
  PERFORM pg_temp.reset();
  eps := pg_temp.two_periods();
  rev := pg_temp.merge('38000000-0000-4000-8000-000000000001', eps[1], eps[2], true);
  PERFORM pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b', format(
    $q$SELECT revision_id FROM public.undo_episode_merge('38000000-0000-4000-8000-000000000002', %L)$q$, rev),
    'P0001', '%does not belong%', 'undo by another account');
  PERFORM pg_temp.as_user('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.undo_episode_merge('38000000-0000-4000-8000-000000000003', %L)$q$, rev));
  ASSERT pg_temp.ep_count() = 2, 'FAIL: not two periods again';
  SELECT * INTO a FROM public.bleeding_episodes WHERE id = eps[1];
  SELECT * INTO b FROM public.bleeding_episodes WHERE id = eps[2];
  ASSERT a.end_date = current_date - 25 AND b.start_date = current_date - 22
    AND b.end_date = current_date - 18, 'FAIL: shapes not restored';
  ASSERT pg_temp.effective_dates(eps[1]) = '30:medium,28:light,25:none', 'FAIL: first entries';
  ASSERT pg_temp.effective_dates(eps[2]) = '22:medium,20:heavy,18:none', 'FAIL: second entries';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_episodes_archive WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'), 'FAIL: archive not emptied';
  ASSERT NOT EXISTS (SELECT 1 FROM public.bleeding_operation_tombstones WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'), 'FAIL: tombstones left';
  -- The restored period's own start replays as itself again.
  ASSERT pg_temp.start_a('35000000-0000-4000-8000-000000000004', 22) = eps[2], 'FAIL: start replay after undo';

  -- After a new entry the merge is final.
  PERFORM pg_temp.reset();
  eps := pg_temp.two_periods();
  rev := pg_temp.merge('38000000-0000-4000-8000-000000000004', eps[1], eps[2], true);
  INSERT INTO public.bleeding_observations (user_id, episode_id, observed_date, precision, flow,
    source, utc_offset_minutes, supersedes_id)
  SELECT user_id, episode_id, observed_date, precision, 'heavy', source, 0, id
  FROM public.bleeding_observations WHERE episode_id = eps[1] AND observed_date = current_date - 20;
  PERFORM pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a', format(
    $q$SELECT revision_id FROM public.undo_episode_merge('38000000-0000-4000-8000-000000000005', %L)$q$, rev),
    'NW409', NULL, 'undo after a correction');
END $$;

\echo 'ALL PASSED'
