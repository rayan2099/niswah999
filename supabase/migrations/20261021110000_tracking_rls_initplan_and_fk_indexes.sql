-- Tracking data path: RLS initplan wrap + covering indexes for foreign keys.
--
-- 1. auth_rls_initplan (Supabase performance advisor). A bare `auth.uid()`
--    in a policy is evaluated once per row; `(select auth.uid())` is
--    planned as an InitPlan and evaluated once per statement. Each policy
--    below is rewritten with ALTER POLICY (never DROP/CREATE), so its name,
--    command, roles and PERMISSIVE flag stay as they are. The new
--    expression is built from the policy's own current catalog text with
--    only `auth.uid()` replaced by `(select auth.uid())`, and only after
--    that text is checked against the expression this repo's migrations
--    created (the expected text is listed below). A policy whose text
--    differs from both the expected original and the already-wrapped form
--    stops the migration (the transaction rolls back) instead of being
--    rewritten to something nobody reviewed. `public.can_access_user(...)`
--    calls are kept as they are (its argument is the row's column, not
--    auth.uid()).
--
--    Re-running is a no-op: a policy already in the wrapped form is skipped.
--    A table that does not exist in an environment is skipped.
--
-- 2. unindexed_foreign_keys on tracking tables. Without an index on the
--    referencing column, every delete of a referenced row scans the whole
--    referencing table. Measured on a local replica (2,000 synthetic users):
--    deleting one account took ~3.9 s, almost all of it in the per-row
--    checks of symptoms_log.cycle_entry_id (150 cycle_entries per user ->
--    150 full scans of symptoms_log) and bleeding_episodes.superseded_by
--    (one full scan of bleeding_episodes per deleted episode). The app also
--    deletes single cycle_entries rows (CycleEntriesProjection's
--    correction path, the legacy sheet's delete), each of which scanned
--    symptoms_log in full. The user_id indexes serve the ON DELETE CASCADE
--    from users (account deletion) and the data export's per-user reads;
--    cycle_logs' index also matches CycleLogRepository's
--    `user_id = ? ORDER BY start_date DESC`.
--
--    Plain CREATE INDEX IF NOT EXISTS: migrations run inside a transaction,
--    where CREATE INDEX CONCURRENTLY is not allowed. The build holds a
--    SHARE lock (blocks writes, not reads) on each table for the build
--    only; these tables are small. On a large table, build the same index
--    with CONCURRENTLY outside a migration first — this file then no-ops.
--
-- Nothing is dropped. The four indexes the advisor reported as unused
-- (bleeding_observations_episode_idx, bleeding_observations_user_date_idx,
-- bleeding_episodes_user_start_idx, cycle_baselines_user_reported_idx) are
-- kept: each matches a real query shape (see
-- test/tracking_efficiency/sql/tracking_rls_initplan_and_fk_indexes.sql).

DO $$
DECLARE
  r record;
  v_qual text;
  v_check text;
  v_norm_qual text;
  v_norm_check text;
  v_clause text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('bleeding_episodes', 'bleeding_episodes_insert_own',
        NULL, '(auth.uid() = user_id)'),
      ('bleeding_episodes', 'bleeding_episodes_update_own',
        'can_access_user(user_id)', '(auth.uid() = user_id)'),
      ('bleeding_observations', 'bleeding_observations_insert_own',
        NULL, '(auth.uid() = user_id)'),
      ('cycle_baselines', 'cycle_baselines_insert_own',
        NULL, '(auth.uid() = user_id)'),
      ('madhhab_history', 'Users can read their own madhhab_history',
        '(auth.uid() = user_id)', NULL),
      ('madhhab_history', 'Users can insert their own madhhab_history',
        NULL, '(auth.uid() = user_id)'),
      ('cycle_entries', 'cycle_entries_own',
        'can_access_user(user_id)', '(auth.uid() = user_id)'),
      ('symptoms_log', 'symptoms_log_own',
        'can_access_user(user_id)', '(auth.uid() = user_id)'),
      ('prayer_log', 'prayer_log_own',
        'can_access_user(user_id)', '(auth.uid() = user_id)'),
      ('adah_ledger', 'adah_ledger_own',
        'can_access_user(user_id)', '(auth.uid() = user_id)'),
      ('istihadah_episodes', 'istihadah_episodes_own',
        'can_access_user(user_id)', '(auth.uid() = user_id)'),
      ('nifas_records', 'nifas_records_own',
        'can_access_user(user_id)', '(auth.uid() = user_id)'),
      ('pregnancy_records', 'pregnancy_records_own',
        'can_access_user(user_id)', '(auth.uid() = user_id)'),
      ('pregnancy_profile', 'Users can only read their own pregnancy_profile',
        '(auth.uid() = user_id)', NULL),
      ('pregnancy_profile', 'Users can only insert their own pregnancy_profile',
        NULL, '(auth.uid() = user_id)'),
      ('pregnancy_profile', 'Users can only update their own pregnancy_profile',
        '(auth.uid() = user_id)', '(auth.uid() = user_id)'),
      ('pregnancy_profile', 'Users can only delete their own pregnancy_profile',
        '(auth.uid() = user_id)', NULL),
      ('cycle_logs', 'Users can view own cycle logs',
        '(auth.uid() = user_id)', NULL),
      ('cycle_logs', 'Users can insert own cycle logs',
        NULL, '(auth.uid() = user_id)'),
      ('cycle_logs', 'Users can update own cycle logs',
        '(auth.uid() = user_id)', '(auth.uid() = user_id)'),
      ('cycle_logs', 'Users can delete own cycle logs',
        '(auth.uid() = user_id)', NULL),
      -- As left by 20261021090000_users_privileged_columns_guard.sql.
      ('users', 'users_update_own',
        '(auth.uid() = id)', '(auth.uid() = id)')
    ) AS t(tbl, pol, old_using, old_check)
  LOOP
    SELECT p.qual, p.with_check INTO v_qual, v_check
    FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename = r.tbl
      AND p.policyname = r.pol;
    IF NOT FOUND THEN
      RAISE NOTICE 'tracking_rls_initplan: %.% not present, skipped',
        r.tbl, r.pol;
      CONTINUE;
    END IF;

    -- The deparsed text qualifies public.* only when public is not on the
    -- search_path; compare without that prefix.
    v_norm_qual := replace(v_qual, 'public.', '');
    v_norm_check := replace(v_check, 'public.', '');

    IF v_norm_qual IS NOT DISTINCT FROM
         replace(r.old_using, 'auth.uid()', '( SELECT auth.uid() AS uid)')
       AND v_norm_check IS NOT DISTINCT FROM
         replace(r.old_check, 'auth.uid()', '( SELECT auth.uid() AS uid)')
    THEN
      CONTINUE; -- already wrapped
    END IF;

    IF v_norm_qual IS DISTINCT FROM r.old_using
       OR v_norm_check IS DISTINCT FROM r.old_check
    THEN
      RAISE EXCEPTION
        'tracking_rls_initplan: policy %.% is USING % / WITH CHECK %, '
        'expected USING % / WITH CHECK % — not rewritten',
        r.tbl, r.pol, v_qual, v_check, r.old_using, r.old_check;
    END IF;

    v_clause := '';
    IF v_qual IS NOT NULL THEN
      v_clause := v_clause || format(' USING (%s)',
        replace(v_qual, 'auth.uid()', '(select auth.uid())'));
    END IF;
    IF v_check IS NOT NULL THEN
      v_clause := v_clause || format(' WITH CHECK (%s)',
        replace(v_check, 'auth.uid()', '(select auth.uid())'));
    END IF;
    EXECUTE format('ALTER POLICY %I ON public.%I', r.pol, r.tbl) || v_clause;
  END LOOP;
END $$;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('bleeding_episodes', 'bleeding_episodes_superseded_by_idx',
        '(superseded_by)'),
      ('symptoms_log', 'symptoms_log_cycle_entry_id_idx', '(cycle_entry_id)'),
      ('symptoms_log', 'symptoms_log_user_id_idx', '(user_id)'),
      ('nifas_records', 'nifas_records_user_id_idx', '(user_id)'),
      ('pregnancy_records', 'pregnancy_records_user_id_idx', '(user_id)'),
      ('pregnancy_records', 'pregnancy_records_nifas_id_idx', '(nifas_id)'),
      ('istihadah_episodes', 'istihadah_episodes_user_id_idx', '(user_id)'),
      ('cycle_logs', 'cycle_logs_user_start_idx', '(user_id, start_date DESC)')
    ) AS t(tbl, idx, cols)
  LOOP
    IF to_regclass(format('public.%I', r.tbl)) IS NULL THEN
      RAISE NOTICE 'tracking_fk_indexes: public.% not present, skipped', r.tbl;
      CONTINUE;
    END IF;
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I %s',
      r.idx, r.tbl, r.cols);
  END LOOP;
END $$;
