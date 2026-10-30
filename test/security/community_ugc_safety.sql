-- App Store guideline 1.2 regression: community terms, objectionable-word
-- filter, blocking, reporting, auto-hide, moderation and suspension are all
-- enforced by the database, whatever the client does.
-- Guards supabase/migrations/20261030090000_community_ugc_safety.sql.
--
-- Run only on a scratch database built by run_sql_checks.sh. Exits non-zero
-- (ON_ERROR_STOP) on the first failed assertion; prints ALL PASSED otherwise.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;

-- a = author, b = blocks a, c/d/e = reporters, m = moderator
INSERT INTO auth.users (id, email) VALUES
  ('a0000000-0000-4000-8000-00000000000a', 'a@example.invalid'),
  ('b0000000-0000-4000-8000-00000000000b', 'b@example.invalid'),
  ('c0000000-0000-4000-8000-00000000000c', 'c@example.invalid'),
  ('d0000000-0000-4000-8000-00000000000d', 'd@example.invalid'),
  ('e0000000-0000-4000-8000-00000000000e', 'e@example.invalid'),
  ('f0000000-0000-4000-8000-00000000000f', 'm@example.invalid');
UPDATE public.users SET role = 'admin'
WHERE id = 'f0000000-0000-4000-8000-00000000000f';

-- Runs p_sql as `authenticated` user p_uid (or anon when p_uid is null).
CREATE FUNCTION pg_temp.run_as(p_uid text, p_sql text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  IF p_uid IS NULL THEN
    EXECUTE 'SET LOCAL ROLE anon';
  ELSE
    EXECUTE 'SET LOCAL ROLE authenticated';
  END IF;
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'RESET ROLE';
    RAISE;
  END;
  EXECUTE 'RESET ROLE';
END $$;

-- Runs a scalar query as p_uid and returns its result as text.
CREATE FUNCTION pg_temp.value_as(p_uid text, p_sql text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE p_sql INTO v;
  EXECUTE 'RESET ROLE';
  RETURN v;
END $$;

-- Requires p_sql, run as p_uid, to fail with SQLSTATE p_state.
CREATE FUNCTION pg_temp.expect_error(p_uid text, p_sql text, p_state text, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
  BEGIN
    PERFORM pg_temp.run_as(p_uid, p_sql);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    EXECUTE 'RESET ROLE';
    IF v_state = p_state THEN RETURN; END IF;
    RAISE EXCEPTION 'FAIL: % raised % (%), expected %', p_label, v_state, SQLERRM, p_state;
  END;
  RAISE EXCEPTION 'FAIL: % was allowed', p_label;
END $$;

CREATE FUNCTION pg_temp.post_sql(p_id text, p_content text)
RETURNS text LANGUAGE sql AS $$
  SELECT format($q$INSERT INTO public.community_posts
    (id, user_id, author_name, title, content, category, language)
    VALUES (%L, auth.uid(), 'Member', 'Title', %L, 'general', 'en')$q$,
    p_id, p_content)
$$;

\echo '--- 1. posting needs the current community terms'
BEGIN;
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  pg_temp.post_sql('11111111-0000-4000-8000-000000000001', 'hello'),
  'NSW02', 'post without terms');
SELECT pg_temp.run_as(u, format(
  $q$INSERT INTO public.community_terms_acceptances (user_id, terms_version)
     VALUES (auth.uid(), 'old-version')$q$))
FROM unnest(ARRAY['a0000000-0000-4000-8000-00000000000a']) u;
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  pg_temp.post_sql('11111111-0000-4000-8000-000000000001', 'hello'),
  'NSW02', 'post with only an outdated terms version');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.community_terms_acceptances (user_id, terms_version)
     VALUES ('b0000000-0000-4000-8000-00000000000b', public.community_terms_version())$q$,
  '42501', 'accepting terms on behalf of someone else');
SELECT pg_temp.run_as(u,
  $q$INSERT INTO public.community_terms_acceptances (user_id, terms_version)
     VALUES (auth.uid(), public.community_terms_version())$q$)
FROM unnest(ARRAY[
  'a0000000-0000-4000-8000-00000000000a', 'b0000000-0000-4000-8000-00000000000b',
  'c0000000-0000-4000-8000-00000000000c', 'd0000000-0000-4000-8000-00000000000d',
  'e0000000-0000-4000-8000-00000000000e']) u;
