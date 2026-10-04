# Production Deployment Preparation Report — Niswah

**Date**: 2026-10-04. Commit at time of writing: `9c36d04`. This is a
**read-only, non-destructive** workstream: it determines whether
production can safely receive the already-validated staging release
and produces the exact deployment + rollback procedure for founder
authorization. **It does not authorize production deployment.** No
migration was applied, no KB was seeded, no Edge Function was deployed,
no secret was set or changed, no KB snapshot was activated, and no
production traffic or data was modified in the course of this
workstream. Every production read was preceded by an identity assertion
(`assert_is_production_project`) confirming ref `jkmjobvxfrmuwafczvtw`,
name "Niswah" — never ambiguous, never defaulted.

**Headline finding, stated up front because it changes the shape of
everything below**: production is **not** a blank slate waiting for a
first deployment. It is an **already-live system** — 26 real user
accounts, 4 Edge Functions already deployed and `ACTIVE` (versions
9–15, not fresh), currently running on **`GEMINI_API_KEY`**, not
OpenAI. Migrations #1–#4 of the 7 "active migrations" set are **already
applied**. Only the 3 KB-specific migrations, the KB seed/snapshot, and
the OpenAI-provider Edge Function code are actually pending. This is a
**partial upgrade of a live system**, not a greenfield deploy — every
section below reflects that.

---

## Phase 1 — Production identity and access

| Field | Value |
|---|---|
| Project ref | `jkmjobvxfrmuwafczvtw` (matches expected exactly) |
| Project name | `Niswah` (matches expected exactly) |
| Region | `ap-southeast-1` |
| Status | `ACTIVE_HEALTHY` |
| Postgres | engine `17`, version `17.6.1.127`, release channel `ga` (staging is `17.11.0.002` — same major version, newer patch on staging; not expected to matter for this migration set, noted for completeness) |
| Compute tier | **Not determinable via `billing/addons`** — that endpoint returned zero `selected_addons` for this project (unlike staging, which showed exactly one `ci_micro` entry). This project predates the addon-based billing model or was never recorded through it; not resolved further to avoid guessing. Does not block anything below — it's informational. |
| Supavisor/pooling | Configured and live: one pooler entry, host `aws-1-ap-southeast-1.pooler.supabase.com` (note: **not** `aws-0-`, unlike staging — confirms the host prefix is not a fixed pattern and must always be read from the real config, never assumed), port `6543`, `pool_mode: transaction`, user `postgres.jkmjobvxfrmuwafczvtw`. Only a transaction-mode entry was returned by this endpoint; a session-mode (port 5432) variant was not independently confirmed for production the way it was for staging — verify at execution time rather than assuming the same pattern transfers. |
| New publishable/secret keys | **Enabled** — both present: `publishable` (prefix `sb_publishable_YqJFV...`) and `secret` (prefix `sb_secret_h0eTV...`). |
| Legacy keys | **Enabled** (`/api-keys/legacy` → `{"enabled": true}`) — unlike staging, where legacy keys were disabled after the redaction incident. Disabling them is a founder decision this workstream does not make or recommend unilaterally; flagged as `MANUAL_DECISION_REQUIRED` in Phase 3. |

**PRODUCTION IDENTITY VERIFIED: YES.**

## Phase 2 — Current production inventory

Read-only (`information_schema`, `pg_catalog`, the Management API) throughout. No mutation.

**Tables (25 in `public`)**: `adah_ledger`, `ai_rate_limit_counters`, `chat_history`, `chat_messages`, `chat_threads`, `community_comments`, `community_likes`, `community_posts`, `cycle_entries`, `cycle_logs`, `dream_entries`, `flagged_conversations`, `istihadah_episodes`, `nifas_records`, `prayer_log`, `pregnancy_profile`, `pregnancy_records`, `private_conversations`, `private_messages`, `profiles`, `ramadan_records`, `secret_vault`, `symptoms_log`, `users`, `wellbeing_logs`.

