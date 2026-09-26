# Production test-account cleanup — status: OUTSTANDING (not deleted)

**Account:** `I.1790267697321@example.test` (Supabase Auth email; GoTrue stores
it lowercased: `i.1790267697321@example.test`)
**Project:** the real production Supabase project (`jkmjobvxfrmuwafczvtw`)
**Created (from the timestamp embedded in the address):** 2026-09-24
16:34:57 UTC
**Cause:** a persona run started before `.env` had been re-pointed from
production to the local disposable backend. The run reached the Auth
sign-up screen and submitted a sign-up; the app then showed "Check your
email" (production requires email confirmation), so the account is
expected to exist **unconfirmed**, and no onboarding, menstrual, or other
application rows should exist for it. That expectation is unverified.

**Status: NOT DELETED, NOT VERIFIED. Do not treat as cleaned up.**

## Why this was not done in-session

The only production credential available to the automated session is the
public *anon* key that ships inside the app. It cannot list or delete Auth
users and must not be used to improvise an administrative deletion. A
deletion needs an authorized administrative path (Supabase Dashboard with
admin access, or the Admin API with a service-role key supplied through an
approved secure environment). No such credential was provided, so this is
a genuine authorization blocker, not something to work around. The
service-role key must never be printed or committed.

## Preventing a recurrence (done)

The acceptance harness now refuses to run against production or any
unapproved backend — see `docs/acceptance-test-runbook.md`. Three
independent layers (host script, app `main()` before Supabase/Sentry init,
persona guard), 30 Dart + Python tests over shared vectors, and live proof
that a refused run creates no account and makes no network call.

## Procedure for the authorized operator

Run the read-only inspection first and record the results in the evidence
table below **before** deleting anything.

1. **Locate the Auth user** (Dashboard → Authentication → Users, search the
   email). Record its UUID: `________`.
2. **Inspect every user-owned table for that UUID** (read-only). Substitute
   the UUID. Every table below references the user with `ON DELETE CASCADE`
   except the one marked **NO FK** (this list was derived from the schema:
   every `public` table that carries a user identifier).

   ```sql
   -- expected: all zero for an account that never got past sign-up
   select 'users'                   t, count(*) from public.users                   where id      = :uid
   union all select 'profiles',             count(*) from public.profiles             where id      = :uid
   union all select 'bleeding_episodes',    count(*) from public.bleeding_episodes    where user_id = :uid
   union all select 'bleeding_observations',count(*) from public.bleeding_observations where user_id = :uid
   union all select 'cycle_baselines',      count(*) from public.cycle_baselines      where user_id = :uid
   union all select 'cycle_entries',        count(*) from public.cycle_entries        where user_id = :uid
   union all select 'cycle_logs',           count(*) from public.cycle_logs           where user_id = :uid
   union all select 'pregnancy_profile',    count(*) from public.pregnancy_profile    where user_id = :uid
   union all select 'pregnancy_records',    count(*) from public.pregnancy_records    where user_id = :uid
   union all select 'nifas_records',        count(*) from public.nifas_records        where user_id = :uid
   union all select 'istihadah_episodes',   count(*) from public.istihadah_episodes   where user_id = :uid
   union all select 'ramadan_records',      count(*) from public.ramadan_records      where user_id = :uid
   union all select 'adah_ledger',          count(*) from public.adah_ledger          where user_id = :uid
   union all select 'prayer_log',           count(*) from public.prayer_log           where user_id = :uid
   union all select 'wellbeing_logs',       count(*) from public.wellbeing_logs       where user_id = :uid
   union all select 'symptoms_log',         count(*) from public.symptoms_log         where user_id = :uid
   union all select 'chat_threads',         count(*) from public.chat_threads         where user_id = :uid
   union all select 'chat_messages',        count(*) from public.chat_messages        where user_id = :uid
   union all select 'chat_history',         count(*) from public.chat_history         where user_id = :uid
   union all select 'flagged_conversations',count(*) from public.flagged_conversations where user_id = :uid
   union all select 'dream_entries',        count(*) from public.dream_entries        where user_id = :uid
   union all select 'secret_vault',         count(*) from public.secret_vault         where user_id = :uid
   union all select 'community_posts',      count(*) from public.community_posts      where user_id = :uid
   union all select 'community_comments',   count(*) from public.community_comments   where user_id = :uid
   union all select 'community_likes',      count(*) from public.community_likes      where user_id = :uid
   union all select 'private_conversations',count(*) from public.private_conversations where participant_one = :uid or participant_two = :uid
   union all select 'private_messages',     count(*) from public.private_messages     where sender_id = :uid
   union all select 'ai_rate_limit_counters (NO FK)', count(*) from public.ai_rate_limit_counters where user_id = :uid;
   ```

   Not server-side, so not in the database: notification preferences and
   event log, pending-operation queue, reports/exports (generated on device).
   Also worth a glance: Supabase Auth logs for the sign-up, and Sentry for
   events from that session (the production `.env` carries the real Sentry
   DSN; that run may have reported errors under `env=development`).