SELECT pg_temp.run_as('a0000000-0000-4000-8000-00000000000a',
  pg_temp.post_sql('11111111-0000-4000-8000-000000000001', 'A calm question about sleep'));
SELECT pg_temp.run_as('b0000000-0000-4000-8000-00000000000b',
  pg_temp.post_sql('22222222-0000-4000-8000-000000000002', 'B shares a routine'));
COMMIT;

\echo '--- 2. objectionable words are rejected server-side (EN + AR)'
BEGIN;
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  pg_temp.post_sql('11111111-0000-4000-8000-0000000000f1', 'you are a WHORE!!'),
  'NSW01', 'English slur in content');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  pg_temp.post_sql('11111111-0000-4000-8000-0000000000f2', 'يا شرمـوطَة'),
  'NSW01', 'Arabic insult with tatweel and diacritics');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  pg_temp.post_sql('11111111-0000-4000-8000-0000000000f3', 'كس أمك'),
  'NSW01', 'Arabic multi-word insult with hamza alef');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$UPDATE public.community_posts SET content = 'just kys'
     WHERE id = '11111111-0000-4000-8000-000000000001'$q$,
  'NSW01', 'editing a post into abuse');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.community_comments (post_id, user_id, author_name, content)
     VALUES ('22222222-0000-4000-8000-000000000002', auth.uid(), 'fucker', 'nice')$q$,
  'NSW01', 'abusive author name on a comment');
-- Whole-word matching: innocent words containing a term are allowed.
SELECT pg_temp.run_as('a0000000-0000-4000-8000-00000000000a',
  pg_temp.post_sql('11111111-0000-4000-8000-0000000000f4',
    'Visiting Scunthorpe, then a class on spice blends'));
COMMIT;

\echo '--- 3. clients cannot hide or unhide content themselves'
BEGIN;
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.community_posts
    (user_id, author_name, title, content, category, language, hidden_at)
    VALUES (auth.uid(), 'M', 'T', 'x', 'general', 'en', now())$q$,
  '42501', 'insert with hidden_at');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$UPDATE public.community_posts SET hidden_reason = 'x'
     WHERE id = '11111111-0000-4000-8000-000000000001'$q$,
  '42501', 'update of hidden_reason');
COMMIT;

\echo '--- 4. blocking hides content and stops contact both ways'
BEGIN;
SELECT pg_temp.run_as('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.community_comments (post_id, user_id, author_name, content)
     VALUES ('22222222-0000-4000-8000-000000000002', auth.uid(), 'A', 'before block')$q$);
SELECT pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b',
  $q$INSERT INTO public.user_blocks (blocker_id, blocked_id)
     VALUES ('c0000000-0000-4000-8000-00000000000c', 'a0000000-0000-4000-8000-00000000000a')$q$,
  '42501', 'creating a block for someone else');
SELECT pg_temp.run_as('b0000000-0000-4000-8000-00000000000b',
  $q$INSERT INTO public.user_blocks (blocker_id, blocked_id, blocked_display_name)
     VALUES (auth.uid(), 'a0000000-0000-4000-8000-00000000000a', 'Member')$q$);
