-- MADHHAB AUTHORITY MODEL: users.madhhab_selection_state
--
-- Fiqh Remediation Wave 1 (AUTH-005 / AUTH-010). Establishes a canonical,
-- durable, three-state Madhhab authority model server-side:
--
--   UNSET    — the user has not answered the Madhhab question yet.
--   UNKNOWN  — the user explicitly selected "I don't know my Madhhab."
--   SELECTED — the user explicitly selected exactly one real madhhab.
--
-- These states are never collapsed into one another. In particular:
-- UNKNOWN is never represented as if it were Hanbali, and UNSET is never
-- silently resolved to any specific madhhab.
--
-- Root cause this migration closes: `public.users.madhhab` existed live
-- (`text NOT NULL DEFAULT 'HANBALI'`) but was never read or written by any
-- application code path — its only writer was `create_user_profile()`'s
-- own hardcoded `'HANBALI'` literal on every signup (fixed in the same
-- migration below), not a real user choice. Client-side, `MadhhabController`
-- persisted only to `SharedPreferences` and silently fell back to
-- `Madhhab.hanbali` whenever nothing was stored (reinstall, new device, or
-- any local-storage clear) — confirmed to reach both the live deterministic
-- Fiqh-calculation path and the Fiqh Advisor AI's context with zero
-- disclosure to the user. This migration, together with the matching
-- `MadhhabController` rewrite (`lib/core/preferences/madhhab_controller.dart`),
-- makes the server the durable, canonical authority and removes every
-- silent-Hanbali fallback from the reachable code path.
--
-- Existing-user migration policy (explicit, conservative, not inferred):
-- no existing user's `madhhab` value is trustworthy — it was never an
-- explicit choice, only an unused default. Per the remediation charter's
-- own instruction ("do NOT infer Hanbali merely because ... Hanbali was
-- the previous internal default"), every existing row is migrated to
-- UNSET below, not silently preserved as Hanbali. A user who previously
-- made a real choice only ever recorded it in local `SharedPreferences`,
-- which this server-side migration cannot see or recover — she will be
-- asked once, explicitly, the next time a Fiqh-guidance surface needs her
-- madhhab (client-side: if a valid local cache value still exists on her
-- current device, `MadhhabController.load()` write-throughs it to the
-- server as her first real SELECTED state instead of discarding it; this
-- migration only concerns server rows that have no such local signal to
-- draw on, e.g. a fresh migration run against every account regardless of
-- which device is currently signed in).
--
-- Guarded (IF EXISTS) rather than a bare ALTER, matching this repo's
-- established pattern (see 20260909100000_wellbeing_logs_notes.sql) — a
-- truly fresh `supabase start` applies supabase/migrations/ before the
-- separately-applied canonical baseline defines `public.users`, so this
-- guard makes the file a safe no-op there and a real, idempotent ALTER
-- against the one environment that actually needs it today: production.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'users'
  ) THEN

    -- 1. Add the selection-state column. Every row (existing and future,
    --    until explicitly set otherwise) defaults to 'unset' — never a
    --    specific madhhab.
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'users'
        AND column_name = 'madhhab_selection_state'
    ) THEN
      ALTER TABLE public.users
        ADD COLUMN madhhab_selection_state TEXT NOT NULL DEFAULT 'unset';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'users_madhhab_selection_state_check'
    ) THEN
      ALTER TABLE public.users
        ADD CONSTRAINT users_madhhab_selection_state_check
        CHECK (madhhab_selection_state IN ('unset', 'unknown', 'selected'));
    END IF;

    -- 2. Relax the old column so it can represent "no explicit madhhab"
    --    (UNSET/UNKNOWN both require NULL) instead of a hardcoded default
    --    that silently implied a choice nobody made.
    ALTER TABLE public.users ALTER COLUMN madhhab DROP NOT NULL;
    ALTER TABLE public.users ALTER COLUMN madhhab DROP DEFAULT;

    -- 3. No existing row's madhhab value is a trustworthy explicit
    --    selection (see the policy note above) — reset every row before
    --    adding the consistency constraint below, so the migration never
    --    has to choose between failing the constraint and silently
    --    keeping an untrustworthy value.
    UPDATE public.users SET madhhab = NULL WHERE madhhab IS NOT NULL;
    UPDATE public.users SET madhhab_selection_state = 'unset'
      WHERE madhhab_selection_state <> 'unset';

    -- 4. Constrain madhhab's content whenever it is non-null, and keep it
    --    in lockstep with the selection-state column so the two can never
    --    contradict each other (e.g. state='selected' with a NULL madhhab,
    --    or state='unset' with a real madhhab value still sitting there).
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'users_madhhab_value_check'
    ) THEN
      ALTER TABLE public.users
        ADD CONSTRAINT users_madhhab_value_check
        CHECK (madhhab IS NULL OR lower(madhhab) IN ('hanafi', 'maliki', 'shafii', 'hanbali'));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'users_madhhab_state_consistency_check'
    ) THEN
      ALTER TABLE public.users
        ADD CONSTRAINT users_madhhab_state_consistency_check
        CHECK (
          (madhhab_selection_state = 'selected' AND madhhab IS NOT NULL)
          OR (madhhab_selection_state IN ('unset', 'unknown') AND madhhab IS NULL)
        );
    END IF;

  END IF;
END $$;

-- 5. Fix the actual signup-time silent default: `create_user_profile()`
--    previously hardcoded 'HANBALI' into every new user's `madhhab` column
--    on signup, unconditionally — the single most authoritative silent
--    default in the whole system, since it applied to every new account
--    from the moment it was created, before any client code ever ran.
--    Every new signup now starts UNSET, exactly like every existing user
--    migrated above — onboarding's own Madhhab step (client-side) is what
--    turns that into a real SELECTED/UNKNOWN state, never this trigger.
CREATE OR REPLACE FUNCTION public.create_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  insert into public.users (
    id,
    email_hash,
    display_name,
    madhhab,
    madhhab_selection_state,
    language,
    onboarding_completed,
    premium_status,
    created_at,
    updated_at
  )
  values (
    new.id,
    md5(coalesce(new.email, 'anonymous')),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name', 'Sister'),
    null,
    'unset',
    'ar',
    false,
    true,
    now(),
    now()
  )
  on conflict (id) do nothing;

  return new;
end;
$function$;
