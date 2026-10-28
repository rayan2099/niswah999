-- Pre-launch grant check: anon cannot call SECURITY DEFINER RPCs, nobody
-- can call trigger functions over RPC, signed-in users keep their RPCs, and
-- triggers still fire for a role that lacks EXECUTE on them.
-- Guards supabase/migrations/20261026090000_revoke_anon_security_definer_execute.sql.
--
-- Run only on a scratch database built by run_sql_checks.sh. Exits non-zero
-- (ON_ERROR_STOP) on the first failed assertion; prints ALL PASSED otherwise.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;

DO $$
DECLARE
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.check_and_increment_ai_rate_limit(text, integer, integer)',
    'public.delete_my_account()',
    'public.get_active_kb_snapshot()',
    'public.retrieve_knowledge_v1(text, text, text, text, integer)'
  ] LOOP
    ASSERT NOT has_function_privilege('anon', v_sig, 'EXECUTE'),
      format('FAIL: anon can still execute %s', v_sig);
    ASSERT has_function_privilege('authenticated', v_sig, 'EXECUTE'),
      format('FAIL: authenticated lost EXECUTE on %s', v_sig);
    ASSERT has_function_privilege('service_role', v_sig, 'EXECUTE'),
      format('FAIL: service_role lost EXECUTE on %s', v_sig);
  END LOOP;

  FOREACH v_sig IN ARRAY ARRAY[
    'public.bleeding_observations_validate_insert()',
    'public.create_user_profile()',
    'public.handle_new_user()'
  ] LOOP
    ASSERT NOT has_function_privilege('anon', v_sig, 'EXECUTE'),
      format('FAIL: anon can still execute trigger function %s', v_sig);
    ASSERT NOT has_function_privilege('authenticated', v_sig, 'EXECUTE'),
      format('FAIL: authenticated can still execute trigger function %s', v_sig);
  END LOOP;

  -- RLS policies granted TO public call these; anon must still evaluate them.
  ASSERT has_function_privilege('anon', 'public.is_admin()', 'EXECUTE'),
    'FAIL: anon lost EXECUTE on is_admin() (RLS policies for anon would error)';
  ASSERT has_function_privilege('anon', 'public.is_conversation_participant(uuid)', 'EXECUTE'),
    'FAIL: anon lost EXECUTE on is_conversation_participant()';

  ASSERT (SELECT proconfig @> ARRAY['search_path=public'] FROM pg_proc
          WHERE oid = 'public.set_updated_at()'::regprocedure),
    'FAIL: set_updated_at() search_path not pinned';
  ASSERT (SELECT proconfig @> ARRAY['search_path=public'] FROM pg_proc
          WHERE oid = 'public.touch_private_conversation()'::regprocedure),
    'FAIL: touch_private_conversation() search_path not pinned';
END $$;

-- Signup still creates the profile when the inserting role has no EXECUTE
-- on the trigger functions (Postgres checks EXECUTE only at CREATE TRIGGER).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'seccheck_signup') THEN
    CREATE ROLE seccheck_signup NOLOGIN;
  END IF;
END $$;
GRANT USAGE ON SCHEMA auth TO seccheck_signup;
GRANT INSERT ON auth.users TO seccheck_signup;
SET ROLE seccheck_signup;
INSERT INTO auth.users (id, email)
VALUES ('c0000000-0000-4000-8000-00000000000c', 'c@example.invalid');
RESET ROLE;
DO $$ BEGIN
  ASSERT EXISTS (SELECT 1 FROM public.users
                 WHERE id = 'c0000000-0000-4000-8000-00000000000c'),
    'FAIL: signup trigger no longer creates the public.users row';
END $$;

-- anon calling a revoked RPC is refused with insufficient_privilege.
DO $$
BEGIN
  EXECUTE 'SET LOCAL ROLE anon';
  BEGIN
    PERFORM public.get_active_kb_snapshot();
    RAISE EXCEPTION 'FAIL: anon executed get_active_kb_snapshot()';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'RESET ROLE';
END $$;

-- Roles are cluster-wide: leave nothing behind for the next scratch DB.
REVOKE ALL ON auth.users FROM seccheck_signup;
REVOKE ALL ON SCHEMA auth FROM seccheck_signup;
DROP ROLE seccheck_signup;

\echo ALL PASSED