DO $$ BEGIN
  ASSERT pg_temp.value_as('b0000000-0000-4000-8000-00000000000b',
    $q$SELECT count(*) FROM public.community_posts
       WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'$q$) = '0',
    'FAIL: blocker still sees the blocked member''s posts';
  ASSERT pg_temp.value_as('b0000000-0000-4000-8000-00000000000b',
    $q$SELECT count(*) FROM public.community_comments
       WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'$q$) = '0',
    'FAIL: blocker still sees the blocked member''s comments';
  ASSERT pg_temp.value_as('c0000000-0000-4000-8000-00000000000c',
    $q$SELECT count(*) FROM public.community_posts
       WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'$q$)::int >= 1,
    'FAIL: a block hid content from an uninvolved member';
  ASSERT pg_temp.value_as('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT count(*) FROM public.user_blocks$q$) = '0',
    'FAIL: the blocked member can read who blocked her';
END $$;
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.community_comments (post_id, user_id, author_name, content)
     VALUES ('22222222-0000-4000-8000-000000000002', auth.uid(), 'A', 'after block')$q$,
  'NSW04', 'blocked member commenting on the blocker''s post');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.private_conversations (participant_one, participant_two)
     VALUES (auth.uid(), 'b0000000-0000-4000-8000-00000000000b')$q$,
  'NSW04', 'blocked member opening a conversation');
SELECT pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b',
  $q$INSERT INTO public.private_conversations (participant_one, participant_two)
     VALUES (auth.uid(), 'a0000000-0000-4000-8000-00000000000a')$q$,
  'NSW04', 'blocker opening a conversation with the blocked member');
COMMIT;

\echo '--- 5. messages: blocked sends fail, read receipts still work'
-- A conversation that existed before the block.
INSERT INTO public.private_conversations (id, participant_one, participant_two) VALUES
  ('33333333-0000-4000-8000-000000000003',
   'a0000000-0000-4000-8000-00000000000a', 'b0000000-0000-4000-8000-00000000000b'),
  ('44444444-0000-4000-8000-000000000004',
   'a0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000c');
INSERT INTO public.private_messages (id, conversation_id, sender_id, content) VALUES
  ('55555555-0000-4000-8000-000000000005', '33333333-0000-4000-8000-000000000003',
   'a0000000-0000-4000-8000-00000000000a', 'sent before the block'),
  ('66666666-0000-4000-8000-000000000006', '44444444-0000-4000-8000-000000000004',
   'a0000000-0000-4000-8000-00000000000a', 'unwanted message to c');
BEGIN;
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.private_messages (conversation_id, sender_id, content)
     VALUES ('33333333-0000-4000-8000-000000000003', auth.uid(), 'hello again')$q$,
  'NSW04', 'blocked member sending a message');
SELECT pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b',
  $q$INSERT INTO public.private_messages (conversation_id, sender_id, content)
     VALUES ('33333333-0000-4000-8000-000000000003', auth.uid(), 'hi')$q$,
  'NSW04', 'blocker sending to the blocked member');
SELECT pg_temp.expect_error('c0000000-0000-4000-8000-00000000000c',
  $q$INSERT INTO public.private_messages (conversation_id, sender_id, content)
     VALUES ('44444444-0000-4000-8000-000000000004', auth.uid(), 'go fuck off')$q$,
  'NSW01', 'abusive private message');
SELECT pg_temp.run_as('b0000000-0000-4000-8000-00000000000b',
  $q$UPDATE public.private_messages SET is_read = true
     WHERE conversation_id = '33333333-0000-4000-8000-000000000003'$q$);
COMMIT;

\echo '--- 6. reporting'
BEGIN;
SELECT pg_temp.expect_error(NULL,
  $q$SELECT public.report_community_content('post',
     '11111111-0000-4000-8000-000000000001', 'spam', NULL)$q$,
  '42501', 'anon calling report_community_content');
SELECT pg_temp.expect_error('c0000000-0000-4000-8000-00000000000c',
  $q$INSERT INTO public.community_reports (reporter_id, target_type, target_id, reason)
     VALUES (auth.uid(), 'post', '11111111-0000-4000-8000-000000000001', 'spam')$q$,
  '42501', 'direct insert into community_reports');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$SELECT public.report_community_content('post',
     '11111111-0000-4000-8000-000000000001', 'spam', NULL)$q$,
  '22023', 'reporting your own post');
SELECT pg_temp.expect_error('b0000000-0000-4000-8000-00000000000b',
  $q$SELECT public.report_community_content('message',
     '66666666-0000-4000-8000-000000000006', 'harassment', NULL)$q$,
  'P0002', 'reporting a message from a conversation you are not in');
SELECT pg_temp.expect_error('c0000000-0000-4000-8000-00000000000c',
  $q$SELECT public.report_community_content('post',
     '11111111-0000-4000-8000-000000000001', 'not-a-reason', NULL)$q$,
  '23514', 'unknown report reason');
COMMIT;

