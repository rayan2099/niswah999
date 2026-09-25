-- ACCOUNT DELETION: ai_rate_limit_counters rows must not outlive the user.
--
-- Found while planning the cleanup of an accidentally-created production
-- test account (acceptance-testing wave, 2026-09-25). Every user-owned
-- table in `public` references public.users / auth.users with
-- ON DELETE CASCADE, so deleting the Auth user (the app's own
-- `delete_my_account()` is exactly `delete from auth.users where id =
-- auth.uid()`, and the Dashboard/Admin API do the same) removes it all —
-- EXCEPT `ai_rate_limit_counters.user_id`, which was created without a
-- foreign key. Verified against a live local Postgres: after the app's own
-- deletion path, every cascading table reached 0 rows and this table kept
-- one row attributable to the deleted user's UUID (removed only by the
-- sampled 1-in-50 retention sweep, and only for old windows).
--
-- The rows hold no message content (user id, function name, window start,
-- request count), but a user-attributable row that survives account
-- deletion is not what deletion promises. A trigger on auth.users is used
-- rather than a new foreign key deliberately:
--   * it covers EVERY deletion path (app RPC, Dashboard, Admin API), and
--   * adding a validated FK could fail against pre-existing orphaned rows
--     in a live database, blocking the migration.
-- The one-time DELETE below removes counters already orphaned by earlier
-- account deletions.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'ai_rate_limit_counters'
  ) THEN

    CREATE OR REPLACE FUNCTION public.delete_ai_rate_limit_counters_for_deleted_user()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $fn$
    BEGIN
      DELETE FROM public.ai_rate_limit_counters WHERE user_id = OLD.id;
      RETURN OLD;
    END;
    $fn$;

    REVOKE ALL ON FUNCTION public.delete_ai_rate_limit_counters_for_deleted_user()
      FROM PUBLIC, anon, authenticated;

    DROP TRIGGER IF EXISTS ai_rate_limit_counters_delete_with_user ON auth.users;
    CREATE TRIGGER ai_rate_limit_counters_delete_with_user
      AFTER DELETE ON auth.users
      FOR EACH ROW
      EXECUTE FUNCTION public.delete_ai_rate_limit_counters_for_deleted_user();

    DELETE FROM public.ai_rate_limit_counters c
    WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = c.user_id);

  END IF;
END $$;
