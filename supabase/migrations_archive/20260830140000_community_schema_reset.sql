-- =========================================================================
-- COMMUNITY SCHEMA RESET
-- =========================================================================
-- The live community tables had drifted completely from what the Flutter
-- client and schema.sql expect: they were named community_post_comments /
-- community_post_likes (not community_comments / community_likes), and
-- community_posts itself was missing title/category/tags/is_anonymous/
-- author_name and used author_id instead of user_id. Every comment insert
-- and like toggle from the app was silently failing against these tables,
-- and CommunityRepositoryImpl.getPosts()'s `on PostgrestException` fallback
-- was masking it by serving canned demo posts instead of surfacing an error.
--
-- All three tables were confirmed empty (0 rows) before this migration, so
-- a drop-and-recreate is safe here — no user data exists yet to migrate.
--
-- This supersedes the never-applied 20260829120000_community_likes.sql and
-- 20260829130000_community_text_only_constraints.sql, folding both into a
-- single consistent definition below.
-- =========================================================================

DROP TABLE IF EXISTS community_post_likes CASCADE;
DROP TABLE IF EXISTS community_post_comments CASCADE;
DROP TABLE IF EXISTS community_posts CASCADE;

CREATE TABLE community_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  author_name TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('support','prayer','wellness','parenting','fertility','general')),
  tags JSONB DEFAULT '[]',
  is_anonymous BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT community_posts_title_length CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  CONSTRAINT community_posts_content_length CHECK (char_length(btrim(content)) BETWEEN 1 AND 1000)
);

CREATE TABLE community_comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  author_name TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT community_comments_content_length CHECK (char_length(btrim(content)) BETWEEN 1 AND 500)
);

CREATE TABLE community_likes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT unique_post_like UNIQUE (post_id, user_id)
);

CREATE INDEX idx_community_posts_user_id_created_at
  ON community_posts(user_id, created_at DESC);
CREATE INDEX idx_community_posts_category_created_at
  ON community_posts(category, created_at DESC);
CREATE INDEX idx_community_comments_post_id_created_at
  ON community_comments(post_id, created_at ASC);
CREATE INDEX idx_community_likes_post_id ON community_likes(post_id);
CREATE INDEX idx_community_likes_user_id ON community_likes(user_id);

ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read all community_posts" ON community_posts
  FOR SELECT USING (true);
CREATE POLICY "Users can create their own community_posts" ON community_posts
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own community_posts" ON community_posts
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own community_posts" ON community_posts
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can read all community_comments" ON community_comments
  FOR SELECT USING (true);
CREATE POLICY "Users can create comments on visible posts" ON community_comments
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM community_posts cp
      WHERE cp.id = community_comments.post_id
    )
  );
CREATE POLICY "Users can update their own community_comments" ON community_comments
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own community_comments" ON community_comments
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can read all community_likes" ON community_likes
  FOR SELECT USING (true);
CREATE POLICY "Users can like as themselves" ON community_likes
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can remove their own like" ON community_likes
  FOR DELETE USING (auth.uid() = user_id);
