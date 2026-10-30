-- COMMUNITY USER-GENERATED-CONTENT SAFETY (App Store Review Guideline 1.2)
--
-- Community (posts, comments) and member-to-member private messages are
-- user-generated content. Guideline 1.2 requires an app with UGC to have:
--   (a) a method for filtering objectionable material from being posted,
--   (b) a mechanism to report offensive content and timely responses,
--   (c) the ability to block abusive users,
--   (d) published contact information (app side, not in this migration),
-- plus terms (EULA) the user agrees to that state there is no tolerance for
-- objectionable content or abusive users, and a developer who acts on
-- reports by removing the content and ejecting the user.
--
-- This migration is the server half, so none of it depends on a client
-- behaving:
--
--   1. public.community_blocked_terms + community_text_violation():
--      server-side word filter applied by triggers to posts, comments,
--      their author names, and private messages. Rejected writes raise
--      SQLSTATE NSW01. The list is a table so moderators extend it with an
--      INSERT, no migration or app release needed.
--   2. public.community_terms_acceptances + community_terms_version():
--      posting, commenting, and messaging require acceptance of the
--      current community terms version (NSW02). The app's
--      CommunityTerms.version constant must equal community_terms_version();
--      test/community_safety_contract_test.dart enforces that.
--   3. public.community_suspensions: a suspended member cannot post,
--      comment, start a conversation, or send a message (NSW03). Only
--      moderators (is_admin()) or service_role create rows.
--   4. public.user_blocks: blocking hides the blocked member's posts and
--      comments from the blocker (SELECT policies), and stops comments on
--      each other's posts and private messages in either direction (NSW04).
--   5. public.community_reports + report_community_content(): report a
--      post, comment, private message, or member. The RPC stores a content
--      snapshot so moderators can review a message they cannot otherwise
--      read, is idempotent per reporter and target, is limited to 20
--      reports a day per reporter, and auto-hides a post or comment once
--      3 different members have open reports on it, pending review.
--   6. community_posts/community_comments.hidden_at/hidden_reason (+ a
--      generated is_hidden, which the notifications migration already
--      honours): moderator removal. Hidden rows are invisible to every
--      client (including the author); clients can never set or clear
--      these columns themselves.
--   7. Moderator RPCs, is_admin() only: community_moderation_queue(),
--      resolve_community_report(), lift_community_suspension().
--
-- Enforcement triggers apply only when current_user is a client role
-- (authenticated, anon), the same rule as users_guard_privileged_columns():
-- service_role and SQL Editor sessions keep full access for moderation.
--
-- New SECURITY DEFINER functions are granted to authenticated and
-- service_role only, never anon (see 20261026090000).
--
-- Idempotent: IF NOT EXISTS / CREATE OR REPLACE / guarded DO blocks.
-- Contains no DROP statement except DROP TRIGGER IF EXISTS before each
-- CREATE TRIGGER.

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.community_blocked_terms (
  term text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT community_blocked_terms_term_check
    CHECK (char_length(btrim(term)) BETWEEN 2 AND 60)
);
ALTER TABLE public.community_blocked_terms ENABLE ROW LEVEL SECURITY;
-- No policies: clients never read or write the list; the filter function
-- below is SECURITY DEFINER.
REVOKE ALL ON public.community_blocked_terms FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.community_terms_acceptances (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  terms_version text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, terms_version)
);
ALTER TABLE public.community_terms_acceptances ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.community_suspensions (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text,
  suspended_at timestamptz NOT NULL DEFAULT now(),
  suspended_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.community_suspensions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.user_blocks (
  blocker_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- The name the blocker saw, so "Blocked members" can show something
  -- without a cross-user profile read. Never used for authorization.
  blocked_display_name text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT user_blocks_not_self CHECK (blocker_id <> blocked_id),
  CONSTRAINT user_blocks_display_name_length
    CHECK (blocked_display_name IS NULL OR char_length(blocked_display_name) <= 80)
);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked_id
  ON public.user_blocks(blocked_id);
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.community_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  target_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text NOT NULL,
  details text,
  content_snapshot text,
  status text NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  resolution_action text,
  resolution_note text,
  CONSTRAINT community_reports_target_type_check
    CHECK (target_type IN ('post', 'comment', 'message', 'user')),
  CONSTRAINT community_reports_reason_check
    CHECK (reason IN ('harassment', 'hate', 'sexual', 'violence', 'self_harm',
                      'spam', 'misinformation', 'other')),
  CONSTRAINT community_reports_status_check
    CHECK (status IN ('open', 'actioned', 'dismissed')),
  CONSTRAINT community_reports_resolution_action_check
    CHECK (resolution_action IS NULL OR resolution_action IN
           ('dismiss', 'remove_content', 'suspend_user')),
  CONSTRAINT community_reports_details_length
    CHECK (details IS NULL OR char_length(details) <= 1000),
  CONSTRAINT community_reports_one_per_reporter
    UNIQUE (reporter_id, target_type, target_id)
);
CREATE INDEX IF NOT EXISTS idx_community_reports_open
  ON public.community_reports(created_at)
  WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_community_reports_target
  ON public.community_reports(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_community_reports_target_user_id
  ON public.community_reports(target_user_id);
CREATE INDEX IF NOT EXISTS idx_community_reports_reviewed_by
  ON public.community_reports(reviewed_by);
ALTER TABLE public.community_reports ENABLE ROW LEVEL SECURITY;
-- Reports are created only through report_community_content().
REVOKE INSERT, UPDATE, DELETE ON public.community_reports FROM anon, authenticated;

CREATE INDEX IF NOT EXISTS idx_community_suspensions_suspended_by
  ON public.community_suspensions(suspended_by);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'community_posts'
      AND column_name = 'hidden_at'
  ) THEN
    ALTER TABLE public.community_posts
      ADD COLUMN hidden_at timestamptz,
      ADD COLUMN hidden_reason text;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'community_comments'
      AND column_name = 'hidden_at'
  ) THEN
    ALTER TABLE public.community_comments
      ADD COLUMN hidden_at timestamptz,
      ADD COLUMN hidden_reason text;
  END IF;

  -- 20261022084701_app_wide_notifications.sql already skips notifications
  -- for rows whose (optional) is_hidden is true, and the app's notification
  -- navigator treats is_hidden rows as gone. Derive it from hidden_at so
  -- the two can never disagree, and no client can write it.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'community_posts'
      AND column_name = 'is_hidden'
  ) THEN
    ALTER TABLE public.community_posts
      ADD COLUMN is_hidden boolean GENERATED ALWAYS AS (hidden_at IS NOT NULL) STORED;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'community_comments'
      AND column_name = 'is_hidden'
  ) THEN
    ALTER TABLE public.community_comments
      ADD COLUMN is_hidden boolean GENERATED ALWAYS AS (hidden_at IS NOT NULL) STORED;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 2. RLS on the new tables (initplan form: (select auth.uid()))
