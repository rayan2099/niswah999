> ⚠️ **PROPOSED — NOT IMPLEMENTED.** This remediation plan is a design document only. No backup, restore, retention, rollback, or manifest/plist change described below has been made. Backup/restore/retention changes affect production data safety and must be reviewed and executed separately, by someone with authorized live-environment access. Nothing in this document should be described as recoverable or verified until Phase 2B controlled restore validation actually succeeds.

# Backup & Recovery Audit — Phase 3: Remediation Design

| Field | Value |
|---|---|
| System | Niswah |
| Phase | 3 — Remediation Design (proposed only) |
| Audit date | 2026-09-04 |

---

## Root-Cause Map

| Finding | Recovery gap | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| BR-001 | DB backup existence/config unknown | Backup posture was never established as a documented, verified project decision; it exists only as an implicit dashboard setting nobody has recorded | High | DI-001 (schema drift), BR-002, BR-008 | R1 |
| BR-002 | Repo cannot rebuild DB from empty | Migrations were authored reactively (fixing live incidents after the fact, per DI-001's evidence) rather than as a complete, replayable, from-scratch source of truth | High (same root cause as DI-001) | DI-001, BR-001 | R2 |
| BR-003 | Destructive migration has no backup/rollback | No migration-safety policy exists requiring a precondition guard or pre-migration snapshot for destructive DDL | High (same root cause as DI-005) | DI-005, BR-008 | R3 |
| BR-004 | No DR runbook/RPO/RTO | Recovery planning was never scoped as a deliverable; no business owner has been asked to set targets | High | BR-001, BR-002 | R4 |
| BR-005 | Backup failures undetectable | No operational monitoring exists anywhere in the app or infra (compounds RR-002's app-wide silent-failure pattern) | High | RR-002, DI-002 | R5 |
| BR-006 | On-device health data backup posture undesigned | Platform backup defaults (`allowBackup`, `NSUserDefaults` inclusion) were simply never touched or considered during development | High | DI-002 (local-first design) | R6 |
| BR-007 | No IaC/config export for Supabase project | Project was configured directly via dashboard with no export/documentation step ever added | Medium | BR-001 | R7 |
| BR-008 | No restore ever demonstrated | No restore test has ever been scheduled or required as part of any release process | High | BR-001, BR-002, BR-003 | R8 |

---

## R1 — Resolve BR-001: Verify and document actual Supabase backup/PITR configuration

- **Actions:**
  1. A team member with Supabase dashboard/account access checks **Project Settings → Database → Backups** and records: plan tier, whether daily backups are enabled, retention window, whether PITR is purchased and its retention window.
  2. Document this in a new `docs/backup-recovery-runbook.md` (or equivalent), including the date checked and who checked it — this becomes the authoritative BKP-001 record referenced by `BR_discovery.md` §3.
  3. If the project is on Free tier (no backups) or backups are disabled, **escalate as an immediate, standalone launch blocker** independent of this document — upgrade the plan or configure backups before proceeding to R8.
- **Assets:** ASSET-001.
- **RPO impact:** Establishes what RPO is actually achievable today (previously unknown).
- **RTO impact:** Establishes what RTO is actually achievable today (previously unknown).
- **Risk:** Low (read-only dashboard check + documentation).
- **Rollback:** N/A (documentation-only step).
- **Retest:** Re-verify quarterly, or whenever the Supabase plan changes.

---

## R2 — Resolve BR-002: Produce a genuinely replayable schema rebuild path

- **Actions:**
  1. Take a live `information_schema`/`pg_dump --schema-only` export of the actual current production schema (requires live DB access — coordinate with whoever performs R1; this specific step is itself the first concrete recovery-relevant action this repo has never had).
  2. Reconcile that export against `schema.sql` and all 15 tracked migrations, resolving every contradiction DI-001 already documented (e.g., `cycle_entries.symptoms` type mismatch).
  3. Produce either (a) a corrected, complete, and gap-free migration sequence that successfully replays end-to-end against a fresh empty Postgres database, or (b) a single authoritative `schema.sql`-based bootstrap script, tested by actually running it against an empty database and confirming the app can start against the result.
  4. Add this replay test as a required, repeatable check (e.g., a script or CI job that spins up a throwaway Postgres and replays the migration sequence) so this regresses loudly, not silently, in the future.
- **Assets:** ASSET-001, ASSET-004.
- **RPO impact:** Converts "no recovery path" into "recovery possible, bounded by whatever RPO the backup mechanism from R1 provides" — this step alone does not achieve a good RPO on its own; it is the precondition for *any* recovery working at all if live backups are also unavailable.
- **RTO impact:** Currently unbounded/unknown; a tested from-empty rebuild gives a measurable floor.
- **Risk:** Medium — requires live schema access; must be done read-only (schema export only, no data mutation).
- **Rollback:** N/A (produces new artifacts, does not modify production).
- **Retest:** Re-run the replay test on every new migration before merge, going forward.
- **Cross-reference:** Coordinate with `production-readiness-results/database/DI_remediation_plan.md` R1 — do not duplicate that effort; this item additionally requires the rebuild to be *proven* via an actual empty-DB replay, not just internal-consistency review.

---

## R3 — Resolve BR-003: Add enforced safety guards to destructive migrations, past and future

- **Actions:**
  1. For `20260830140000_community_schema_reset.sql` specifically: since it has (per its own comment) already been applied, mark it explicitly as historical/already-applied and not intended for replay (e.g., a header comment plus, if the team adopts a migration-tracking convention, recording it as already-run so a fresh-environment bootstrap does not re-attempt a risky drop).
  2. Adopt a going-forward policy: any future destructive migration (`DROP TABLE`, `DROP COLUMN`, bulk `DELETE`/`TRUNCATE`) must include an enforced SQL-level precondition (e.g., `DO $$ BEGIN IF EXISTS (SELECT 1 FROM <table> LIMIT 1) THEN RAISE EXCEPTION 'refusing to drop non-empty table'; END IF; END $$;`) rather than a comment-only assertion.
  3. Require a recorded pre-migration backup/snapshot reference (even just a dashboard-generated manual backup timestamp, logged in the migration's commit message or an accompanying doc) before any destructive migration is applied to a populated environment.
- **Assets:** `community_posts`, `community_comments`, `community_likes`, and all future destructive migrations.
- **RPO/RTO impact:** Bounds future destructive-migration risk to "backup taken immediately before" rather than "whatever the last scheduled backup was."
- **Risk:** Low (guard-adding is additive; historical-marking is documentation-only).
- **Rollback:** N/A for the historical-marking step; guard-adding migrations are themselves reversible by dropping the guard.
- **Retest:** Verify the guard actually blocks a drop against seeded non-empty test data before relying on it.
- **Cross-reference:** `DI_remediation_plan.md` R5 covers the DI-005 finding from the data-integrity angle; this item is the backup/recovery-specific half (pre-migration backup + rollback expectation).

---

## R4 — Resolve BR-004: Author a minimal disaster-recovery runbook and obtain RPO/RTO targets

- **Actions:**
  1. Get RPO and RTO targets for the primary database from a business/product owner — do not invent them. At minimum, cover: accidental row/bulk deletion, bad migration, full DB loss.
  2. Author a runbook (`docs/backup-recovery-runbook.md`, can be the same file as R1's documentation) covering, per template §67, for each scenario: trigger, owner, required access, backup selection, exact restore steps, validation checks, rollback-if-restore-fails, and completion criteria.
  3. Assign a named primary and backup recovery owner with confirmed Supabase account access (populate `OWNER-xx` — currently empty in this repo).
- **Assets:** All.
- **RPO/RTO impact:** Converts undefined targets into measurable, owner-approved ones.
- **Risk:** Low (documentation/process only).
- **Rollback:** N/A.
- **Retest:** Review/refresh the runbook at least every 6 months or after any major schema change.

---

## R5 — Resolve BR-005: Make backup (and general operational) failure observable

- **Actions:**
  1. Once R1 confirms what backup mechanism exists, configure Supabase's own backup-status notification (if available on the confirmed plan) to route to a monitored channel (email/Slack) rather than relying on anyone checking the dashboard manually.
  2. Independent of backup-specific monitoring, adopt a crash-reporting/structured-logging solution for the app itself, since RR-002 already establishes the app currently discards all uncaught errors app-wide — this is a prerequisite for ever detecting a backup-adjacent client-side failure (e.g., local cache growing unboundedly, sync failures) and is properly owned by the Reliability/Observability audits, but is listed here because BR-005 cannot be closed without it.
- **Assets:** ASSET-001.
- **Risk:** Low-medium depending on the logging/monitoring solution chosen (must not log secrets — cross-reference Security audit).
- **Rollback:** Standard feature-flag/config rollback for whatever monitoring tool is chosen.
- **Retest:** Simulate a backup-failure notification (or, at minimum, confirm the notification channel receives a test event) before relying on it.
- **Cross-reference:** RR-002 (Reliability), Observability audit (Wave 3, primary owner of general operational-visibility remediation).

---

## R6 — Resolve BR-006: Make a deliberate decision about local health-data OS backup inclusion

- **Actions (pick one, as a product decision — not prescribed here):**
  - **Option A — Exclude:** Set `android:allowBackup="false"` (or use `android:fullBackupContent` to selectively exclude the relevant `SharedPreferences` file) in `android/app/src/main/AndroidManifest.xml`, and mark the underlying `NSUserDefaults`-backed file `NSURLIsExcludedFromBackupKey = true` on iOS, if the product decision is that health/religious data should never leave the device via OS backup channels.
  - **Option B — Explicitly allow:** Document, in the same runbook as R4, a conscious decision that this data is low-sensitivity enough (or that users benefit more from device-restore continuity) to remain in default OS backup scope, and record who approved that framing (cross-reference Privacy/Compliance audit for a sign-off, given `fiqh_state` is religious-observance data).
  - Either option **must be a recorded decision**, not left as an unexamined default, given this data currently sits in the local-first "authoritative" tier per DI-002.
- **Assets:** ASSET-002, ASSET-003.
- **Risk:** Low (manifest/plist attribute change or documentation-only); if Option A is chosen, confirm it doesn't unintentionally break the intended "local-first" resilience story RR-004 already credits it for.
- **Rollback:** Manifest/plist attribute revert.
- **Retest:** If Option A: install app, populate local cache, trigger an OS backup, restore to a fresh device, confirm the file is genuinely absent. If Option B: no restore test needed, but the decision documentation should be reviewed alongside the Privacy audit.

---

## R7 — Resolve BR-007: Document Supabase project-level configuration for recovery

- **Actions:**
  1. Produce a non-secret inventory (in the R4 runbook) of everything needed to stand up a fresh Supabase project matching production: region, auth provider settings, redirect URLs/deep-link scheme (`niswah://login-callback`, already visible in `AndroidManifest.xml`), storage bucket names/policies if any exist (confirm with API/Backend audit whether Storage is used at all), and a list of required Edge Function secret **names** (never values) for `dr-niswah-chat`.
  2. Confirm and record who currently holds Supabase account/organization-owner access, and ensure at least one backup owner also has it (avoid single-point-of-access risk).
- **Assets:** ASSET-005.
- **Risk:** Low (documentation only; explicitly exclude secret values per template §24/§80.6).
- **Rollback:** N/A.
- **Retest:** N/A (documentation freshness review alongside R4).

---

## R8 — Resolve BR-008: Execute a real controlled restore test

- **Actions:**
  1. Only after R1 confirms a backup mechanism actually exists: select an isolated restore destination (a throwaway Supabase project or local Postgres instance) — **never production**.
  2. Restore the most recent available backup/PITR point there.
  3. Validate: schema present, representative record counts, key relationships intact (e.g., a `cycle_entries` row's `user_id` FK resolves), and that the app can plausibly start against the restored schema.
  4. Record start/end time (feeds the RTO figure R4's runbook needs), and document the result — pass, fail, or inconclusive — per template §48's Controlled Restore Matrix.
  5. Repeat this test periodically (e.g., quarterly) — a one-time pass does not remain valid indefinitely.
- **Assets:** ASSET-001.
- **Risk:** Low if genuinely isolated; **high if accidentally pointed at production** — the destination must be triple-checked before executing.
- **Rollback:** N/A (restore target is disposable/isolated).
- **Retest:** Recurring, per above.

---

## Remediation Phase Table

| # | Action | Findings closed | Assets | RPO impact | RTO impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|
| R1 | Verify/document Supabase backup config | BR-001 | ASSET-001 | Establishes baseline | Establishes baseline | Low | N/A | Quarterly |
| R2 | Produce tested from-empty schema rebuild | BR-002 | ASSET-001, ASSET-004 | Enables any recovery at all | Gives measurable floor | Medium | N/A | On every migration |
| R3 | Guard destructive migrations + pre-migration backup policy | BR-003 | Community tables + future | Bounds future loss | Bounds future loss | Low | Guard is reversible | Before each destructive migration |
| R4 | DR runbook + RPO/RTO from owner | BR-004 | All | Defines target | Defines target | Low | N/A | Every 6 months |
| R5 | Backup + operational failure observability | BR-005 | ASSET-001 | Prevents silent drift beyond target | Prevents silent drift | Low-Medium | Standard | Before relying on it |
| R6 | Deliberate OS-backup decision for local health data | BR-006 | ASSET-002, ASSET-003 | N/A (local tier) | N/A | Low | Manifest/plist revert | Once, on release |
| R7 | Document Supabase project config (non-secret) | BR-007 | ASSET-005 | N/A | Reduces reconstruction time | Low | N/A | Alongside R4 |
| R8 | Execute real controlled restore test | BR-008 (+ validates R1/R2) | ASSET-001 | Verifies actual RPO | Verifies actual RTO | Low if isolated / High if misdirected | N/A | Quarterly |

---

## Remediation Exit Gate

- [x] Root cause documented for every open finding.
- [x] Backup scope made explicit for every asset (pending R1/R2 execution to move from "documented gap" to "closed").
- [x] RPO/RTO impact defined for each remediation item (targets themselves still require R1/R4 execution — **BUSINESS OWNER DECISION REQUIRED** remains open until then).
- [x] Restore procedure defined (R8) — not yet executed.
- [x] Monitoring defined (R5) — not yet implemented.
- [x] Rollback defined per item above.
- [x] Recovery test defined (R8) — not yet executed.
- [x] Ownership defined as an action item (R4/R7) — not yet assigned in practice.
- [x] No untested "provider handles it" assumption remains **in this document** — but note this plan itself does not resolve BR-001/BR-002/BR-008; it only defines how to. Those findings remain **OPEN** until R1–R8 are actually executed and retested.

**This plan is proposed only. No finding in `BR_findings.md` may be marked Verified Closed until the corresponding remediation item above has been executed and retested against real evidence — a static-review recommendation is not a substitute for a demonstrated restore.**