**None of the 6 KB tables exist**: `knowledge_items`, `knowledge_item_versions`, `knowledge_item_sources`, `knowledge_sources`, `knowledge_citations`, `kb_snapshot_registry` — all absent. No active snapshot (there is no registry to have one). `retrieve_knowledge_v1` and `get_active_kb_snapshot` do not exist in `pg_proc`.

**Migration status, verified directly against real schema (not inferred from the empty Supabase migration-tracking table — see note below)**:

| Migration | Status on production | Evidence |
|---|---|---|
| `20260906090000_ai_rate_limit.sql` | **Already applied** | `ai_rate_limit_counters` table exists; `check_and_increment_ai_rate_limit` function exists in `pg_proc`. Migration's own comment ("directly load-tested in production") corroborates. |
| `20260909100000_wellbeing_logs_notes.sql` | **Already applied** | `wellbeing_logs.notes` column exists. |
| `20260914120000_madhhab_authority_state.sql` | **Already applied** | `users.madhhab_selection_state` exists (`NOT NULL DEFAULT 'unset'`), `users.madhhab` is nullable with no default, all three new constraints present (`users_madhhab_selection_state_check`, `users_madhhab_value_check`, `users_madhhab_state_consistency_check`). `create_user_profile()`'s live body (`pg_get_functiondef`) contains no `HANBALI` literal and inserts `'unset'` — confirmed the *updated* function, not the pre-fix hardcoded-Hanbali version. |
| `20260914120100_...drop_legacy_uppercase_check.sql` | **Already applied** | The old `users_madhhab_check` constraint this migration drops is confirmed absent. |
| `20260929114500_knowledge_base_v1.sql` | **Pending** | None of its objects exist. |
| `20260929120000_...qualification_and_snapshot.sql` | **Pending** | Depends on the above. |
| `20260930130000_...relevance_anchor.sql` | **Pending** | Depends on both above. |

