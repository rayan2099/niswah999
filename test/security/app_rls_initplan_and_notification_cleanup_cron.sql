-- Regression for
-- supabase/migrations/20261026160000_app_rls_initplan_and_notification_cleanup_cron.sql:
-- the remaining public RLS policies (chat, community, dreams, wellbeing,
-- profiles, private messages, Ramadan, secret vault) evaluate auth.uid()
-- once per statement (InitPlan) without changing who can read or write
-- what, the rewrite refuses a policy whose text drifted, and re-running the
-- migration is a no-op. The pg_cron part is skipped here (no pg_cron on the
-- scratch database); its NOTICE path is what runs.
--
-- Run only on a scratch database built by run_sql_checks.sh. Exits non-zero
-- (ON_ERROR_STOP) on the first failed assertion; prints ALL PASSED otherwise.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;

\echo '--- 1. no public policy calls auth.uid() per row'
DO $$
DECLARE v text;
BEGIN
  SELECT string_agg(format('%s.%s', tablename, policyname), ', ') INTO v
  FROM pg_policies
  WHERE schemaname = 'public'
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
    AND tablename IN ('chat_history', 'chat_messages', 'chat_threads',
      'community_comments', 'community_likes', 'community_posts',
      'dream_entries', 'private_conversations', 'private_messages',
      'profiles', 'ramadan_records', 'secret_vault', 'wellbeing_logs')
    AND (qual LIKE '%SELECT auth.uid()%' OR with_check LIKE '%SELECT auth.uid()%')
    AND (roles <> '{public}' OR permissive <> 'PERMISSIVE');
  ASSERT v IS NULL, format('FAIL: roles/permissive changed on %s', v);

  ASSERT (SELECT cmd FROM pg_policies WHERE tablename = 'secret_vault'
          AND policyname = 'secret_vault_own') = 'ALL',
    'FAIL: secret_vault_own is no longer FOR ALL';
  ASSERT (SELECT qual FROM pg_policies WHERE tablename = 'secret_vault'
          AND policyname = 'secret_vault_own') = 'can_access_user(user_id)',
    'FAIL: secret_vault_own USING changed';
  ASSERT (SELECT qual FROM pg_policies WHERE tablename = 'private_messages'
          AND policyname = 'Recipients can mark messages as read')
         = '(is_conversation_participant(conversation_id) AND (( SELECT auth.uid() AS uid) <> sender_id))',
    'FAIL: private_messages mark-read USING is not the wrapped check';
  ASSERT (SELECT qual FROM pg_policies WHERE tablename = 'chat_messages'
          AND policyname = 'Users can read their own chat_messages or messages in their thr')
         LIKE '%(ct.user_id = ( SELECT auth.uid() AS uid))%',
    'FAIL: auth.uid() inside the chat_messages EXISTS was not wrapped';
END $$;

INSERT INTO auth.users (id, email) VALUES
  ('a0000000-0000-4000-8000-00000000000a', 'a@example.invalid'),
  ('b0000000-0000-4000-8000-00000000000b', 'b@example.invalid'),
  ('c0000000-0000-4000-8000-00000000000c', 'c@example.invalid');
-- Messaging requires the current community terms (20261030090000).
DO $$ BEGIN
  IF to_regclass('public.community_terms_acceptances') IS NOT NULL THEN
    EXECUTE $q$INSERT INTO public.community_terms_acceptances (user_id, terms_version)
      SELECT id, public.community_terms_version() FROM auth.users$q$;
  END IF;
END $$;
INSERT INTO public.dream_entries (user_id, title, description) VALUES
  ('a0000000-0000-4000-8000-00000000000a', 'a', 'a'),
  ('b0000000-0000-4000-8000-00000000000b', 'b', 'b');
INSERT INTO public.wellbeing_logs (user_id, log_date, mood, energy, sleep) VALUES
  ('a0000000-0000-4000-8000-00000000000a', current_date, 3, 3, 3),
  ('b0000000-0000-4000-8000-00000000000b', current_date, 3, 3, 3);
INSERT INTO public.chat_threads (id, user_id, thread_type) VALUES
  ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-00000000000a', 'general'),
  ('b1000000-0000-4000-8000-00000000000b', 'b0000000-0000-4000-8000-00000000000b', 'general');
INSERT INTO public.private_conversations (id, participant_one, participant_two) VALUES
  ('ab000000-0000-4000-8000-0000000000ab', 'a0000000-0000-4000-8000-00000000000a',
   'b0000000-0000-4000-8000-00000000000b'),
  ('bc000000-0000-4000-8000-0000000000bc', 'b0000000-0000-4000-8000-00000000000b',
   'c0000000-0000-4000-8000-00000000000c');
INSERT INTO public.private_messages (id, conversation_id, sender_id, content) VALUES
  ('ab100000-0000-4000-8000-0000000000ab', 'ab000000-0000-4000-8000-0000000000ab',
   'b0000000-0000-4000-8000-00000000000b', 'hi a'),
  ('ab200000-0000-4000-8000-0000000000ab', 'ab000000-0000-4000-8000-0000000000ab',
   'a0000000-0000-4000-8000-00000000000a', 'hi b'),
  ('bc100000-0000-4000-8000-0000000000bc', 'bc000000-0000-4000-8000-0000000000bc',
   'b0000000-0000-4000-8000-00000000000b', 'hi c');

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
  ASSERT (SELECT count(*) FROM public.dream_entries) = 1,
    'FAIL: dream_entries visibility changed';
  ASSERT (SELECT count(*) FROM public.wellbeing_logs) = 1,
    'FAIL: wellbeing_logs visibility changed';
  ASSERT (SELECT count(*) FROM public.chat_threads) = 1,
    'FAIL: chat_threads visibility changed';
  ASSERT (SELECT count(*) FROM public.private_conversations) = 1,
    'FAIL: private_conversations visibility changed';
  ASSERT (SELECT count(*) FROM public.private_messages) = 2,
    'FAIL: private_messages visibility changed';