3. **Delete the Auth user** through the authorized path (Dashboard →
   Delete user, or Admin API `DELETE /auth/v1/admin/users/{uid}`).
4. **Re-run the inspection.** Expected: the Auth user is gone and every
   cascading table is 0.
5. **Expected exception (a real defect, now fixed in the repo but NOT yet
   deployed to production):** `ai_rate_limit_counters` has no foreign key,
   so any counter rows for this UUID survive Auth deletion. For an account
   that never reached an AI feature the count is expected to be 0 and this
   is moot; if it is non-zero, do **not** delete them blindly — record the
   count, then either deploy migration
   `20260925100000_ai_rate_limit_counters_deleted_with_user.sql` (which also
   removes counters already orphaned by earlier deletions) or remove exactly
   that UUID's rows and note it here.
6. Fill in the evidence table and mark the status COMPLETE only when both
   the Auth deletion **and** the post-deletion table check are recorded.

## Evidence (to be completed by the operator)

| Field | Value |
|---|---|
| Account email | `I.1790267697321@example.test` |
| Auth user UUID | |
| Auth user existed / confirmed? | |
| Rows per table **before** (from the query above) | |
| Deleted via (Dashboard / Admin API), by whom, when | |
| Auth user exists after? | |
| Rows per table **after** | |
| `ai_rate_limit_counters` before → after | |
| Sentry / Auth-log findings | |
| Final status | **OUTSTANDING** |

## Account-deletion behavior verified in the repo (local, disposable Postgres)

This is evidence about the *mechanism*, not about the production account.

- Every user-owned `public` table (27 of them) references `public.users`
  or `auth.users` with `ON DELETE CASCADE`. Deleting the Auth user through
  the app's own `delete_my_account()` (which is literally
  `delete from auth.users where id = auth.uid()`) took a disposable account
  holding canonical episodes/observations/baseline, a legacy
  `cycle_entries` row and an AI counter from 6 attributable rows to 0
  **for every cascading table**.
- **Defect D-005 (P3), found by this check:** `ai_rate_limit_counters.user_id`
  had no foreign key, so one row remained attributable to the deleted UUID
  (until a sampled 1-in-50 sweep, and only for old windows). Fixed by a
  trigger on `auth.users` (covers the app RPC, the Dashboard and the Admin
  API alike) plus a one-time removal of already-orphaned counters.
  Regression: `scripts/check_account_deletion_cascade.sh` failed before
  the fix (`before=6 after=1`) and passes after (`before=6 after=0`); it and
  a schema-contract row now run inside `scripts/validate_migrations.sh`.
  Deleting straight from `auth.users` (the Dashboard/Admin equivalent) was
  also verified to remove the counters.