**Important caveat on migration tracking**: `GET /v1/projects/{ref}/database/migrations` (Supabase's own formal tracking, what `supabase db push`/`migration list` would read) returned an **empty list** for production — meaning migrations #1–#4 were evidently applied by some direct means (e.g. the dashboard SQL editor), never through `supabase db push`, so there is no tracking-table record of them. **Do not trust `supabase migration list`/`db push`'s own idea of "pending" for production** — it would likely consider all 7 migrations pending, which is wrong for #1–#4. Determine real status from the schema itself (as this report did), every time, not from the tracking table.

**Extensions installed**: `pg_stat_statements`, `pgcrypto`, `plpgsql`, `supabase_vault`, `uuid-ossp`. **`pg_trgm` is absent** — required by the KB migration (`CREATE EXTENSION IF NOT EXISTS pg_trgm` is the first statement of `20260929114500_knowledge_base_v1.sql`) and will be installed as part of applying it. This is a standard, free, non-paid extension — not a billing concern.

**Edge Functions deployed**: all 4 — `dr-niswah-chat` (v15), `fiqh-advisor-chat` (v9), `dream-interpreter-chat` (v9), `ai-assistant-chat` (v9) — all `ACTIVE`. Version numbers this high confirm a real deployment history predating this engagement's staging work.

**Configured secrets (names only)**: `GEMINI_API_KEY`, plus the platform-auto-injected `SUPABASE_URL`/`SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY`/`SUPABASE_PUBLISHABLE_KEYS`/`SUPABASE_SECRET_KEYS`/`SUPABASE_DB_URL`/`SUPABASE_JWKS`. **No `OPENAI_API_KEY` or `OPENAI_MODEL` exists.** The currently-deployed function code is therefore pre-OpenAI-migration code calling Gemini, not the staging-validated OpenAI code.

**Real usage scale**: `public.users` contains **26 rows** (a count only — no content was read). Zero requests to any of the 4 functions in the most recent `functions.combined-stats` 1-day bucket — no live traffic observed at the moment of this check, but 26 real accounts exist and could generate traffic at any time.

**Existing production data that could be affected by the canonical baseline or the 7 migrations**:
- The canonical baseline is **not applicable to production at all** — see Phase 5. It is a bare-DDL (`CREATE TABLE`, no `IF NOT EXISTS`) snapshot *of* production's own schema; applying it again would fail immediately on every statement since every table already exists. It must never be run against production.
- Migration #3 (`madhhab_authority_state.sql`) **already executed** a real, intentional data-modifying statement against every existing `users` row with a non-null `madhhab` (`UPDATE ... SET madhhab = NULL`) — this already happened, in the past, per the inventory above; it is not a *pending* risk, it's a *historical fact* worth the founder knowing if not already aware. Re-running the migration now would be a safe no-op (the `UPDATE`'s `WHERE` clause would match nothing left to change).
- The 3 pending KB migrations create entirely new objects — no existing table is touched by them.

**PRODUCTION INVENTORY COMPLETE: YES.**

## Phase 3 — Staging ↔ production delta

| Item | Classification | Detail |
|---|---|---|
| Canonical baseline | **NO_CHANGE** (do not apply) | Already represents production's own schema; re-applying would error on every statement. |
| Migrations #1–#4 | **NO_CHANGE** | Already applied; confirmed directly. |
| Migrations #5–#7 (KB) | **CREATE** | All-new objects; nothing conflicts. |
| `pg_trgm` extension | **CREATE** | Installed automatically by migration #5; free, no billing impact. |
| KB tables (6) | **CREATE** | All absent today. |
| `kb_snapshot_registry` | **CREATE** then **DATA_LOAD** | Table created by migration #6; populated by the KB seed script. |
| `retrieve_knowledge_v1` / `get_active_kb_snapshot` / `check_and_increment_ai_rate_limit` | **CREATE** (first two) / **NO_CHANGE** (third, already exists) | |
| KB rows (211 eligible) | **DATA_LOAD** | Net-new; nothing to reconcile against. |
| Edge Function source (all 4) | **REPLACE** | Not a first deploy — replaces live, `ACTIVE`, versions 9–15 code currently serving (or available to serve) 26 real accounts. |
| `OPENAI_API_KEY` / `OPENAI_MODEL` | **CONFIGURE** | Absent today; must be set before the new Edge Function code can function (it has no Gemini fallback). |
| `GEMINI_API_KEY` | **MANUAL_DECISION_REQUIRED** | Currently set and in active use by the live code. Whether to remove it after cutover (vs. leave it, harmless but unused) is a founder call, not inferred here. |
| Legacy API keys (anon/service_role) | **MANUAL_DECISION_REQUIRED** | Currently enabled on production, unlike staging (disabled after the redaction incident). Not this workstream's call to change. |
| New publishable/secret keys | **NO_CHANGE** | Already enabled and available; the Edge Functions' platform-injected `SUPABASE_SERVICE_ROLE_KEY` secret already exists regardless of key-type policy. |
| `SENTRY_DSN` (app-level, not a function secret) | **CONFIGURE** (client build config) | Same DSN used for staging can be reused (environment-tagged), or a decision to separate — founder call, not inferred (see Phase 8). |
| `APP_ENV` | **CONFIGURE** | Must resolve to `production` in the real production build; today's bundled `.env` reads `local` and already points its `SUPABASE_URL` at this same production project (pre-existing, unrelated to this workstream — noted as ambient context). |
| Supavisor/pooling | **NO_CHANGE** | Already configured and live; same pattern staging validated (transaction-mode pooler for runtime; direct host is IPv6-only exactly as staging's was, so any future production-side admin/migration connection should use the pooler too). |
| Postgres version | **NO_CHANGE** | `17.6.1.127` vs. staging's `17.11.0.002` — same major version; not expected to matter for this migration set. |

**STAGING→PRODUCTION DELTA UNDERSTOOD: YES.**

## Phase 4 — Data safety / backup precheck

Re-verified live via the Management API (`GET /database/backups`), cross-referenced against this engagement's own earlier backup-recovery workstream (`production-readiness-results/backup-recovery/`), whose most recent dated entry (`BR_recovery_runbook.md`, 2026-09-08) **supersedes** that workstream's own earlier static-review report (`BR_production_readiness_report.md`, 2026-09-04, which recommended NO-GO specifically because the backup configuration was then still unverified from source — that unknown is exactly what the later wave closed with live evidence).

- **`walg_enabled: true`, `pitr_enabled: false`** — confirmed live, today. Matches the recovery runbook's own documented posture exactly.
- **Backup type**: daily automated physical (WAL-G) backups. 7 consecutive `COMPLETED` backups observed, `2026-09-27` through `2026-10-03` (most recent ~13 hours before this check).
- **A real restore has already been demonstrated** — not hypothetical. Per `BR_recovery_runbook.md`: on 2026-09-08 the founder restored a real `COMPLETED` production backup into an isolated project and this engagement independently ran a 14-point behavioral recovery suite against the real restored data (23 users, 43 `cycle_entries`, etc.) — 12/14 full pass, 2 expected/schema-level pass, zero new defects. The temporary restore project was deleted afterward by the founder. **`BR-001` (backup existence/config) and `BR-008` (restore ever demonstrated) are both closed**, with evidence, not assumed.
- **RPO**: ~24 hours for production user data (daily backups, no PITR) — unchanged from the runbook's own documented figure, re-confirmed live today.
- **RTO**: ~13 minutes measured (real production data, full behavioral validation) per the 2026-09-08 drill; ~2 minutes for schema-only recovery.
- **Restore mechanism, confirmed available two ways**: (1) the Supabase Dashboard's "restore to new project" action (what was actually used in the 2026-09-08 drill), and (2) `POST /v1/projects/{ref}/database/backups/restore` with `{"id": <backup_id>}` (confirmed present and correctly shaped in Supabase's current API spec; not invoked by this workstream).
- **Limitation, stated plainly**: RPO is ~24h, not zero. A migration or deploy that goes wrong between backups could lose up to a day of the 26 real users' activity if a full restore were the only recovery path. For this specific deployment, that risk is mitigated by the migration-safety analysis in Phase 5 (nothing in the pending migrations is destructive) and is not a reason to require a fresh manual backup beforehand — but taking one immediately before deployment (a standard, zero-cost, few-minutes operation) is recommended in the runbook below regardless, as cheap insurance.
- **No additional paid backup service was enabled or recommended** — PITR remains off, consistent with "no paid service change without separate authorization."

**PRODUCTION BACKUP/RECOVERY READY: YES**, on the strength of real, dated, already-executed evidence — not a claim manufactured by this workstream.

## Phase 5 — Migration safety

Static analysis against the **real** production inventory from Phase 2, not a generic review.

- **Canonical baseline: not applicable to production, full stop.** Every `CREATE TABLE` in it is bare (no `IF NOT EXISTS`) because it is a literal capture *of* production's own schema. Running it against production would fail on the first statement (`adah_ledger` already exists) and should never be attempted. The deployment runbook below applies **migrations only**, never the baseline, to production.
- **Migrations #1–#4**: already applied (Phase 2). Each is independently idempotent (`CREATE TABLE/INDEX IF NOT EXISTS`, `IF NOT EXISTS` guards around every `ALTER`/constraint add in `DO $$` blocks, `CREATE OR REPLACE FUNCTION`) — re-running them against production, if ever done by accident, would be a safe no-op. No action needed; included here only to confirm safety, not because they need to run.
- **Migration #5 (`knowledge_base_v1.sql`)**: creates 5 new tables, extension, indexes, RPC. Nothing it touches exists today — a clean, additive `CREATE`. No lock contention with existing tables (no `ALTER` on any pre-existing object).
- **Migration #6 (`...qualification_and_snapshot.sql`)**: `ALTER TABLE`s two of the KB tables migration #5 *just* created (not pre-existing production tables), plus creates `kb_snapshot_registry` and the two retrieval functions. Same safety profile as #5 — nothing pre-existing is touched.
- **Migration #7 (`...relevance_anchor.sql`)**: `CREATE OR REPLACE FUNCTION`, same signature — safe, additive.
- **Lock/downtime characteristics**: all three pending migrations are `CREATE TABLE`/`CREATE INDEX`/`CREATE FUNCTION` against objects that don't yet exist — no `ALTER TABLE` on a populated table, so no table-rewrite lock and no meaningful downtime expected. This is a materially lower-risk migration shape than #3 was (which did `ALTER`+`UPDATE` a populated, live table) — and #3 already succeeded in the past.
- **Ordering**: must apply in filename/timestamp order (#5 before #6 before #7) — #6 and #7 both depend on objects #5 creates. This is the same order already proven, twice now (local CI's `validate_migrations.sh`/`bootstrap_local_dev.sh`, and the full staging deployment), never deviated from.
- **No destructive or ambiguous behavior found in the pending migrations.** No `DROP TABLE`, no `DROP COLUMN`, no data-loss statement of any kind in #5/#6/#7.

**MIGRATION PLAN SAFE: YES.** No blocker identified.

## Phase 6 — KB production deployment plan (prepared, not executed)

Reuses the exact, CI-proven pipeline (`scripts/deploy_kb_v1.sh`'s steps, exactly as executed for real against staging in the prior workstream) — not reinvented:

1. `python3 scripts/verify_kb_review_packets.py`
2. `python3 scripts/build_kb_production_candidates.py` — materializes exactly 211 eligible + 43 quarantined from `PRODUCTION_DISPOSITION_MASTER.csv`.
3. `python3 scripts/render_kb_seed_sql.py` — renders `PRODUCTION_KB_SEED.sql`, deterministic from the frozen snapshot.
4. Apply migrations #5, #6, #7 only (in order) directly via SQL against production's connection (pooler, session-mode if available, else transaction-mode with single-statement execution per the staging precedent) — **never** `supabase db push`'s own tracking (Phase 2's caveat).
5. Load `PRODUCTION_KB_SEED.sql` — loads only the 211 eligible rows; the 43 fail-closed rows are never loaded (quarantine stays non-authoritative by construction, not by a runtime filter).
6. Run `scripts/verify_kb_live.sql` — hard gate: 211 = 74 Health/Safety + 137 Fiqh, publication/source clean.
7. Run `scripts/verify_kb_retrieval_live.sql` — hard gate: Madhhab isolation, Arabic routing, cross-Madhhab leak check, low-relevance fail-closed.
8. Confirm snapshot activation: the seed SQL itself sets `is_current = true` for commit `eda4b96c7b2a77924a3dd86397cbcbba671440b3` — no separate activation step; `assertSnapshotHealth()` enforces this at request time regardless.
9. Qualification fidelity: re-run the same 4-case check already validated on staging (`HL-MENS-002` et al.) against production once functions are live.
10. Madhhab isolation: re-run the same per-Madhhab + cross-leakage cases already validated on staging.
11. Fail-closed confirmation: the 43 quarantined rows are structurally absent from `knowledge_items` — "cannot answer authoritatively" is a property of what was loaded, not a runtime check to pass or fail.

**No production KB write occurred in this phase.** **KB DEPLOYMENT PLAN READY: YES.**

## Phase 7 — Edge Function deployment plan (prepared, not executed)

| Function | Source commit | Required secrets | Deployment method | Post-deploy health check | Rollback method |
|---|---|---|---|---|---|
| `ai-assistant-chat` | same validated staging commit | `OPENAI_API_KEY`, `OPENAI_MODEL` (new); existing platform-injected `SUPABASE_*` | `npx supabase functions deploy ai-assistant-chat --project-ref jkmjobvxfrmuwafczvtw --use-api` | `GET /functions/ai-assistant-chat` → `status: ACTIVE`; one real synthetic-user smoke call | Re-deploy the prior (Gemini-based) source from git history via the same `--use-api` command — see Phase 10 |
| `dr-niswah-chat` | same | same, plus KB tables must exist first (retrieval is one of its two KB domains) | same pattern | same, plus confirm `knowledgeGrounded` responds correctly | same |
| `dream-interpreter-chat` | same | same | same pattern | same | same |
| `fiqh-advisor-chat` | same | same, plus KB tables must exist first | same pattern | same, plus one real per-Madhhab smoke call | same |

**Deployment order**: KB migrations + seed (Phase 6) **before** any Edge Function deploy — `dr-niswah-chat`/`fiqh-advisor-chat` call `retrieveKnowledge()`, which degrades safely to "no evidence" if the KB tables don't exist yet, but there is no reason to deploy functions ahead of their own data dependency. Within the 4 functions, no inter-function dependency exists — any order among them is fine; deploying the two KB-dependent ones (`dr-niswah-chat`, `fiqh-advisor-chat`) last is a reasonable default.

**Preferred deployment method, matching the already-validated staging path exactly**: `--use-api`, avoiding any Docker dependency. No production function deployment occurred in writing this plan.

**EDGE FUNCTION PLAN READY: YES.**

## Phase 8 — Secret / configuration plan (names and sources only — no values)

| Secret / config | Currently on production? | Classification | Note |
|---|---|---|---|
| `OPENAI_API_KEY` | No | **Should be separately provisioned** | The staging key was reused for staging by founder decision; whether production reuses the *same* key or gets its own, with its own spending cap, is a **separate founder decision** this workstream does not make. Given production has real users (26, not synthetic), a production-specific key with its own cap is the more conservative default to recommend — but the actual choice is the founder's. |
| `OPENAI_MODEL` | No | **Requires founder input** (the identifier itself isn't secret, but which model to run in front of real users is a product decision) | Same identifier validated on staging is the natural default; stated as a recommendation, not decided here. |
| `GEMINI_API_KEY` | Yes, currently live | **Manual decision required** | Leave in place (harmless, unused post-cutover) or remove — founder call, not inferred. |
| Supabase runtime credentials (`SUPABASE_URL`/`ANON_KEY`/`SERVICE_ROLE_KEY`/`DB_URL`/etc.) | Yes, platform-injected | **Already exists, can safely be reused** | These are automatic on every Supabase project; no action needed. |
| Legacy vs. new-format API keys | Both currently enabled | **Manual decision required** | Disabling legacy keys (as staging did) is not this workstream's call for production. |
| `SENTRY_DSN` | Not a function secret (it's app/client build config) | **Can safely be reused, or separately provisioned** | Same DSN as staging with `environment=production` tagging (the code already supports this via `AppEnvironment.isProduction`), or a dedicated production Sentry project — founder call. |
| `APP_ENV` | N/A (build-time, not a stored secret) | **Must be set at build time** | Must resolve to `production` via `--dart-define=APP_ENV=production` for any real production build — the bundled `.env` fallback (`development`) must never be what a real release build ships with. |

**No staging secret was copied into production by this workstream.** **SECRET/CONFIG PLAN READY: YES** (the plan is ready; two items explicitly require founder input before execution, which is expected and correctly flagged, not a gap in the plan itself).

## Phase 9 — Deployment order (runbook)

See `PRODUCTION_DEPLOYMENT_RUNBOOK.md` (updated this pass) for the full, exact, ordered procedure. Summary of the ordered stages and reversibility:

| Stage | Reversible? |
|---|---|
| PRE-DEPLOY CHECK | N/A (read-only) |
| BACKUP/RECOVERY CONFIRMATION | N/A (read-only; recommend one fresh manual backup, cheap and non-disruptive) |
| MIGRATIONS (#5–#7 only) | Reversible — all additive; a down-migration dropping only the new objects is possible if ever needed (none written yet, not required unless requested) |
| SCHEMA VERIFICATION | N/A (read-only) |
| KB LOAD | Reversible — re-running the seed script is idempotent (render_kb_seed_sql.py is deterministic); deleting the loaded rows is also possible without touching any other table |
| SNAPSHOT ACTIVATION | Reversible — re-registering a different `is_current` row, or simply having no eligible rows, makes retrieval fail closed rather than broken |
| KB VERIFICATION | N/A (read-only) |
| SECRETS | Reversible — `supabase secrets set`/unset at any time |
| EDGE FUNCTIONS | **Forward-fix only in the strict sense** — there is no platform "revert to version N" button (confirmed: the Management API has no endpoint for it); rollback means re-deploying the prior source from git history as a new deploy. See Phase 10. |
| FUNCTION HEALTH | N/A (read-only) |
| REAL OPENAI SMOKE TEST | N/A (read-only) |
| FIQH / HEALTH / QUALIFIED HEALTH / FAIL-CLOSED / MADHHAB BOUNDARY / URGENT HEALTH smoke tests | N/A (read-only, synthetic) |
| SENTRY PRODUCTION TEST | N/A (read-only verification of an already-reversible, non-destructive test event) |
| POOLING TEST | N/A (read-only, synthetic load) |
| POST-DEPLOY HEALTH CHECK | N/A (read-only) |

## Phase 10 — Rollback plan

See `PRODUCTION_ROLLBACK_RUNBOOK.md` (new this pass) for the full decision tree. Every mechanism named there was independently confirmed available in this workstream (not assumed):

- **Migration failure**: additive-only DDL; a failure mid-migration leaves at most a partially-created *new* object, never a corrupted *existing* one. Fix forward (correct and re-run) or manually drop the partial new object — never touches pre-existing tables.
- **KB load failure**: delete the partially-loaded rows (`knowledge_items`/related, all net-new tables) and re-run the deterministic seed script. No pre-existing data involved.
- **Snapshot activation failure**: re-register the correct row as `is_current`, or deliberately leave none current — the system already fails closed in that state (confirmed behavior, not a new mechanism).
- **Edge Function deployment failure/regression**: re-deploy the **prior source** (the currently-live Gemini-based code, at the git commit/tag it was last deployed from — confirmed existing as `pg_get_functiondef`-style introspection isn't needed here since it's TypeScript in git, not DB state) via the same `--use-api` command. **No platform version-revert button exists** — confirmed by checking the Management API's function endpoints directly; the only real mechanism is a fresh deploy of old code. As an extra safety net, this workstream confirmed `GET /functions/{slug}/body` can retrieve the exact currently-deployed bundle before any new deploy overwrites it — recommended as a pre-deployment step in the runbook, independent of git history, in case what's live has ever drifted from what's committed.
- **OpenAI configuration failure**: unset/fix the secret; functions already degrade safely without it (confirmed on staging: static fallback / banner-only / clean 502, never a fabricated answer).
- **Retrieval failure**: already fails closed by design (confirmed extensively on staging) — "rollback" here means fixing the underlying cause, not reverting data.
- **Pooling failure**: not a rollback case — it was validated at concurrency 10/20/40 on staging with 100% success; a production-side pooling issue would be a configuration question (pooler is already active, confirmed Phase 1), not something this plan believes needs a revert path.
- **Sentry/observability failure**: no data-plane impact — fix the DSN/config and redeploy the client build; nothing to roll back server-side.
- **Post-deploy acceptance failure (any smoke test)**: the explicit trigger to stop forward progress and roll back Edge Functions (and, if the KB itself is implicated, deactivate the snapshot) rather than proceed.

**What gets rolled back, how, in what order**: Edge Functions first (fastest, stateless, re-deploy old code), then KB snapshot deactivation if the functions' failure is KB-related, then (only if genuinely necessary — not expected, given the migration-safety analysis) a full database restore from the verified ~13-minute real-data restore path in Phase 4. **DB restore is the last resort, not the first response**, because everything else here is cheaper, faster, and does not risk the ~24h RPO gap.

**ROLLBACK PLAN READY: YES.**

## Phase 11 — Production acceptance matrix (prepared, not executed)

Smallest sufficient post-deploy matrix, reusing the exact case patterns already real-model-verified on staging (not reinvented), synthetic/non-sensitive data only:

| Case | Reuses |
|---|---|
| One ordinary question per Madhhab (4) | Staging's SF01–SF04 |
| Madhhab isolation (cross-leakage attempt) | Staging's SF05 |
| Unresolved-state fail-closed | Staging's SF06 |
| Nifas-adjacent fail-closed | Staging's SF07 |
| Qualification fidelity (all 4 `VERIFIED_WITH_QUALIFICATION` rows, `HL-MENS-002` explicit) | Staging's Phase-1 qualified-health matrix |
| Citation fidelity (one per Madhhab + one qualified Health case) | Staging's Phase-5 citation-shape check |
| Relevance gate (gibberish) | Staging's SH02 |
| Snapshot health (confirm `eda4b96c7b2a...` active) | Staging's Phase 3/9 |
| DB/RPC health (behavioral, not injected this time — production is not the place for a REVOKE/GRANT fault-injection drill) | Confirmed safe behavior already proven on staging; production acceptance only *observes* health, does not *inject* failure |
| OpenAI connectivity (one real minimal call) | Staging's baseline calls |
| Urgent Health behavior | Staging's SH03 |
| Sentry (confirm environment=production tagging reaches a real event) | This workstream's own staging Sentry closure |
| Pooling (light, not the full 10/20/40 staging drill — production's first real exercise should be moderate, not a repeat stress test against live users' shared infrastructure) | Scaled-down version of the staging pooling test |

**No real health data anywhere in this matrix** — every case uses a fresh synthetic Supabase Auth account, exactly as staging did. **POST-DEPLOY ACCEPTANCE PLAN READY: YES.**

## Mandatory observability

Unchanged from the staging closure's own finding: `functions.combined-stats` is confirmed live and working for production too (used throughout this phase's own inventory work), the `flagged_conversations` table exists and would durably capture any urgent production exchange, and the same behavioral fail-closed guarantees apply. **MANDATORY OBSERVABILITY READY: YES.**

---

## Final gates

```
PRODUCTION IDENTITY VERIFIED: YES
PRODUCTION INVENTORY COMPLETE: YES
STAGING→PRODUCTION DELTA UNDERSTOOD: YES
MIGRATION PLAN SAFE: YES
PRODUCTION BACKUP/RECOVERY READY: YES
KB DEPLOYMENT PLAN READY: YES
EDGE FUNCTION PLAN READY: YES
SECRET/CONFIG PLAN READY: YES
ROLLBACK PLAN READY: YES
POST-DEPLOY ACCEPTANCE PLAN READY: YES
MANDATORY OBSERVABILITY READY: YES

TECHNICALLY PRODUCTION-READY: YES

READY FOR PRODUCTION DEPLOYMENT: YES

PRODUCTION DEPLOYMENT AUTHORIZED: NO
```

**Why `READY FOR PRODUCTION DEPLOYMENT` can honestly say `YES` here**, where the staging closure report deliberately said `NO`: that `NO` was about production never having been *provisioned* at all — this workstream is exactly the provisioning *preparation* that closes that gap. Every plan above was built from this project's **real, current, live state** (not assumed from staging), every claimed mechanism (backup restore, rollback, read-only query) was independently confirmed to actually exist, and no blocker was found in the migration safety analysis. Three items remain **founder decisions, not blockers**: the production OpenAI key/cap policy, whether to disable legacy API keys, and whether to reuse or separate the Sentry DSN — all explicitly named in Phase 8, none inferred or decided here.

**`PRODUCTION DEPLOYMENT AUTHORIZED: NO`**, unconditionally, per standing instruction. This report prepares the path; it does not take it.
