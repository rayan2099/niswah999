-- COMMUNITY LANGUAGE: public.users.community_language, public.community_posts.language
--
-- Requirement 4: Niswah serves both Arabic- and English-speaking users,
-- and Community needs an explicit, persistent choice of which language
-- community to browse — separate from the app's interface language
-- (`AppLocaleController`, local-only, 'niswah_arabic' SharedPreferences
-- key). This migration adds:
--
--   1. `public.users.community_language` — the user's own preference
--      (nullable: unset until she's asked once, per the gate in
--      `lib/features/community/presentation/widgets/community_language_gate.dart`).
--   2. `public.community_posts.language` — which community a given post
--      belongs to.
--
-- No column is added to `community_comments`/`community_likes` — a
-- comment inherits its community via its post's `post_id` foreign key,
-- so it can never drift independently from its parent post.
--
-- NULLABLE-FIRST BY DESIGN (adversarial-review correction, 2026-10-07):
-- an earlier draft of this migration defaulted every existing row with
-- no language value to 'ar' and made the column NOT NULL immediately.
-- That default was never a detected fact about any real row — it was an
-- assumption, and a wrong one for a production database that happens to
-- already hold real English-language posts. A live, read-only check
-- against this repo's own production project (`community_posts`,
-- `community_comments`, `community_likes` — all three, via the public
-- SELECT RLS policy already in place) confirmed zero existing rows at
-- the time this correction was written, so there is nothing to mis-tag
-- today — but the migration is written to be safe as a *general*
-- migration, not safe-because-the-table-happened-to-be-empty-right-now.
--
-- `language` is therefore added NULLABLE, with no default and no
-- backfill UPDATE. Application code (`CommunityRepositoryImpl
-- .createPost`, `lib/features/community/data/repositories/
-- community_repository_impl.dart`) always writes an explicit `language`
-- on every insert going forward — confirmed required at the Dart type
-- level (`CommunityPost.language` is a non-nullable, required
-- constructor field) — so no new row is ever written without one, even
-- though the column itself does not yet enforce that.
--
-- Enforcing NOT NULL is deferred to a follow-up migration, to be applied
-- only after confirming live
--   SELECT count(*) FROM community_posts WHERE language IS NULL
-- is zero in whichever environment it's about to run against (it cannot
-- safely be asserted here, for all environments, for all time).
--
-- Guarded (IF EXISTS/IF NOT EXISTS) matching this repo's established
-- pattern (see 20260914120000_madhhab_authority_state.sql).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'users'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'users'
        AND column_name = 'community_language'
    ) THEN
      ALTER TABLE public.users ADD COLUMN community_language TEXT;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'users_community_language_check'
    ) THEN
      ALTER TABLE public.users
        ADD CONSTRAINT users_community_language_check
        CHECK (community_language IS NULL OR community_language IN ('ar', 'en'));
    END IF;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'community_posts'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'community_posts'
        AND column_name = 'language'
    ) THEN
      ALTER TABLE public.community_posts ADD COLUMN language TEXT;
    END IF;

    -- Nullable, no default, no backfill — see the comment block above.

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'community_posts_language_check'
    ) THEN
      ALTER TABLE public.community_posts
        ADD CONSTRAINT community_posts_language_check
        CHECK (language IS NULL OR language IN ('ar', 'en'));
    END IF;

    CREATE INDEX IF NOT EXISTS idx_community_posts_language_category_created_at
      ON public.community_posts(language, category, created_at DESC);
  END IF;
END $$;

-- FOLLOW-UP MIGRATION (not included here, apply only after verifying
-- zero NULLs live in the target environment):
--
--   ALTER TABLE public.community_posts ALTER COLUMN language SET NOT NULL;