-- ---------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'community_terms_acceptances'
      AND policyname = 'Users read their own terms acceptances') THEN
    CREATE POLICY "Users read their own terms acceptances"
      ON public.community_terms_acceptances FOR SELECT TO authenticated
      USING ((select auth.uid()) = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'community_terms_acceptances'
      AND policyname = 'Users record their own terms acceptance') THEN
    CREATE POLICY "Users record their own terms acceptance"
      ON public.community_terms_acceptances FOR INSERT TO authenticated
      WITH CHECK ((select auth.uid()) = user_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'community_suspensions'
      AND policyname = 'Users read their own suspension') THEN
    CREATE POLICY "Users read their own suspension"
      ON public.community_suspensions FOR SELECT TO authenticated
      USING ((select auth.uid()) = user_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'user_blocks' AND policyname = 'Users read their own blocks') THEN
    CREATE POLICY "Users read their own blocks"
      ON public.user_blocks FOR SELECT TO authenticated
      USING ((select auth.uid()) = blocker_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'user_blocks' AND policyname = 'Users block as themselves') THEN
    CREATE POLICY "Users block as themselves"
      ON public.user_blocks FOR INSERT TO authenticated
      WITH CHECK ((select auth.uid()) = blocker_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'user_blocks' AND policyname = 'Users remove their own blocks') THEN
    CREATE POLICY "Users remove their own blocks"
      ON public.user_blocks FOR DELETE TO authenticated
      USING ((select auth.uid()) = blocker_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'community_reports'
      AND policyname = 'Reporters read their own reports') THEN
    CREATE POLICY "Reporters read their own reports"
      ON public.community_reports FOR SELECT TO authenticated
      USING ((select auth.uid()) = reporter_id);
  END IF;
