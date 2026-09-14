-- Fixes a real conflict discovered immediately after applying
-- 20260914120000_madhhab_authority_state.sql: production's `public.users`
-- table already carried a constraint, `users_madhhab_check`, requiring
-- `madhhab` to be one of the UPPERCASE literals 'HANAFI'/'MALIKI'/
-- 'SHAFII'/'HANBALI' — undocumented in any migration file this session
-- could find (not present in supabase/migrations/, migrations_archive/, or
-- the canonical baseline snapshot), so it was not visible before writing
-- the previous migration.
--
-- The application (`Madhhab.hanafi.name` etc., Dart) has only ever used
-- lowercase enum names, and this wave's new `users_madhhab_value_check`
-- constraint correctly validates against `lower(madhhab) IN (...)`. Left
-- in place, `users_madhhab_check` would have silently rejected every real
-- write `MadhhabController.selectMadhhab()` makes (a lowercase value)
-- with a constraint-violation error, the moment any user actually
-- selected a madhhab after this wave's other changes went live — a
-- production-breaking regression caught before rollout, not after.
--
-- Superseded entirely by `users_madhhab_value_check` (added in the
-- previous migration), which already validates correctly. Dropping the
-- old, conflicting, undocumented constraint; adding nothing new.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_madhhab_check'
  ) THEN
    ALTER TABLE public.users DROP CONSTRAINT users_madhhab_check;
  END IF;
END $$;
