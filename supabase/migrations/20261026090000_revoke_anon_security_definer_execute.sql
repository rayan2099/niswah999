-- Pre-launch: close anonymous access to SECURITY DEFINER functions.
--
-- Supabase's default privileges grant EXECUTE on every new public function
-- directly to anon, authenticated and service_role. The migrations that
-- created the functions below ran `REVOKE ... FROM PUBLIC`, which does not
-- remove those direct grants, so the security advisor (lints 0028/0029)
-- still reports them as callable through /rest/v1/rpc by anyone holding the
-- app's public anon key, signed in or not.
--
-- 1. Signed-in-only RPCs. Each one already rejects or no-ops a null
--    auth.uid(), but anon has no reason to reach them at all. The KB pair
--    is called by the AI Edge Functions with the user's own JWT
--    (role authenticated), so revoking anon leaves that path unchanged and
--    stops unauthenticated scraping of the knowledge base.
--      check_and_increment_ai_rate_limit, delete_my_account,
--      get_active_kb_snapshot, retrieve_knowledge_v1
--
-- 2. Trigger functions. These are only meant to run as triggers; nobody
--    should call them over RPC. Postgres checks EXECUTE on a trigger
--    function only at CREATE TRIGGER time, never when the trigger fires,
--    so signup (auth.users -> create_user_profile/handle_new_user) and
--    bleeding_observations inserts keep working.
--      bleeding_observations_validate_insert, create_user_profile,
--      handle_new_user
--
-- 3. Mutable search_path (lint 0011) on two trigger functions: pin it.
--    can_access_user is left alone on purpose: it is SECURITY INVOKER,
--    every name in it is schema-qualified, and pinning a search_path would
--    stop Postgres from inlining it into the RLS policies that call it on
--    every row.
--
-- is_admin() and is_conversation_participant() keep their anon grant: RLS
-- policies granted TO public call them, so an anon request against those
-- tables must still be able to evaluate them (both return false for anon).
--
-- Every statement is skipped when the function does not exist in an
-- environment, and re-running the migration is a no-op.

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
    IF to_regprocedure(v_sig) IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_sig);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_sig);
    END IF;
  END LOOP;

  FOREACH v_sig IN ARRAY ARRAY[
    'public.bleeding_observations_validate_insert()',
    'public.create_user_profile()',
    'public.handle_new_user()'
  ] LOOP
    IF to_regprocedure(v_sig) IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_sig);
    END IF;
  END LOOP;

  IF to_regprocedure('public.set_updated_at()') IS NOT NULL THEN
    ALTER FUNCTION public.set_updated_at() SET search_path = public;
  END IF;
  IF to_regprocedure('public.touch_private_conversation()') IS NOT NULL THEN
    ALTER FUNCTION public.touch_private_conversation() SET search_path = public;
  END IF;
END $$;