END $$;

REVOKE UPDATE ON public.community_terms_acceptances FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.community_suspensions FROM anon, authenticated;
REVOKE UPDATE ON public.user_blocks FROM anon, authenticated;
REVOKE ALL ON public.community_terms_acceptances, public.community_suspensions,
  public.user_blocks, public.community_reports FROM anon;

-- ---------------------------------------------------------------------
-- 3. Visibility: hidden content and blocked authors
-- ---------------------------------------------------------------------
-- The existing SELECT policies are USING (true). Inline NOT EXISTS (not a
-- function) so the planner can use the user_blocks primary key; the
-- user_blocks read here passes its own "read own blocks" policy because it
-- only looks at the viewer's own rows.

ALTER POLICY "Users can read all community_posts" ON public.community_posts
  USING (
    hidden_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.user_blocks b
      WHERE b.blocker_id = (select auth.uid())
        AND b.blocked_id = community_posts.user_id
    )
  );

ALTER POLICY "Users can read all community_comments" ON public.community_comments
  USING (
    hidden_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.user_blocks b
      WHERE b.blocker_id = (select auth.uid())
        AND b.blocked_id = community_comments.user_id
    )
  );

-- ---------------------------------------------------------------------
-- 4. Helper functions
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.community_terms_version()
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $$ SELECT '2026-10-30'::text $$;