DO $$
DECLARE r1 text; r2 text;
BEGIN
  r1 := pg_temp.value_as('c0000000-0000-4000-8000-00000000000c',
    $q$SELECT public.report_community_content('post',
       '11111111-0000-4000-8000-000000000001', 'harassment', 'rude')$q$);
  r2 := pg_temp.value_as('c0000000-0000-4000-8000-00000000000c',
    $q$SELECT public.report_community_content('post',
       '11111111-0000-4000-8000-000000000001', 'spam', NULL)$q$);
  ASSERT r1 IS NOT NULL AND r1 = r2, 'FAIL: repeat report is not idempotent';
  PERFORM pg_temp.value_as('c0000000-0000-4000-8000-00000000000c',
    $q$SELECT public.report_community_content('message',
       '66666666-0000-4000-8000-000000000006', 'harassment', NULL)$q$);
  PERFORM pg_temp.value_as('c0000000-0000-4000-8000-00000000000c',
    $q$SELECT public.report_community_content('user',
       'a0000000-0000-4000-8000-00000000000a', 'harassment', NULL)$q$);
  ASSERT (SELECT content_snapshot FROM public.community_reports
          WHERE target_id = '66666666-0000-4000-8000-000000000006')
         = 'unwanted message to c',
    'FAIL: message report has no snapshot for moderators';
  ASSERT pg_temp.value_as('d0000000-0000-4000-8000-00000000000d',
    $q$SELECT count(*) FROM public.community_reports$q$) = '0',
    'FAIL: a member can read other members'' reports';
  ASSERT pg_temp.value_as('c0000000-0000-4000-8000-00000000000c',
    $q$SELECT count(*) FROM public.community_reports$q$) = '3',
    'FAIL: a reporter cannot read her own reports';
  ASSERT (SELECT hidden_at FROM public.community_posts
          WHERE id = '11111111-0000-4000-8000-000000000001') IS NULL,
    'FAIL: one report hid the post';
END $$;

\echo '--- 7. three different reporters auto-hide a post pending review'
DO $$
BEGIN
  PERFORM pg_temp.value_as(u,
    $q$SELECT public.report_community_content('post',
       '11111111-0000-4000-8000-000000000001', 'harassment', NULL)$q$)
  FROM unnest(ARRAY['d0000000-0000-4000-8000-00000000000d',
                    'e0000000-0000-4000-8000-00000000000e']) u;
  ASSERT (SELECT hidden_reason FROM public.community_posts
          WHERE id = '11111111-0000-4000-8000-000000000001') = 'auto_reports',
    'FAIL: post not auto-hidden after 3 reporters';
  ASSERT pg_temp.value_as('a0000000-0000-4000-8000-00000000000a',
    $q$SELECT count(*) FROM public.community_posts
       WHERE id = '11111111-0000-4000-8000-000000000001'$q$) = '0',
    'FAIL: hidden post still visible';
  ASSERT (SELECT is_hidden FROM public.community_posts
          WHERE id = '11111111-0000-4000-8000-000000000001'),
    'FAIL: is_hidden (read by notifications) does not follow hidden_at';
END $$;

\echo '--- 8. moderation is admin-only; dismiss restores, suspend ejects'
BEGIN;
SELECT pg_temp.expect_error('c0000000-0000-4000-8000-00000000000c',
  $q$SELECT * FROM public.community_moderation_queue(10)$q$,
  '42501', 'non-moderator reading the queue');
SELECT pg_temp.expect_error('c0000000-0000-4000-8000-00000000000c',
  $q$SELECT public.resolve_community_report(
     (SELECT id FROM public.community_reports LIMIT 1), 'dismiss', NULL)$q$,
  '42501', 'non-moderator resolving a report');
COMMIT;