END $$;
-- Own writes still pass the wrapped WITH CHECK.
INSERT INTO public.dream_entries (user_id, title, description)
VALUES ('a0000000-0000-4000-8000-00000000000a', 'a2', 'a2');
INSERT INTO public.wellbeing_logs (user_id, log_date, mood, energy, sleep)
VALUES ('a0000000-0000-4000-8000-00000000000a', current_date - 1, 4, 4, 4);
INSERT INTO public.chat_messages (thread_id, user_id, role, content)
VALUES ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-00000000000a', 'user', 'x');
INSERT INTO public.private_messages (conversation_id, sender_id, content)
VALUES ('ab000000-0000-4000-8000-0000000000ab', 'a0000000-0000-4000-8000-00000000000a', 'again');
DO $$ BEGIN
  -- The recipient can mark a received message read; the sender cannot.
  UPDATE public.private_messages SET is_read = true
  WHERE id = 'ab100000-0000-4000-8000-0000000000ab';
  ASSERT FOUND, 'FAIL: recipient could not mark a message read';
  UPDATE public.private_messages SET is_read = true
  WHERE id = 'ab200000-0000-4000-8000-0000000000ab';
  ASSERT NOT FOUND, 'FAIL: sender marked their own message read';
  -- Another user's row is untouched by an UPDATE (USING filters it out).
  UPDATE public.dream_entries SET title = 'x'
  WHERE user_id = 'b0000000-0000-4000-8000-00000000000b';
  ASSERT NOT FOUND, 'FAIL: updated another user''s dream_entries row';
END $$;
COMMIT;

BEGIN;
SELECT pg_temp.expect_denied('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.dream_entries (user_id, title, description)
     VALUES ('b0000000-0000-4000-8000-00000000000b', 'x', 'x')$q$,
  'dream_entries insert for another user');
SELECT pg_temp.expect_denied('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.chat_messages (thread_id, user_id, role, content)
     VALUES ('b1000000-0000-4000-8000-00000000000b', 'a0000000-0000-4000-8000-00000000000a', 'user', 'x')$q$,
  'chat_messages insert into another user''s thread');
SELECT pg_temp.expect_denied('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.private_messages (conversation_id, sender_id, content)
     VALUES ('bc000000-0000-4000-8000-0000000000bc', 'a0000000-0000-4000-8000-00000000000a', 'x')$q$,
  'private_messages insert into a conversation she is not in');
SELECT pg_temp.expect_denied('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.private_conversations (participant_one, participant_two)
     VALUES ('b0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-00000000000c')$q$,
  'private_conversations between two other users');
SELECT pg_temp.expect_denied('a0000000-0000-4000-8000-00000000000a',
  $q$UPDATE public.wellbeing_logs SET user_id = 'b0000000-0000-4000-8000-00000000000b'
     WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'$q$,
  'moving a wellbeing_logs row to another user');
COMMIT;

\echo '--- 4. the rewrite is planned as an InitPlan'
BEGIN;
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-00000000000a', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  ASSERT pg_temp.plan('SELECT * FROM public.dream_entries') LIKE '%InitPlan%',
    'FAIL: dream_entries policy is not an InitPlan';
  ASSERT pg_temp.plan('SELECT * FROM public.wellbeing_logs') LIKE '%InitPlan%',
    'FAIL: wellbeing_logs policy is not an InitPlan';
  ASSERT pg_temp.plan('SELECT * FROM public.private_conversations') LIKE '%InitPlan%',
    'FAIL: private_conversations policy is not an InitPlan';
END $$;
ROLLBACK;

\echo '--- 5. re-running the migration is a no-op'
CREATE TEMP TABLE before_policies AS
  SELECT tablename, policyname, cmd, roles, qual, with_check FROM pg_policies
  WHERE schemaname = 'public';
\ir ../../supabase/migrations/20261026160000_app_rls_initplan_and_notification_cleanup_cron.sql
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

\echo '--- 6. a drifted policy stops the migration instead of being rewritten'
ALTER POLICY "Users can only insert their own dream_entries" ON public.dream_entries
  WITH CHECK (auth.uid() = user_id AND title IS NOT NULL);
\set ON_ERROR_STOP 0
\ir ../../supabase/migrations/20261026160000_app_rls_initplan_and_notification_cleanup_cron.sql
\set ON_ERROR_STOP 1
SELECT :'LAST_ERROR_MESSAGE' LIKE 'app_rls_initplan: policy dream_entries.Users can only insert their own dream_entries is%'
  AS drift_refused \gset
\if :drift_refused
\else
  \echo 'FAIL: a drifted policy was not refused'
  SELECT 1/0;
\endif
DO $$ BEGIN
  ASSERT (SELECT with_check FROM pg_policies WHERE tablename = 'dream_entries'
          AND policyname = 'Users can only insert their own dream_entries')
         = '((auth.uid() = user_id) AND (title IS NOT NULL))',
    'FAIL: a drifted policy was rewritten';
END $$;

\echo ALL PASSED
