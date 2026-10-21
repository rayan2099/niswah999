-- SEC-012 regression: a client can never grant herself admin or premium on
-- public.users, ordinary profile writes still work, service_role keeps its
-- admin path, and other users' rows stay invisible.
-- Guards supabase/migrations/20261021090000_users_privileged_columns_guard.sql.
--
-- Run only on a scratch database built by run_sql_checks.sh. Exits non-zero
-- (ON_ERROR_STOP) on the first failed assertion; prints ALL PASSED otherwise.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;

-- Signup path (auth.users trigger -> create_user_profile/handle_new_user,
-- SECURITY DEFINER) must still create the profile rows.
INSERT INTO auth.users (id, email) VALUES
  ('a0000000-0000-4000-8000-00000000000a', 'a@example.invalid'),
  ('b0000000-0000-4000-8000-00000000000b', 'b@example.invalid');
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM public.users) = 2,
    'FAIL: signup trigger no longer creates public.users rows';
END $$;
INSERT INTO public.cycle_entries (user_id, date)
VALUES ('a0000000-0000-4000-8000-00000000000a', current_date);

-- Runs p_sql as `authenticated` user p_uid and requires SQLSTATE 42501.
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

\echo '--- 1. self-promotion to admin is rejected'
BEGIN;
SELECT pg_temp.expect_denied('b0000000-0000-4000-8000-00000000000b',
  $q$UPDATE public.users SET role = 'admin' WHERE id = auth.uid()$q$,
  'self-promotion to admin');
COMMIT;
DO $$ BEGIN
  ASSERT (SELECT role FROM public.users
          WHERE id = 'b0000000-0000-4000-8000-00000000000b') = 'user',
    'FAIL: role changed';
END $$;

\echo '--- 2. premium self-grant is rejected'
BEGIN;
SELECT pg_temp.expect_denied('b0000000-0000-4000-8000-00000000000b',
  $q$UPDATE public.users SET premium_expires_at = now() + interval '10 years'
     WHERE id = auth.uid()$q$,
  'premium_expires_at self-grant');
SELECT pg_temp.expect_denied('b0000000-0000-4000-8000-00000000000b',
  $q$UPDATE public.users SET premium_status = NOT premium_status
     WHERE id = auth.uid()$q$,
  'premium_status change');
COMMIT;

\echo '--- 3. a client cannot delete and re-insert her row to reset premium'
-- An entitlement the server revoked must survive: with premium_status
-- defaulting to true, delete + insert-with-defaults would restore it.
BEGIN;
SET LOCAL ROLE service_role;
UPDATE public.users SET premium_status = false
WHERE id = 'b0000000-0000-4000-8000-00000000000b';
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'b0000000-0000-4000-8000-00000000000b';
DO $$ DECLARE n int; BEGIN
  DELETE FROM public.users WHERE id = auth.uid();
  GET DIAGNOSTICS n = ROW_COUNT;
  ASSERT n = 0, 'FAIL: client deleted her own users row';
END $$;
COMMIT;
-- Even with the row gone, a client insert is refused.
DELETE FROM public.users WHERE id = 'b0000000-0000-4000-8000-00000000000b';
BEGIN;
SELECT pg_temp.expect_denied('b0000000-0000-4000-8000-00000000000b',
  $q$INSERT INTO public.users (id) VALUES (auth.uid())$q$,
  'client insert of a users row');
SELECT pg_temp.expect_denied('b0000000-0000-4000-8000-00000000000b',
  $q$INSERT INTO public.users (id, premium_expires_at)
     VALUES (auth.uid(), now() + interval '1 year')$q$,
  'insert with premium_expires_at');
COMMIT;
-- Restore B's profile the way the server would.
INSERT INTO public.users (id) VALUES ('b0000000-0000-4000-8000-00000000000b');

\echo '--- 4. ordinary profile updates still work'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'b0000000-0000-4000-8000-00000000000b';
UPDATE public.users SET display_name = 'Maryam', anonymous_mode = true,
  onboarding_completed = true, madhhab_selection_state = 'selected',
  madhhab = 'hanafi', community_language = 'ar', language = 'en'
WHERE id = auth.uid();
-- Re-writing a privileged column with its CURRENT value is not a change.
UPDATE public.users SET role = 'user' WHERE id = auth.uid();
COMMIT;
DO $$ BEGIN
  ASSERT (SELECT display_name = 'Maryam' AND madhhab = 'hanafi'
            AND onboarding_completed
          FROM public.users WHERE id = 'b0000000-0000-4000-8000-00000000000b'),
    'FAIL: ordinary profile update did not persist';
END $$;

\echo '--- 5. service_role can still change role'
BEGIN;
SET LOCAL ROLE service_role;
UPDATE public.users SET role = 'admin'
WHERE id = 'a0000000-0000-4000-8000-00000000000a';
UPDATE public.users SET role = 'user'
WHERE id = 'a0000000-0000-4000-8000-00000000000a';
COMMIT;

\echo '--- 6. another user''s rows stay invisible and untouchable'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'b0000000-0000-4000-8000-00000000000b';
DO $$ DECLARE n int; BEGIN
  ASSERT (SELECT count(*) FROM public.users) = 1, 'FAIL: B sees other users';
  ASSERT (SELECT count(*) FROM public.cycle_entries) = 0,
    'FAIL: B sees A''s cycle_entries';
  UPDATE public.users SET display_name = 'x'
  WHERE id = 'a0000000-0000-4000-8000-00000000000a';
  GET DIAGNOSTICS n = ROW_COUNT;
  ASSERT n = 0, 'FAIL: B updated A''s users row';
END $$;
COMMIT;

\echo '--- 7. account deletion (delete_my_account, SECURITY DEFINER) still works'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'b0000000-0000-4000-8000-00000000000b';
SELECT public.delete_my_account();
COMMIT;
DO $$ BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM public.users
                     WHERE id = 'b0000000-0000-4000-8000-00000000000b'),
    'FAIL: delete_my_account no longer removes the users row';
END $$;

\echo 'ALL PASSED'