-- Normalizes text for matching: lower case; Arabic diacritics and tatweel
-- removed; alef/yaa/taa-marbuta variants folded; every run of characters
-- that is not a Latin letter, digit, or Arabic letter becomes one space;
-- padded with spaces so whole-word matching is a plain position() check.
CREATE OR REPLACE FUNCTION public.community_normalize_text(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $$
  SELECT ' ' || btrim(regexp_replace(
    translate(
      regexp_replace(lower(coalesce(p_text, '')), '[ً-ْـ]', '', 'g'),
      'أإآٱىة',
      'اااايه'
    ),
    '[^a-z0-9ء-ي]+', ' ', 'g'
  )) || ' '
$$;

-- Returns the first blocked term found in p_text (whole words), or NULL.
CREATE OR REPLACE FUNCTION public.community_text_violation(p_text text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT t.term
  FROM public.community_blocked_terms t
  WHERE position(public.community_normalize_text(t.term)
                 IN public.community_normalize_text(p_text)) > 0
  LIMIT 1
$$;

-- True when the caller and p_other have blocked each other in either
-- direction. Only ever answers about the caller's own relationships.
CREATE OR REPLACE FUNCTION public.community_blocked_with(p_other uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_blocks b
    WHERE (b.blocker_id = auth.uid() AND b.blocked_id = p_other)
       OR (b.blocker_id = p_other AND b.blocked_id = auth.uid())
  )
$$;

-- Raises the right NSW0x error when the caller may not write community
-- content right now. Reads only the caller's own rows, so SECURITY INVOKER
-- is enough (RLS: read own acceptance / suspension).
CREATE OR REPLACE FUNCTION public.community_assert_can_write()
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.community_suspensions s WHERE s.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'community_suspended' USING ERRCODE = 'NSW03';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.community_terms_acceptances a
    WHERE a.user_id = auth.uid()
      AND a.terms_version = public.community_terms_version()
  ) THEN
    RAISE EXCEPTION 'community_terms_not_accepted' USING ERRCODE = 'NSW02';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.community_assert_clean(VARIADIC p_texts text[])
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $$
DECLARE
  v_text text;
BEGIN
  FOREACH v_text IN ARRAY p_texts LOOP
    IF public.community_text_violation(v_text) IS NOT NULL THEN
      RAISE EXCEPTION 'community_content_rejected' USING ERRCODE = 'NSW01';
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Write-boundary triggers (client roles only)
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.community_posts_guard_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER -- must see the CALLER's role in current_user
SET search_path TO ''
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.hidden_at IS NOT NULL OR NEW.hidden_reason IS NOT NULL THEN
      RAISE EXCEPTION 'community moderation columns cannot be set by the client'
        USING ERRCODE = '42501';
    END IF;
  ELSIF NEW.hidden_at IS DISTINCT FROM OLD.hidden_at
     OR NEW.hidden_reason IS DISTINCT FROM OLD.hidden_reason THEN
    RAISE EXCEPTION 'community moderation columns cannot be changed by the client'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public.community_assert_can_write();
  PERFORM public.community_assert_clean(NEW.title, NEW.content, NEW.author_name,
                                        NEW.tags::text);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.community_comments_guard_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $$
DECLARE
  v_post_author uuid;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.hidden_at IS NOT NULL OR NEW.hidden_reason IS NOT NULL THEN
      RAISE EXCEPTION 'community moderation columns cannot be set by the client'
        USING ERRCODE = '42501';
    END IF;
  ELSIF NEW.hidden_at IS DISTINCT FROM OLD.hidden_at
     OR NEW.hidden_reason IS DISTINCT FROM OLD.hidden_reason THEN
    RAISE EXCEPTION 'community moderation columns cannot be changed by the client'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public.community_assert_can_write();

  -- Visible-post lookup under the caller's own RLS: a post that is hidden
  -- or whose author the caller blocked is simply not found here.
  SELECT p.user_id INTO v_post_author
  FROM public.community_posts p WHERE p.id = NEW.post_id;
  IF v_post_author IS NOT NULL AND v_post_author <> NEW.user_id
     AND public.community_blocked_with(v_post_author) THEN
    RAISE EXCEPTION 'community_blocked' USING ERRCODE = 'NSW04';
  END IF;

  PERFORM public.community_assert_clean(NEW.content, NEW.author_name);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.private_conversations_guard_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $$
DECLARE
  v_other uuid;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.community_suspensions s WHERE s.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'community_suspended' USING ERRCODE = 'NSW03';
  END IF;
  v_other := CASE WHEN NEW.participant_one = auth.uid()
                  THEN NEW.participant_two ELSE NEW.participant_one END;
  IF public.community_blocked_with(v_other) THEN
    RAISE EXCEPTION 'community_blocked' USING ERRCODE = 'NSW04';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.private_messages_guard_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $$
DECLARE
  v_other uuid;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  -- Recipients marking messages read (UPDATE of is_read only) are never
  -- blocked; only a change of content is checked on UPDATE.
  IF TG_OP = 'UPDATE' AND NEW.content IS NOT DISTINCT FROM OLD.content THEN
    RETURN NEW;
  END IF;

  PERFORM public.community_assert_can_write();

  SELECT CASE WHEN c.participant_one = auth.uid()
              THEN c.participant_two ELSE c.participant_one END
    INTO v_other
  FROM public.private_conversations c WHERE c.id = NEW.conversation_id;
  IF v_other IS NOT NULL AND public.community_blocked_with(v_other) THEN
    RAISE EXCEPTION 'community_blocked' USING ERRCODE = 'NSW04';
  END IF;

  PERFORM public.community_assert_clean(NEW.content);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_community_posts_guard_write ON public.community_posts;
CREATE TRIGGER trg_community_posts_guard_write
  BEFORE INSERT OR UPDATE ON public.community_posts
  FOR EACH ROW EXECUTE FUNCTION public.community_posts_guard_write();

DROP TRIGGER IF EXISTS trg_community_comments_guard_write ON public.community_comments;
CREATE TRIGGER trg_community_comments_guard_write
  BEFORE INSERT OR UPDATE ON public.community_comments
  FOR EACH ROW EXECUTE FUNCTION public.community_comments_guard_write();

DROP TRIGGER IF EXISTS trg_private_conversations_guard_insert ON public.private_conversations;
CREATE TRIGGER trg_private_conversations_guard_insert
  BEFORE INSERT ON public.private_conversations
  FOR EACH ROW EXECUTE FUNCTION public.private_conversations_guard_insert();

DROP TRIGGER IF EXISTS trg_private_messages_guard_write ON public.private_messages;
CREATE TRIGGER trg_private_messages_guard_write
  BEFORE INSERT OR UPDATE ON public.private_messages
  FOR EACH ROW EXECUTE FUNCTION public.private_messages_guard_write();

-- ---------------------------------------------------------------------
-- 6. Reporting
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.report_community_content(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_details text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_reporter uuid := auth.uid();
  v_target_user uuid;
  v_snapshot text;
  v_report_id uuid;
  v_open_reporters integer;
BEGIN
  IF v_reporter IS NULL THEN
    RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501';
  END IF;
  IF p_target_type NOT IN ('post', 'comment', 'message', 'user') THEN
    RAISE EXCEPTION 'unknown report target type' USING ERRCODE = '22023';
  END IF;

  IF p_target_type = 'post' THEN
    SELECT p.user_id, left(p.title || E'\n\n' || p.content, 2000)
      INTO v_target_user, v_snapshot
    FROM public.community_posts p WHERE p.id = p_target_id;
  ELSIF p_target_type = 'comment' THEN
    SELECT c.user_id, left(c.content, 2000)
      INTO v_target_user, v_snapshot
    FROM public.community_comments c WHERE c.id = p_target_id;
  ELSIF p_target_type = 'message' THEN
    -- Only a participant can report a message, and only one she received.
    SELECT m.sender_id, left(m.content, 2000)
      INTO v_target_user, v_snapshot
    FROM public.private_messages m
    JOIN public.private_conversations c ON c.id = m.conversation_id
    WHERE m.id = p_target_id
      AND v_reporter IN (c.participant_one, c.participant_two)
      AND m.sender_id <> v_reporter;
  ELSE
    SELECT u.id INTO v_target_user FROM auth.users u WHERE u.id = p_target_id;
  END IF;

  IF v_target_user IS NULL THEN
    RAISE EXCEPTION 'report target not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_target_user = v_reporter THEN
    RAISE EXCEPTION 'cannot report your own content' USING ERRCODE = '22023';
  END IF;

  -- Idempotent: a repeat report of the same target returns the first one.
  SELECT r.id INTO v_report_id FROM public.community_reports r
  WHERE r.reporter_id = v_reporter
    AND r.target_type = p_target_type AND r.target_id = p_target_id;
  IF v_report_id IS NOT NULL THEN
    RETURN v_report_id;
  END IF;

  IF (SELECT count(*) FROM public.community_reports r
      WHERE r.reporter_id = v_reporter
        AND r.created_at > now() - interval '1 day') >= 20 THEN
    RAISE EXCEPTION 'report limit reached' USING ERRCODE = 'NSW05';
  END IF;

  INSERT INTO public.community_reports
    (reporter_id, target_type, target_id, target_user_id, reason, details,
     content_snapshot)
  VALUES
    (v_reporter, p_target_type, p_target_id, v_target_user, p_reason,
     nullif(left(btrim(coalesce(p_details, '')), 1000), ''), v_snapshot)
  ON CONFLICT (reporter_id, target_type, target_id) DO NOTHING
  RETURNING id INTO v_report_id;

  IF v_report_id IS NULL THEN -- lost a race with the same reporter
    SELECT r.id INTO v_report_id FROM public.community_reports r
    WHERE r.reporter_id = v_reporter
      AND r.target_type = p_target_type AND r.target_id = p_target_id;
    RETURN v_report_id;
  END IF;

  -- Auto-hide pending review once 3 different members report it.
  IF p_target_type IN ('post', 'comment') THEN
    SELECT count(DISTINCT r.reporter_id) INTO v_open_reporters
    FROM public.community_reports r
    WHERE r.target_type = p_target_type AND r.target_id = p_target_id
      AND r.status = 'open';
    IF v_open_reporters >= 3 THEN
      IF p_target_type = 'post' THEN
        UPDATE public.community_posts
          SET hidden_at = now(), hidden_reason = 'auto_reports'
          WHERE id = p_target_id AND hidden_at IS NULL;
      ELSE
        UPDATE public.community_comments
          SET hidden_at = now(), hidden_reason = 'auto_reports'
          WHERE id = p_target_id AND hidden_at IS NULL;
      END IF;
    END IF;
  END IF;

  RETURN v_report_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 7. Moderation (is_admin() only)
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.community_moderation_queue(p_limit integer DEFAULT 100)
RETURNS TABLE (
  report_id uuid,
  created_at timestamptz,
  target_type text,
  target_id uuid,
  target_user_id uuid,
  reason text,
  details text,
  content_snapshot text,
  open_report_count bigint,
  target_hidden boolean,
  target_user_suspended boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'moderators only' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT r.id, r.created_at, r.target_type, r.target_id, r.target_user_id,
         r.reason, r.details, r.content_snapshot,
         count(*) OVER (PARTITION BY r.target_type, r.target_id),
         CASE r.target_type
           WHEN 'post' THEN EXISTS (SELECT 1 FROM public.community_posts p
                                    WHERE p.id = r.target_id AND p.hidden_at IS NOT NULL)
           WHEN 'comment' THEN EXISTS (SELECT 1 FROM public.community_comments c
                                       WHERE c.id = r.target_id AND c.hidden_at IS NOT NULL)
           ELSE false
         END,
         EXISTS (SELECT 1 FROM public.community_suspensions s
                 WHERE s.user_id = r.target_user_id)
  FROM public.community_reports r
  WHERE r.status = 'open'
  ORDER BY r.created_at ASC
  LIMIT greatest(1, least(coalesce(p_limit, 100), 500));
END;
$$;

-- Resolves every open report on the same target as p_report_id.
--   dismiss        - no action; restores a post/comment that was only
--                    auto-hidden by reports.
--   remove_content - hides the post/comment (or deletes the private
--                    message). Not valid for a 'user' report.
--   suspend_user   - removes the content (when there is content) and
--                    suspends the author from posting and messaging.
CREATE OR REPLACE FUNCTION public.resolve_community_report(
  p_report_id uuid,
  p_action text,
  p_note text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_report public.community_reports%ROWTYPE;
  v_resolved integer;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'moderators only' USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN ('dismiss', 'remove_content', 'suspend_user') THEN
    RAISE EXCEPTION 'unknown moderation action' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_report FROM public.community_reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'report not found' USING ERRCODE = 'P0002';
  END IF;
  IF p_action = 'remove_content' AND v_report.target_type = 'user' THEN
    RAISE EXCEPTION 'a member report has no content to remove; use suspend_user'
      USING ERRCODE = '22023';
  END IF;

  IF p_action = 'dismiss' THEN
    IF v_report.target_type = 'post' THEN
      UPDATE public.community_posts SET hidden_at = NULL, hidden_reason = NULL
      WHERE id = v_report.target_id AND hidden_reason = 'auto_reports';
    ELSIF v_report.target_type = 'comment' THEN
      UPDATE public.community_comments SET hidden_at = NULL, hidden_reason = NULL
      WHERE id = v_report.target_id AND hidden_reason = 'auto_reports';
    END IF;
  ELSE
    IF v_report.target_type = 'post' THEN
      UPDATE public.community_posts
        SET hidden_at = coalesce(hidden_at, now()), hidden_reason = 'moderator'
      WHERE id = v_report.target_id;
    ELSIF v_report.target_type = 'comment' THEN
      UPDATE public.community_comments
        SET hidden_at = coalesce(hidden_at, now()), hidden_reason = 'moderator'
      WHERE id = v_report.target_id;
    ELSIF v_report.target_type = 'message' THEN
      DELETE FROM public.private_messages WHERE id = v_report.target_id;
    END IF;

    IF p_action = 'suspend_user' AND v_report.target_user_id IS NOT NULL THEN
      INSERT INTO public.community_suspensions (user_id, reason, suspended_by)
      VALUES (v_report.target_user_id, nullif(btrim(coalesce(p_note, '')), ''),
              auth.uid())
      ON CONFLICT (user_id) DO NOTHING;
    END IF;
  END IF;

  UPDATE public.community_reports
    SET status = CASE WHEN p_action = 'dismiss' THEN 'dismissed' ELSE 'actioned' END,
        reviewed_at = now(),
        reviewed_by = auth.uid(),
        resolution_action = p_action,
        resolution_note = nullif(left(btrim(coalesce(p_note, '')), 1000), '')
  WHERE target_type = v_report.target_type
    AND target_id = v_report.target_id
    AND status = 'open';
  GET DIAGNOSTICS v_resolved = ROW_COUNT;
  RETURN v_resolved;
END;
$$;

CREATE OR REPLACE FUNCTION public.lift_community_suspension(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'moderators only' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.community_suspensions WHERE user_id = p_user_id;
  RETURN FOUND;
END;
$$;

-- ---------------------------------------------------------------------
-- 8. Grants: signed-in clients only, never anon
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.community_terms_version()',
    'public.community_normalize_text(text)',
    'public.community_text_violation(text)',
    'public.community_blocked_with(uuid)',
    'public.community_assert_can_write()',
    'public.community_assert_clean(text[])',
    'public.report_community_content(text, uuid, text, text)',
    'public.community_moderation_queue(integer)',
    'public.resolve_community_report(uuid, text, text)',
    'public.lift_community_suspension(uuid)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_sig);
  END LOOP;

  -- Trigger functions: never callable over RPC (EXECUTE is only checked
  -- at CREATE TRIGGER time).
  FOREACH v_sig IN ARRAY ARRAY[
    'public.community_posts_guard_write()',
    'public.community_comments_guard_write()',
    'public.private_conversations_guard_insert()',
    'public.private_messages_guard_write()'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_sig);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 9. Starter filter list (whole words, after normalization)
-- ---------------------------------------------------------------------
-- Deliberately short and unambiguous: slurs and explicit sexual insults
-- that have no innocent use in a women's health and support community.
-- Moderators extend it with
--   INSERT INTO public.community_blocked_terms (term) VALUES ('...');

INSERT INTO public.community_blocked_terms (term) VALUES
  ('fuck'), ('fucking'), ('fucker'), ('motherfucker'), ('cunt'), ('whore'),
  ('slut'), ('bitch'), ('nigger'), ('nigga'), ('faggot'), ('retard'),
  ('kike'), ('spic'), ('chink'), ('tranny'), ('dickhead'), ('asshole'),
  ('kill yourself'), ('kys'),
  ('شرموطة'), ('شرموطه'), ('قحبة'), ('قحبه'), ('عاهرة'), ('منيوك'),
  ('منيوكة'), ('كس امك'), ('كسمك'), ('كس اختك'), ('زبي'), ('ابن الزانية'),
  ('ابن القحبة'), ('ابن الشرموطة'), ('يلعن دينك'), ('انتحري'), ('اقتلي نفسك')
ON CONFLICT (term) DO NOTHING;
