# Niswah Database Recovery Runbook

**Last updated:** 2026-09-05, Backup/Recovery Remediation Wave. **Last restore test:** 2026-09-05 (this wave) — see `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §20 for full evidence.

This runbook is for **schema/application recoverability** — rebuilding the database structure and confirming the application works against it. It is explicitly **not** a guarantee of recovering real production user data — see the RPO section below and §20 Phase G/H for why, and what would be needed to close that separate gap.

---

## 1. Failure scenarios this runbook covers

- **A. Live database lost or corrupted** (project deleted, catastrophic Postgres failure, accidental `DROP`) — no Supabase-side backup exists to restore from (see §2). This runbook lets you rebuild the *schema* from scratch; it cannot recover *data* that existed only in the lost database.
- **B. Suspected schema corruption** (a bad manual Studio change, a partially-applied migration) — use this runbook to stand up a clean reference environment and diff against production to identify what changed.
- **C. Need to test a new migration safely** — apply it to a fresh restore of this baseline first, never directly to production.

## 2. Prerequisites

- Docker Desktop (or compatible), running.
- Supabase CLI, authenticated (`supabase login`). **Known issue, recurring throughout this project's history:** the CLI's keychain-based session token intermittently hangs indefinitely on any authenticated command (not just this project — a `security find-generic-password` call blocks). Fix: re-run `supabase login` in an interactive terminal (not a scripted/automated context) and complete the browser OAuth flow. For **local-only** operations (`supabase start`/`stop`), this can be bypassed by setting a dummy `SUPABASE_ACCESS_TOKEN` env var — that trick does **not** work for any command that talks to the real Supabase platform API (`projects list`, `backups list`, `db dump` against `--linked`, etc.), which genuinely need a real, valid session.
- Access to `supabase/canonical_baseline/00_public_baseline_draft.sql` — the tested, working recovery artifact (not `supabase/migrations/`, which does not replay cleanly from empty — see §4 note).
- No production credentials are needed to run this runbook against a local/isolated environment. Restoring to a real environment (staging or the production project itself) requires the project's real database connection string / service role key — **never commit these**, obtain them from the Supabase dashboard or the owner's secure credential store at the time of use.

## 3. Recovery artifact locations

| Artifact | Path | Status as of this wave |
|---|---|---|
| Canonical baseline (the tested recovery package) | `supabase/canonical_baseline/00_public_baseline_draft.sql` | **CURRENT** — re-validated this wave: applies cleanly to empty, produces 24/24 tables, 8/8 functions, 24/24 RLS-enabled, identical to the original Wave 0 live capture |
| Live schema capture (point-in-time reference, not itself a restore artifact) | `supabase/live_schema_capture/2026-09-04_{public,auth,storage}.sql` | CURRENT (one day old at time of writing; no live schema change has occurred since — no migrations added, no DB-touching work performed by any remediation wave) |
| Tracked migrations | `supabase/migrations/*.sql` | **UNSAFE for restore — do not use.** Confirmed, freshly, this wave: replaying them against an empty database fails (`BR-002`, re-confirmed live). They do not represent an applied, working history — they were never successfully applied to the live project through the tracked mechanism at all. |
| Migration ledger repair plan (not executed) | `production-readiness-results/master/00_10_WAVE0_EXECUTION_REPORT.md` Output K | Proposed, reviewed, **not run**. Would resolve the ledger's disagreement with reality but does not itself fix `supabase/migrations/`'s replay failure — the underlying migration files remain unusable as a from-empty restore path either way. |

## 4. Restore sequence (schema-level recovery)

```bash
cd <repo root>

# 1. Start an isolated Supabase stack. If testing a truly clean restore
#    (not just reusing an already-migrated local volume from other work),
#    remove any existing local DB volume first:
docker volume rm supabase_db_Niswah 2>/dev/null

# 2. IMPORTANT: supabase start auto-replays supabase/migrations/ against a
#    truly empty database, and that replay fails (see §3 above). Move the
#    migrations directory aside before starting, or the stack will not come
#    up at all:
mv supabase/migrations /tmp/supabase_migrations_backup

SUPABASE_ACCESS_TOKEN="<any-non-empty-value>" supabase start
# (~60-90s on a machine with the Docker images already cached; longer on
#  first-ever pull.)

# 3. Apply the canonical baseline directly — NOT supabase db push, which
#    would try to use supabase/migrations/ again:
docker cp supabase/canonical_baseline/00_public_baseline_draft.sql \
  supabase_db_Niswah:/tmp/baseline.sql
docker exec supabase_db_Niswah psql -U postgres -v ON_ERROR_STOP=1 \
  -f /tmp/baseline.sql
# Measured this wave: <1 second.

# 4. Restore the migrations directory afterward (it is real, tracked
#    source — do not leave it moved aside):
mv /tmp/supabase_migrations_backup supabase/migrations
```

**Total measured time, this wave, stack-start through schema-ready:** 92 seconds (65s stack startup + <1s baseline apply), on a machine with Docker images already cached locally. A completely cold environment (first-ever image pull) would take materially longer — budget extra time for that case specifically, e.g. during initial on-call training or on a fresh machine.

## 5. Validation sequence (confirm the restore actually works, not just that it applied without error)

Schema equality is necessary but not sufficient — validate real application behavior. Minimum checklist, all confirmed working this wave against a fresh restore using the real local Supabase Auth service (not a stub):

1. Sign up a synthetic user via `/auth/v1/signup`.
2. Confirm `public.profiles` and `public.users` rows were created automatically (the two `auth.users` triggers fired).
3. As that user, write a `cycle_entries` row; confirm `fiqh_state` defaults to `'TAHARA'`.
4. As a second synthetic user, confirm you **cannot** see the first user's `cycle_entries` row (RLS).
5. As the first user again, confirm you **can** see your own row.
6. Write a `pregnancy_profile` row; confirm it succeeds.
7. Update `profiles.full_name`; confirm it persists.
8. Write a `prayer_log` row using a status value from `{prayed, qadha_required, lifted, missed}` — **not** `completed`/`pending`/`excused`; see the known app-code bug in §8.
9. Write and read back a `community_posts` row as a different user (public read).
10. Call `delete_my_account()`; confirm every row across `auth.users`/`public.users`/`public.profiles`/`cycle_entries`/`pregnancy_profile`/`prayer_log`/`community_posts` for that user is gone.

If any of these fail against a restore that otherwise reports "success," the restore is not actually usable — do not consider recovery complete on schema-apply exit code alone.

## 6. Decision points / escalation

- **If `supabase start` itself won't come up:** check Docker Desktop is running and has enough resources; check for a stale `supabase_db_Niswah` volume/container from a prior session (`docker ps -a`, `docker volume ls`) and remove it.
- **If the baseline apply fails partway through:** stop — do not attempt to patch around it live. Diff the error against `supabase/live_schema_capture/2026-09-04_public.sql` to see if live has drifted from the baseline since it was captured; re-capture from the real project (read-only `supabase db dump -s public --linked`) if so.
- **If auth restoration fails** (triggers don't fire, `public.users`/`public.profiles` stay empty after signup): check that both `auth_users_create_profile` and `on_auth_user_created` triggers exist on `auth.users` (`\d auth.users` in psql) and that their backing functions (`create_user_profile()`, `handle_new_user()`) exist in `public`. These are the two objects most likely to be silently missing from a naive restore attempt, since they live in `auth`, not `public`, and are easy to overlook — the canonical baseline includes them explicitly for this reason.
- **If RLS restoration fails** (a user can see another user's private data): check `SELECT relrowsecurity FROM pg_class WHERE relname = '<table>'` — the baseline enables RLS on all 24 tables; if any show `false`, the baseline apply was incomplete or a different object with the same name shadowed it. Do not proceed to point any real traffic at this environment until RLS is confirmed correct for every affected table.
- **If Edge Functions depend on missing DB behavior:** the three tables the deployed Edge Functions reference directly are `chat_messages`, `flagged_conversations`, `pregnancy_profile` (confirmed via `grep -rn ".from('" supabase/functions/*/index.ts` this wave) — all three are `REQUIRED_APPLICATION_OBJECT` in the baseline. If a function still errors against a freshly-restored DB with these tables present, check RLS policies specifically (the service-role client used by `flagged_conversations` writes bypasses RLS; the user-scoped client used for `chat_messages`/`pregnancy_profile` does not) and check the two `auth.users` triggers are present (functions assume a caller's `public.users`/`public.profiles` row already exists).

## 7. RPO / RTO (see §20 Phase G in `00_09` for full derivation)

- **RTO (schema/application recoverability):** ~2 minutes measured stack-to-schema-ready this wave, plus behavioral validation time (a few more minutes for the checklist in §5) — call it **10-15 minutes realistic total** for a practiced operator, more on a cold Docker-image-pull environment or if issues are hit.
- **RTO (real production data, e.g. via an eventual PITR):** cannot be estimated — no such capability exists today (see §8).
- **RPO (schema):** effectively zero for structure, since the baseline is derived from and matches the live schema — but this only protects *structure*, not *rows*.
- **RPO (production user data):** **infinite / total loss** if the live database were lost today. No Supabase-managed backup, no PITR, and no independent logical data export exists. See §8 and `00_09` §20 Phase H for what closing this actually requires.

## 8. What this runbook cannot do — stated plainly

- **It cannot recover real user data.** The canonical baseline contains schema only — table structure, constraints, functions, triggers, RLS policies. It was deliberately built without exporting any production row data, per the operating constraints of every wave in this engagement. If the live database were lost today, everything reproducible by this runbook would come back; every real user's cycle logs, pregnancy data, chat history, and account would not.
- **It does not fix `W0-002`** (pregnancy-milestone table/data-model mismatch) — deliberately out of scope, preserved as `DEFERRED — PRODUCT/DATA-MODEL DECISION REQUIRED`.
- **It does not fix `W0-003`** (newly discovered this wave — prayer-log status values the app sends don't match the database's allowed values for 3 of 4 statuses) — a real, currently-live application bug, not a recovery-artifact defect; the baseline correctly and faithfully reproduces the actual (currently broken-for-this-feature) production constraint. See `00_04`/`00_09` for full detail.

## 9. Post-recovery validation

After any real restore (not just this local test), before considering the incident resolved:
1. Run the full §5 checklist against the restored environment.
2. Confirm the deployed Edge Functions (`dr-niswah-chat`, `ai-assistant-chat`, `fiqh-advisor-chat`, `dream-interpreter-chat`) can reach the restored database and complete a normal request.
3. Confirm the mobile app's sign-in flow works end-to-end against the restored project.
4. Document what was lost (time window, which tables/rows if determinable) and communicate it per the incident's severity.

## 10. Post-incident steps

- Update this runbook with anything learned that wasn't already documented here.
- Re-run the restore-test-to-validated cycle at least once more shortly after, to confirm the *incident itself* didn't leave the recovery artifacts stale.
- If the incident involved data loss, this is the trigger to finally implement the production data backup strategy in `00_09` §20 Phase H, if it hasn't been already — the near-miss is the strongest possible case for prioritizing it.
