# Niswah Database Recovery Runbook

**Last updated:** 2026-09-08, Final BR-001 Production Backup Verification Wave. **Last schema restore test:** 2026-09-06 — two full rebuilds (baseline-only, baseline + `W1-001`), both schema-contract-verified — see `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §37. **Real production backup status, confirmed 2026-09-08**: 7 consecutive `COMPLETED` daily physical backups now exist (`00_09` §43) — a genuine, verified change from every prior wave's "zero backups" state. A restore drill against this real backup has not yet been performed — see §7/§8 below.

This runbook covers **schema/application recoverability** — rebuilding the database structure and confirming the application works against it — and now also tracks **real production backup existence**, though not yet real-data restore proof. See §7 (RPO/RTO) for the precise, current, evidence-backed state of each.

**⚠ Standing credential note (added 2026-09-06):** the Supabase CLI role `cli_login_postgres` had its password briefly, unintentionally printed to a session's output during a `db dump --dry-run` investigation. This role is **persistent** (not auto-expiring) — its password remains valid until explicitly changed. If that rotation has not yet been confirmed complete, treat any operation in this runbook that touches the real production project (not a local/isolated stack) as carrying that residual risk until an owner confirms rotation via `ALTER ROLE cli_login_postgres WITH PASSWORD '<new-strong-password>';` or by dropping and letting the CLI recreate the role. Never print, log, or commit this or any other database password — see §2's `--dry-run` warning below, added for the same reason.

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
- **`--dry-run` warning (added 2026-09-06):** `supabase db dump --linked` (with or without `--data-only`) — even with `--dry-run` — establishes a real wire connection to compose its output and will print a live, plaintext database password to the terminal/logs as a side effect. Treat every variant of this command as credential-printing, not as a safe preview. Prefer Management-API-based commands (`supabase backups list`, `supabase migration list --linked`, `supabase projects list`) for any read-only production check — none of these require or print a database password.

## 3. Recovery artifact locations

| Artifact | Path | Status as of this wave |
|---|---|---|
| Canonical baseline (the tested recovery package) | `supabase/canonical_baseline/00_public_baseline_draft.sql` | **CURRENT** — re-validated this wave: applies cleanly to empty, produces 24/24 tables, 8/8 functions, 24/24 RLS-enabled, identical to the original Wave 0 live capture |
| Live schema capture (point-in-time reference, not itself a restore artifact) | `supabase/live_schema_capture/2026-09-04_{public,auth,storage}.sql` | CURRENT (one day old at time of writing; no live schema change has occurred since — no migrations added, no DB-touching work performed by any remediation wave) |
| Historical migrations (archived) | `supabase/migrations_archive/*.sql` (12 files, moved here by the BR-002 Migration Chain Reproducibility wave, 2026-09-06) | **UNSAFE for restore, and no longer even attempted by tooling.** Confirmed via a full concatenated replay this wave: 96 `ERROR` lines, only 7 of ~20 tables created. Preserved as audit evidence only — see `supabase/migrations_archive/README.md`. **Not in the active replay path** — `supabase start`/`supabase db push` never read this directory. |
| Active migrations | `supabase/migrations/*.sql` (now just `20260906090000_ai_rate_limit.sql`, `W1-001`) | Self-contained, additive-only, verified idempotent — safe for `supabase start` to auto-apply. See `docs/database-migration-strategy.md`. |
| Migration ledger repair plan | Superseded by the strategy above — the ledger's divergence from reality is now a deliberately, permanently accepted and documented fact (`docs/database-migration-strategy.md`'s "Migration ledger policy" section), not something a repair script needs to reconcile before repository reproducibility is considered solved. |

## 4. Restore sequence (schema-level recovery) — simplified this wave

`supabase/migrations/` now contains only `W1-001` (self-contained, no dependency on anything else) — **`supabase start` no longer needs the migrations directory moved aside first**, since there is nothing broken left in the active replay path:

```bash
cd <repo root>

# 1. Clean slate
docker volume ls --filter "name=supabase" --format "{{.Name}}" | xargs -r docker volume rm

# 2. Start — applies supabase/migrations/ (just W1-001) automatically, no manual workaround needed
SUPABASE_ACCESS_TOKEN="<any-non-empty-value>" supabase start
# ~47-50s measured this wave, Docker images already cached locally.

# 3. Apply the canonical baseline directly — NOT supabase db push for this step,
#    since the baseline itself is not a tracked migration:
docker cp supabase/canonical_baseline/00_public_baseline_draft.sql \
  supabase_db_Niswah:/tmp/baseline.sql
docker exec supabase_db_Niswah psql -U postgres -v ON_ERROR_STOP=1 \
  -f /tmp/baseline.sql
# Sub-second, measured this wave.

# 4. Verify (schema-contract check, not just "applied without error"):
docker cp scripts/verify_schema_contract.sql supabase_db_Niswah:/tmp/verify_schema_contract.sql
docker exec supabase_db_Niswah psql -U postgres -f /tmp/verify_schema_contract.sql
```

Or, in one command: `scripts/validate_migrations.sh` (does all four steps above, plus teardown, tested end-to-end this wave).

**Total measured time, this wave, stack-start through schema-contract-verified:** well under one minute, run twice (baseline-only, and baseline + `W1-001`) with identical, fully-passing results both times — see `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §37 for the full evidence. A completely cold environment (first-ever Docker image pull) would take materially longer — budget extra time for that case specifically.

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

## 7. RPO / RTO (see §20 Phase G, §34, §35, §43 in `00_09` for full derivation)

- **RTO (schema/application recoverability):** ~2 minutes measured stack-to-schema-ready, plus behavioral validation time (a few more minutes for the checklist in §5) — call it **10-15 minutes realistic total** for a practiced operator, more on a cold Docker-image-pull environment or if issues are hit. Re-confirmed via a fresh independent restore in the Production Database Change Safety Gate wave (2026-09-06).
- **RTO (real production data):** **`UNTESTED`** — a real production backup now exists (see below), but no restore drill has ever been performed against it. Do not report a duration until one has actually been run.
- **RPO (schema):** effectively zero for structure, since the baseline is derived from and matches the live schema — but this only protects *structure*, not *rows*.
- **RPO (production user data):** **up to ~24 hours, evidence-backed as of 2026-09-08** — the owner upgraded the Supabase plan tier and daily physical backups are now confirmed running: 7 consecutive `COMPLETED` backups, `2026-09-01` through `2026-09-07`, ~16:24 UTC each day (`GET /v1/projects/<ref>/database/backups`, re-verified in the Final BR-001 Production Backup Verification wave). `pitr_enabled` remains deliberately `false` — no RPO requirement in this engagement justifies PITR's added cost over the now-active daily-backup default.

## 8. What this runbook cannot do — stated plainly

- **It has not yet had a real restore proven against it.** A real production backup now exists (7 daily `COMPLETED` physical backups, confirmed 2026-09-08) — a genuine, hard-won change from every prior wave's "zero backups" state — but no restore drill has ever been run against it. Until one is, "a backup exists" and "we can actually recover from it" remain two different claims, and this runbook does not conflate them. **The remaining owner action**: authorize and execute a real restore-to-new-project drill (a paid resource creation requiring separate cost approval) against one of these physical backups, then re-run the existing 14-point behavioral verification suite (§5-adjacent, `00_09` §20 Phase E) against the restored project — this is the one step left to fully close `BR-001` per its own native definition.
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
