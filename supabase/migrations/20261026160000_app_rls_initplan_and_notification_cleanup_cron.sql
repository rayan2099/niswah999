-- App tables: RLS initplan wrap + hourly notification cleanup.
--
-- 1. auth_rls_initplan (Supabase performance advisor), for the 35 policies
--    on non-tracking tables that still call a bare `auth.uid()` (chat,
--    community, dreams, wellbeing, profiles, private messages, Ramadan,
--    secret vault). 20261021110000 did the same for the tracking tables;
--    this uses the same method: each policy is rewritten with ALTER POLICY
--    (never DROP/CREATE), so its name, command, roles and PERMISSIVE flag
--    stay as they are, and the new expression is the policy's own catalog
--    text with only `auth.uid()` replaced by `(select auth.uid())`. A
--    policy is rewritten only when its text equals the expression listed
--    below (taken from staging on 2026-10-26, and identical to what the
--    baseline plus migrations build). A policy whose text differs from both
--    that and the already-wrapped form stops the migration (the
--    transaction rolls back) instead of being rewritten to something
--    nobody reviewed. `can_access_user(...)` and
--    `is_conversation_participant(...)` calls are kept as they are.
--
--    Re-running is a no-op: a policy already in the wrapped form is skipped.
--    A policy or table that does not exist in an environment is skipped.
--
-- 2. Notification cleanup. public.cleanup_notification_activity() (90-day
--    inbox retention, push-job pruning) was only called by the
--    notification-dispatch worker, which is not deployed while push is off,
--    so in that state nothing ever pruned the inbox. An hourly pg_cron job
--    (minute 17) now calls it. Hourly, not daily: each call deletes at most
--    1000 inbox rows and 1000 push jobs, so a daily run would fall behind
--    once more than 1000 notifications a day reach the 90-day limit. The
--    worker keeps calling it too; the bounded batches make that safe.
--    Skipped where pg_cron is not available (the local test database);
--    cron.schedule() replaces a job of the same name, so re-running is a
--    no-op.

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
      ('chat_history', 'chat_history_own',
        'can_access_user(user_id)',
        '(auth.uid() = user_id)'),
      ('chat_messages', 'Users can delete their own chat messages',
        '(auth.uid() = user_id)',
        NULL),
      ('chat_messages', 'Users can insert messages into their own chat threads',
        NULL,
        E'((auth.uid() = user_id) AND (EXISTS ( SELECT 1\n   FROM chat_threads ct\n  WHERE ((ct.id = chat_messages.thread_id) AND (ct.user_id = auth.uid())))))'),
      ('chat_messages', 'Users can read their own chat_messages or messages in their thr',
        E'((auth.uid() = user_id) OR (EXISTS ( SELECT 1\n   FROM chat_threads ct\n  WHERE ((ct.id = chat_messages.thread_id) AND (ct.user_id = auth.uid())))))',
        NULL),
      ('chat_messages', 'Users can update their own chat messages',
        '(auth.uid() = user_id)',
        '(auth.uid() = user_id)'),
      ('chat_threads', 'Users can delete their own chat_threads',
        '(auth.uid() = user_id)',
        NULL),
      ('chat_threads', 'Users can insert their own chat_threads',
        NULL,
        '(auth.uid() = user_id)'),
      ('chat_threads', 'Users can read their own chat_threads',
        '(auth.uid() = user_id)',
        NULL),
      ('chat_threads', 'Users can update their own chat_threads',
        '(auth.uid() = user_id)',
        '(auth.uid() = user_id)'),
      ('community_comments', 'Users can create comments on visible posts',
        NULL,
        E'((auth.uid() = user_id) AND (EXISTS ( SELECT 1\n   FROM community_posts cp\n  WHERE (cp.id = community_comments.post_id))))'),
      ('community_comments', 'Users can delete their own community_comments',
        '(auth.uid() = user_id)',
        NULL),
      ('community_comments', 'Users can update their own community_comments',
        '(auth.uid() = user_id)',
        '(auth.uid() = user_id)'),
      ('community_likes', 'Users can like as themselves',
        NULL,
        '(auth.uid() = user_id)'),
      ('community_likes', 'Users can remove their own like',
        '(auth.uid() = user_id)',
        NULL),
      ('community_posts', 'Users can create their own community_posts',
        NULL,
        '(auth.uid() = user_id)'),
      ('community_posts', 'Users can delete their own community_posts',
        '(auth.uid() = user_id)',
        NULL),
      ('community_posts', 'Users can update their own community_posts',
        '(auth.uid() = user_id)',
        '(auth.uid() = user_id)'),
      ('dream_entries', 'Users can only delete their own dream_entries',
        '(auth.uid() = user_id)',
        NULL),
      ('dream_entries', 'Users can only insert their own dream_entries',
        NULL,
        '(auth.uid() = user_id)'),
      ('dream_entries', 'Users can only read their own dream_entries',
        '(auth.uid() = user_id)',
        NULL),
      ('dream_entries', 'Users can only update their own dream_entries',
        '(auth.uid() = user_id)',
        '(auth.uid() = user_id)'),
      ('private_conversations', 'Participants can read their conversations',
        '((auth.uid() = participant_one) OR (auth.uid() = participant_two))',
        NULL),
      ('private_conversations', 'Participants can update their conversations',
        '((auth.uid() = participant_one) OR (auth.uid() = participant_two))',
        '((auth.uid() = participant_one) OR (auth.uid() = participant_two))'),
      ('private_conversations', 'Users can create conversations they participate in',
        NULL,
        '((auth.uid() = participant_one) OR (auth.uid() = participant_two))'),
      ('private_messages', 'Participants can send messages in their conversations',
        NULL,
        '((auth.uid() = sender_id) AND is_conversation_participant(conversation_id))'),
      ('private_messages', 'Recipients can mark messages as read',
        '(is_conversation_participant(conversation_id) AND (auth.uid() <> sender_id))',
        '(is_conversation_participant(conversation_id) AND (auth.uid() <> sender_id))'),
      ('profiles', 'Users can insert own profile',
        NULL,
        '(auth.uid() = id)'),
      ('profiles', 'Users can update own profile',
        '(auth.uid() = id)',
        '(auth.uid() = id)'),
      ('profiles', 'Users can view own profile',
        '(auth.uid() = id)',
        NULL),
      ('ramadan_records', 'ramadan_records_own',
        'can_access_user(user_id)',
        '(auth.uid() = user_id)'),
      ('secret_vault', 'secret_vault_own',
        'can_access_user(user_id)',
        '(auth.uid() = user_id)'),
      ('wellbeing_logs', 'Users can only delete their own wellbeing_logs',
        '(auth.uid() = user_id)',
        NULL),
      ('wellbeing_logs', 'Users can only insert their own wellbeing_logs',
        NULL,
        '(auth.uid() = user_id)'),
      ('wellbeing_logs', 'Users can only read their own wellbeing_logs',
        '(auth.uid() = user_id)',
        NULL),
      ('wellbeing_logs', 'Users can only update their own wellbeing_logs',
        '(auth.uid() = user_id)',
        '(auth.uid() = user_id)')
    ) AS t(tbl, pol, old_using, old_check)
  LOOP
    SELECT p.qual, p.with_check INTO v_qual, v_check
    FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename = r.tbl
      AND p.policyname = r.pol;
    IF NOT FOUND THEN
      RAISE NOTICE 'app_rls_initplan: %.% not present, skipped',
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
        'app_rls_initplan: policy %.% is USING % / WITH CHECK %, '
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
BEGIN
  IF to_regprocedure('public.cleanup_notification_activity()') IS NULL THEN
    RAISE NOTICE 'notification_cleanup_cron: cleanup function not present, skipped';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_available_extensions
                 WHERE name = 'pg_cron') THEN
    RAISE NOTICE 'notification_cleanup_cron: pg_cron not available, skipped';
    RETURN;
  END IF;
  CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
  PERFORM cron.schedule(
    'notification-cleanup-hourly',
    '17 * * * *',
    'select public.cleanup_notification_activity()'
  );
END $$;
