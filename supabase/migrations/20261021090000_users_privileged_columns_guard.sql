-- USERS PRIVILEGED-COLUMNS GUARD (security hotfix, proposed 2026-10-21)
--
-- Finding SEC-012 (production-readiness-results/security/SEC_findings.md):
-- `users_update_own` only checked `auth.uid() = id`, and `authenticated`
-- holds UPDATE on every column of public.users. Any signed-in user could
-- therefore run
--     update public.users set role = 'admin' where id = auth.uid();
-- after which public.is_admin() is true for her, and every policy built on
-- public.can_access_user() (`auth.uid() = row_user_id OR is_admin()`)
-- exposes every other user's health rows (bleeding episodes/observations,
-- baselines, cycle_entries, prayer_log, pregnancy_records, nifas_records,
-- istihadah_episodes, adah_ledger, symptoms_log, secret_vault, ...) for
-- read, and for delete wherever the policy is FOR ALL. The same policy text
-- is in the 2026-09-04 live schema capture, so production is presumed
-- affected until the audit query in that finding says otherwise.
--
-- Fix, in two layers:
--   1. A BEFORE INSERT OR UPDATE trigger on public.users that rejects
--      (SQLSTATE 42501, insufficient_privilege) any client-role write that
--      changes `role`, `premium_status` or `premium_expires_at`, or inserts
--      them with anything but the column defaults. "Client role" means
--      current_user is `authenticated` or `anon` — the roles PostgREST
--      switches to for app requests. service_role, postgres and SECURITY
--      DEFINER functions owned by postgres (e.g. the signup trigger
--      create_user_profile(), which inserts premium_status) run as other
--      roles and are unaffected, so legitimate admin paths keep working.
--      The app never writes these columns (checked: lib/ only updates
--      display_name, anonymous_mode, onboarding_completed,
--      madhhab/madhhab_selection_state, community_language).
--   2. users_update_own no longer admits is_admin(): a client may only
--      update her own row. No app feature uses an admin client path;
--      administrative changes go through service_role, which bypasses RLS.
--   3. users_insert_own / users_delete_own are dropped (see Layer 3).
--
-- Idempotent: CREATE OR REPLACE / DROP ... IF EXISTS throughout.

CREATE OR REPLACE FUNCTION public.users_guard_privileged_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER -- must see the CALLER's role in current_user
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_default_premium_status boolean;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW; -- service_role, postgres, definer-owned functions
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.role IS DISTINCT FROM OLD.role
      OR NEW.premium_status IS DISTINCT FROM OLD.premium_status
      OR NEW.premium_expires_at IS DISTINCT FROM OLD.premium_expires_at
    THEN
      RAISE EXCEPTION
        'users.role/premium_status/premium_expires_at cannot be changed by the client'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- INSERT: only the column defaults are allowed. premium_status' default
  -- is read from the catalog rather than hard-coded, so a later default
  -- change does not silently break client sign-up.
  EXECUTE 'SELECT ' || coalesce(
      (SELECT pg_get_expr(d.adbin, d.adrelid)
         FROM pg_attrdef d
         JOIN pg_attribute a
           ON a.attrelid = d.adrelid AND a.attnum = d.adnum
        WHERE d.adrelid = 'public.users'::regclass
          AND a.attname = 'premium_status'),
      'NULL') || '::boolean'
    INTO v_default_premium_status;

  IF NEW.role IS DISTINCT FROM 'user'
    OR NEW.premium_status IS DISTINCT FROM v_default_premium_status
    OR NEW.premium_expires_at IS NOT NULL
  THEN
    RAISE EXCEPTION
      'users.role/premium_status/premium_expires_at must keep their defaults on a client insert'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.users_guard_privileged_columns() IS
  'SEC-012: blocks client roles (authenticated/anon) from setting users.role, '
  'premium_status or premium_expires_at; service_role/postgres unaffected.';

REVOKE ALL ON FUNCTION public.users_guard_privileged_columns()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS users_guard_privileged_columns ON public.users;
CREATE TRIGGER users_guard_privileged_columns
  BEFORE INSERT OR UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.users_guard_privileged_columns();

-- Layer 2: own-row only for client UPDATE on users.
DROP POLICY IF EXISTS users_update_own ON public.users;
CREATE POLICY users_update_own ON public.users
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Layer 3: no client INSERT or DELETE of profile rows at all. Otherwise a
-- client whose premium the server revoked could delete her row and insert
-- a fresh one with defaults (premium_status defaults to true) to get it
-- back. The app never does either: the signup trigger creates the row and
-- delete_my_account() (SECURITY DEFINER) removes it, both bypassing RLS.
DROP POLICY IF EXISTS users_insert_own ON public.users;
DROP POLICY IF EXISTS users_delete_own ON public.users;