DO $$
DECLARE v_report text; v_resolved text;
BEGIN
  ASSERT pg_temp.value_as('f0000000-0000-4000-8000-00000000000f',
    $q$SELECT count(*) FROM public.community_moderation_queue(100)$q$) = '5',
    'FAIL: moderation queue does not list the 5 open reports';
  ASSERT pg_temp.value_as('f0000000-0000-4000-8000-00000000000f',
    $q$SELECT max(open_report_count) FROM public.community_moderation_queue(100)
       WHERE target_type = 'post'$q$) = '3',
    'FAIL: queue does not count reports per target';

  v_report := (SELECT id::text FROM public.community_reports
               WHERE target_type = 'post' LIMIT 1);
  v_resolved := pg_temp.value_as('f0000000-0000-4000-8000-00000000000f',
    format($q$SELECT public.resolve_community_report(%L, 'dismiss', 'not abusive')$q$,
           v_report));
  ASSERT v_resolved = '3', 'FAIL: dismiss did not resolve every report on the post';
  ASSERT (SELECT hidden_at FROM public.community_posts
          WHERE id = '11111111-0000-4000-8000-000000000001') IS NULL,
    'FAIL: dismiss did not restore an auto-hidden post';

  v_report := (SELECT id::text FROM public.community_reports
               WHERE target_type = 'message' LIMIT 1);
  PERFORM pg_temp.value_as('f0000000-0000-4000-8000-00000000000f',
    format($q$SELECT public.resolve_community_report(%L, 'suspend_user', 'harassment')$q$,
           v_report));
  ASSERT NOT EXISTS (SELECT 1 FROM public.private_messages
                     WHERE id = '66666666-0000-4000-8000-000000000006'),
    'FAIL: suspend did not remove the reported message';
  ASSERT EXISTS (SELECT 1 FROM public.community_suspensions
                 WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'),
    'FAIL: suspend did not suspend the author';
  ASSERT (SELECT count(*) FROM public.community_reports WHERE status = 'open') = 1,
    'FAIL: the member report should still be open';
END $$;

BEGIN;
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  pg_temp.post_sql('11111111-0000-4000-8000-0000000000a9', 'back again'),
  'NSW03', 'suspended member posting');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.private_messages (conversation_id, sender_id, content)
     VALUES ('44444444-0000-4000-8000-000000000004', auth.uid(), 'hello')$q$,
  'NSW03', 'suspended member messaging');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$INSERT INTO public.private_conversations (participant_one, participant_two)
     VALUES (auth.uid(), 'd0000000-0000-4000-8000-00000000000d')$q$,
  'NSW03', 'suspended member opening a conversation');
SELECT pg_temp.expect_error('a0000000-0000-4000-8000-00000000000a',
  $q$DELETE FROM public.community_suspensions WHERE user_id = auth.uid()$q$,
  '42501', 'member lifting her own suspension');
COMMIT;

DO $$ BEGIN
  ASSERT pg_temp.value_as('f0000000-0000-4000-8000-00000000000f',
    $q$SELECT public.lift_community_suspension('a0000000-0000-4000-8000-00000000000a')$q$)
    = 'true', 'FAIL: moderator could not lift the suspension';
END $$;
BEGIN;
SELECT pg_temp.run_as('a0000000-0000-4000-8000-00000000000a',
  pg_temp.post_sql('11111111-0000-4000-8000-0000000000aa', 'back again, kindly'));
COMMIT;

\echo '--- 9. remove_content hides a comment; member report cannot remove content'
DO $$
DECLARE v_comment text; v_report text;
BEGIN
  v_comment := (SELECT id::text FROM public.community_comments LIMIT 1);
  v_report := pg_temp.value_as('c0000000-0000-4000-8000-00000000000c',
    format($q$SELECT public.report_community_content('comment', %L, 'spam', NULL)$q$,
           v_comment));
  PERFORM pg_temp.value_as('f0000000-0000-4000-8000-00000000000f',
    format($q$SELECT public.resolve_community_report(%L, 'remove_content', NULL)$q$,
           v_report));
  ASSERT (SELECT hidden_reason FROM public.community_comments
          WHERE id = v_comment::uuid) = 'moderator',
    'FAIL: remove_content did not hide the comment';
END $$;
BEGIN;
SELECT pg_temp.expect_error('f0000000-0000-4000-8000-00000000000f',
  format($q$SELECT public.resolve_community_report(%L, 'remove_content', NULL)$q$,
         (SELECT id FROM public.community_reports WHERE target_type = 'user')),
  '22023', 'remove_content on a member report');
COMMIT;

\echo '--- 10. unblocking restores visibility'
BEGIN;
SELECT pg_temp.run_as('b0000000-0000-4000-8000-00000000000b',
  $q$DELETE FROM public.user_blocks WHERE blocked_id = 'a0000000-0000-4000-8000-00000000000a'$q$);
COMMIT;
DO $$ BEGIN
  ASSERT pg_temp.value_as('b0000000-0000-4000-8000-00000000000b',
    $q$SELECT count(*) FROM public.community_posts
       WHERE user_id = 'a0000000-0000-4000-8000-00000000000a'$q$)::int >= 1,
    'FAIL: unblocking did not restore visibility';
END $$;

\echo 'ALL PASSED'
