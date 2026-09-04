# Backup & Recovery Audit — Phase 2A: Static Verification & Findings

| Field | Value |
|---|---|
| System | Niswah |
| Phase | 2A — Static Verification (Phase 2B Controlled Restore Validation was **not performed** — no live DB/environment access authorized; see §Phase 2B below) |
| Audit date | 2026-09-04 |
| Environment | Static repo review only |
| Restrictions | No live DB queries, no migration execution/rollback, no restore test, no backup credential access |

Evidence key: 🟥 Confirmed by Restore Test · 🟧 Confirmed by Configuration/Artifact · 🟨 Likely · 🟦 Requires Controlled Restore Test · ⬜ Not Applicable

---

## BR-001 — Supabase backup/PITR configuration for the production project is entirely unverified; plan tier unknown from source

- **Severity:** **BR0 (Critical)** — per template §4 ("restore process is unknown/unworkable") and §73 NO-GO criterion ("Critical backup/recovery behavior remains unknown").
- **Category:** SCOPE-xx / FREQ-xx / RPO-xx
- **Asset/system:** ASSET-001 (primary Postgres DB)
- **Backup source:** UNKNOWN
- **Backup frequency:** UNKNOWN
- **Retention:** UNKNOWN
- **RPO:** UNKNOWN / NOT VERIFIED (no owner target exists either — see BR-004)
- **RTO:** UNKNOWN / NOT VERIFIED
- **Restore method:** UNKNOWN — no documentation found
- **Evidence (🟦 requires controlled verification, cannot be resolved from source):**
  - No `supabase/config.toml` exists anywhere in this repository.
  - No documentation, README section, or code comment anywhere states the Supabase billing/plan tier for this project.
  - Supabase's Free tier ships with **no automated backups**; Pro tier ships with daily backups; PITR is a separate paid add-on with its own retention. All three are materially different recovery postures, and this repo gives no signal which applies.
  - This audit does **not** assume either default, per explicit instruction, and marks this as an unresolved critical unknown rather than a pass or fail.
- **Confidence:** 🟦 Requires controlled restore test / live dashboard verification — cannot be resolved through static review.
- **Launch-blocker status:** **YES.**
- **Remediation category:** Immediate live verification (Supabase dashboard → Project Settings → Database → Backups) — confirm plan tier, backup schedule, and PITR status; document the finding; then execute a real controlled restore test to prove the mechanism actually works. See `BR_remediation_plan.md` R1.

---

## BR-002 — Full database loss is not recoverable from this repository alone (builds on DI-001)

- **Severity:** **BR0 (Critical)**
- **Category:** MIG-xx / REST-xx
- **Asset/system:** ASSET-001, ASSET-004
- **Backup source:** N/A — this finding concerns the *absence* of a repo-based rebuild path, independent of whether Supabase-side backups exist
- **Backup frequency:** N/A
- **Retention:** N/A
- **RPO:** N/A (this path offers zero recovery, not a bounded-loss recovery)
- **RTO:** N/A (undefined/unbounded — manual reconciliation with unknown duration)
- **Restore method:** None usable today
- **Evidence (🟧 confirmed by direct trace):**
  - Replaying the 15 tracked migrations in timestamp order against a fresh empty Postgres database fails at `supabase/migrations/20260822014500_niswah_schema_sync_and_indexes.sql`'s `CREATE INDEX ... ON public.cycle_entries(...)` statement, because no earlier tracked migration ever creates `cycle_entries` (see `BR_discovery.md` §5 for the full step-by-step trace, extending DI-001).
  - 10 of the 19 tables `schema.sql` documents have no `CREATE TABLE` anywhere in tracked migration history (DI-001).
  - `schema.sql` cannot substitute for the missing migrations either: DI-001 documents that it is a hand-maintained approximation that has itself been shown to contradict the live schema it claims to describe (e.g., `cycle_entries.symptoms` declared `JSONB` in `schema.sql` vs. `TEXT[] NOT NULL DEFAULT '{}'` in an applied migration).
  - **This means: if the live Supabase project were deleted, corrupted beyond repair, or otherwise lost, and Supabase-side backups (BR-001) were unavailable or insufficient, there is currently no artifact in this repository capable of rebuilding the schema, let alone the data.** Recovery would require manual reconciliation by an engineer with prior institutional knowledge of the live schema — a single-point-of-knowledge dependency with no fallback documented anywhere.
- **Confidence:** 🟧 Confirmed by direct migration-sequence trace.
- **Launch-blocker status:** **YES.**
- **Remediation category:** Take a live `information_schema`-derived full schema dump now, reconcile it against `schema.sql` and the migration history into one verified source of truth, and add either a complete, replayable migration chain or a tested `schema.sql`-based bootstrap script. See `BR_remediation_plan.md` R2 (cross-references DI-001/DI_remediation_plan.md R1 — do not duplicate that work, but this audit additionally requires the *rebuild path itself* be proven by an actual empty-DB replay test, not just internal consistency).

---

## BR-003 — Destructive migration (DI-005) has no pre-migration backup evidence, no rollback script, and no restore has ever been demonstrated for it

- **Severity:** BR1 (High)
- **Category:** MIG-xx / ROLL-xx
- **Asset/system:** `community_posts`, `community_post_comments`/`community_comments`, `community_post_likes`/`community_likes`
- **Backup source:** None referenced in the migration file itself
- **Backup frequency:** N/A
- **Retention:** N/A
- **RPO:** N/A — an unguarded `DROP TABLE ... CASCADE` replayed against non-empty data is an unbounded-loss event, not a bounded RPO
- **RTO:** UNKNOWN — no documented recovery path if this migration is ever mistakenly replayed against populated data
- **Restore method:** None documented
- **Evidence (🟧 confirmed, extends DI-005):**
  - `supabase/migrations/20260830140000_community_schema_reset.sql` performs `DROP TABLE IF EXISTS community_post_likes CASCADE; DROP TABLE IF EXISTS community_post_comments CASCADE; DROP TABLE IF EXISTS community_posts CASCADE;` guarded only by a comment asserting the tables were empty at authoring time — no SQL-level precondition check (e.g., a row-count guard that would `RAISE EXCEPTION` if non-empty).
  - No paired rollback/down migration exists for this file, nor for any of the other 14 tracked migrations — this repo has no reverse-migration convention at all.
  - No evidence any backup was taken immediately before this migration was applied, and no evidence a restore was ever exercised against it (see `BR_discovery.md` §8) — the entire `supabase/` directory, including this migration, entered git history in a single squashed initial commit, so git itself carries no audit trail of when/how this was actually run against the live project.
- **Confidence:** 🟧 Confirmed (direct SQL text + absence of any restore/rollback artifact).
- **Launch-blocker status:** Recommended pre-launch fix, not a hard BR0 (current live risk is likely already realized/closed per DI-005's own assessment that the tables were empty when run) — but the **file, as committed, remains a live landmine** for any future replay (fresh environment, CI, accidental re-run) with **zero recovery path** if replayed against populated data today.
- **Remediation category:** Add an enforced precondition guard or mark this migration historical/non-replayable; adopt a policy requiring a verified backup immediately before any future destructive migration, plus a tested rollback path. See `BR_remediation_plan.md` R3.

---

## BR-004 — No disaster-recovery runbook, RTO/RPO targets, or restore-testing process exists anywhere in the repository

- **Severity:** BR1 (High)
- **Category:** REST-xx / OWNER-xx
- **Asset/system:** All critical assets (ASSET-001 through ASSET-005)
- **Backup source:** N/A
- **Backup frequency:** N/A
- **Retention:** N/A
- **RPO:** **BUSINESS OWNER DECISION REQUIRED** — not defined anywhere
- **RTO:** **BUSINESS OWNER DECISION REQUIRED** — not defined anywhere
- **Restore method:** Undocumented
- **Evidence (🟧 confirmed by exhaustive search):**
  - Repo-wide search across `README.md`, `MANIFEST.md`, `docs/*.md`, `FLUTTER_UI_PARITY_GUIDE.md`, `haidfigh.md`, and all `.md`/`.sql`/`.yaml`/`.yml`/`.toml`/`.json`/`.dart` files for `backup`, `restore`, `disaster recovery`, `RTO`, `RPO`, `point-in-time`, `PITR` returns **no runbook, no target, no process** — the only "restore" hit in application code is an unrelated in-app-purchase "Restore Purchase" UI label (`lib/features/auth/presentation/screens/profile_screen.dart:1938`).
  - No `.github/workflows/` directory exists — no CI/CD-driven backup verification, no scheduled backup-health check job of any kind.
- **Confidence:** 🟧 Confirmed via exhaustive search, not assumed absent.
- **Launch-blocker status:** **YES** — a system with critical, irreplaceable data (health/religious tracking, private messages) launching with zero documented recovery process, zero recovery-time expectation, and zero assigned recovery owner is a direct match for this template's BR1 definition.
- **Remediation category:** Author a minimal runbook covering at minimum the DB-loss and bad-migration scenarios, get RPO/RTO targets from a business owner, and assign a named recovery owner. See `BR_remediation_plan.md` R4.

---

## BR-005 — Backup failure detectability is unassessable because the backup mechanism itself is unconfirmed; if any backup exists, its failure would be silent

- **Severity:** BR1 (High)
- **Category:** MON-xx
- **Asset/system:** ASSET-001
- **Backup source:** N/A (dependent on BR-001's resolution)
- **Evidence (🟧 confirmed; extends RR-002):**
  - No monitoring/alerting configuration of any kind exists in this repo (no `.github/workflows/`, no cron/scheduled-function definitions, no third-party monitoring integration referenced anywhere).
  - Cross-reference RR-002 (Reliability audit, confirmed): the app has **no crash reporting, no structured logging, and an app-wide uncaught-async-error handler that silently discards every error** (`lib/main.dart:34-61`). Even setting aside whether Supabase-managed backups exist, this app-side operational blindness means that **any** backup-adjacent failure signal that did reach the client (e.g., a sync failure that should have prompted a manual export) would be silently swallowed, consistent with the broader silent-failure pattern DI-002 already documents for live writes.
  - There is no dashboard, alert route, or on-call process referenced anywhere in the repo for "backup job did not run" or "backup is stale."
- **Confidence:** 🟧 Confirmed (absence of monitoring is directly verifiable; RR-002's silent-failure pattern is independently confirmed by a separate audit wave).
- **Launch-blocker status:** **YES** (a backup job — if one exists — that can silently stop is an explicit NO-GO criterion in this template, §73).
- **Remediation category:** Once BR-001 is resolved, wire up Supabase's own backup-status webhook/notification (if available on the confirmed plan tier) to a monitored channel; do not rely on the app itself for this signal given RR-002. See `BR_remediation_plan.md` R5.

---

## BR-006 — On-device health/religious tracking data has no deliberate backup design; it only inherits undocumented OS-default behavior

- **Severity:** BR2 (Medium)
- **Category:** SCOPE-xx / FILE-xx (local storage variant)
- **Asset/system:** ASSET-002 (`cycle_entries` local cache), ASSET-003 (`pregnancy_milestones` local cache)
- **Backup source:** Incidental OS-level app-data backup only (Android Auto Backup / iOS device backup), not an app design decision
- **Backup frequency:** Whatever the end user's own device backup cadence is (fully outside app control)
- **Retention:** OS-controlled, unknown, not app-controlled
- **RPO/RTO:** Not defined; not meaningfully measurable given the mechanism is incidental
- **Evidence (🟧 confirmed):**
  - `lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart` and `lib/features/pregnancy_tracking/data/datasources/local_pregnancy_tracking_data_source.dart` both persist their full data set as a single JSON blob via `shared_preferences`, which per DI-002 is the **authoritative** copy whenever remote Supabase sync silently fails.
  - `android/app/src/main/AndroidManifest.xml` sets no `android:allowBackup` attribute — the Android platform default (`true`) applies, meaning this data is eligible for Android Auto Backup with no deliberate app-level decision either way.
  - No `NSURLIsExcludedFromBackupKey`, `NSFileProtection`, or equivalent backup-exclusion mechanism was found anywhere for iOS — `NSUserDefaults` (the iOS backing store for `shared_preferences`) is included in standard device backups by iOS platform default, again with no deliberate app-level decision.
- **Integrity/compliance risk:** Two-sided. (a) As a *backup*, this is unverifiable, untested, and entirely dependent on individual end users having device-level cloud backup enabled — it cannot be relied upon as a recovery mechanism for this audit's purposes. (b) As a *side effect*, health and religious-observance data (`fiqh_state`) is flowing into OS-level cloud backups (Google/Apple) without the app team ever having made a conscious decision about that — this has a privacy/compliance dimension that should be cross-referenced to the Privacy/Compliance audit; it is flagged here strictly as an unaddressed backup-design gap.
- **Confidence:** 🟧 Confirmed (absence of any manifest/plist/code-level exclusion setting is directly verifiable).
- **Launch-blocker status:** NO independently (bounded — cloud sync, when it works, remains the primary recovery path for this data; DI-002's silent-failure pattern is the more severe compounding issue, already flagged there) — but recommended for explicit product/privacy sign-off before launch given the sensitivity of the data involved.
- **Remediation category:** Make a deliberate, documented decision: either explicitly exclude this cache from OS backups (if treated as sensitive health data that should not silently travel into a personal cloud backup) or explicitly allow it and document why (e.g., framed as a lightweight, low-risk convenience given `shared_preferences` content is already visible in cloud backups the user already controls). See `BR_remediation_plan.md` R6.

---

## BR-007 — No infrastructure-as-code or exported record of Supabase project-level configuration; project reconstruction depends on undocumented dashboard access

- **Severity:** BR2 (Medium)
- **Category:** INFRA-xx / CFG-xx
- **Asset/system:** ASSET-005
- **Evidence (🟧 confirmed by absence):**
  - No Terraform/Pulumi/IaC files, no exported Supabase project-settings JSON/YAML, and no documentation of auth-provider configuration, redirect URLs, storage bucket policies, Edge Function secrets, project region, or plan tier exists anywhere in this repository.
  - `supabase/functions/dr-niswah-chat/` contains only function *source code* — its runtime secrets/environment variables (referenced implicitly by the function but not defined in-repo) are not documented or recoverable from source.
- **Confidence:** 🟧 Confirmed.
- **Launch-blocker status:** NO independently (BR2) — bounded by the fact that, unlike the database, project settings are typically slower-changing and more likely to be recoverable via whoever holds the Supabase account itself, but this is an unverified assumption, not a demonstrated recovery path.
- **Remediation category:** Document (outside of secret values) the required project settings needed to stand up a fresh Supabase project matching production, and identify/confirm who holds account-owner access. See `BR_remediation_plan.md` R7.

---

## BR-008 — No evidence any backup or migration has ever actually been restored (Golden Rule violation)

- **Severity:** BR2 (Medium) — a process/evidence gap rather than a currently-realized loss, but decisive for confidence in every other finding in this report
- **Category:** REST-xx / MIG-xx
- **Asset/system:** All
- **Evidence (🟧 confirmed):**
  - `git log --oneline --all -- supabase/` shows the entire `supabase/` directory was introduced in a single squashed commit (`6d59bfe`), with no subsequent history — the repository itself provides no timeline of when migrations, including DI-005's destructive one, were actually applied to the live project, let alone whether any were ever rolled back or restored from a backup.
  - No restore-test report, no staging-environment rebuild log, and no "we tested this" comment or artifact of any kind exists anywhere in the repo.
- **Confidence:** 🟧 Confirmed (absence directly verifiable; this audit also could not itself perform a restore test, per its read-only mandate — see Phase 2B below).
- **Launch-blocker status:** NO independently, but compounds BR-001 and BR-002 — per the template's Golden Rule, this means **even if Supabase-managed backups exist and are correctly configured, they must be treated as unverified** until a real restore is demonstrated.
- **Remediation category:** Schedule and execute a controlled restore test (isolated destination, not production) as the first concrete remediation action once BR-001's plan-tier question is resolved. See `BR_remediation_plan.md` R1/R8.

---

## Static Verification Matrix

| Check ID | Category | Asset/Scenario | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| SCOPE-01 | Backup scope | Primary Postgres DB | Automated backup/PITR confirmed active | BR-001 | **INCONCLUSIVE** (unverifiable from source) |
| REST-01 | Restore process | Primary Postgres DB, full loss | Repo alone can rebuild schema from empty DB | BR-002 | **FAIL** |
| MIG-01 | Migration recovery | `20260830140000_community_schema_reset.sql` | Backup-before + rollback path for destructive migration | BR-003 | **FAIL** |
| REST-02 | Restore documentation | All critical assets | Documented runbook + RPO/RTO exists | BR-004 | **FAIL** |
| MON-01 | Backup monitoring | Primary Postgres DB | Backup failure observable | BR-005 | **FAIL** |
| SCOPE-02 | Backup scope | Local on-device health cache | Deliberate, documented backup posture | BR-006 | **FAIL** |
| INFRA-01 | Infrastructure recovery | Supabase project settings | Reconstructable from repo/IaC | BR-007 | **FAIL** |
| REST-03 | Restore validation | All backups (if any) | At least one demonstrated successful restore | BR-008 | **FAIL (Golden Rule)** |

---

## Phase 2B — Controlled Restore Validation

**Not performed.** Per the audit brief, this audit is explicitly authorized for static/read-only source review only — no live database connection, no migration execution, no restore test, no rollback of any kind. Every Phase 2B test category (`BR-DB-xx`, `BR-PITR-xx`, `BR-FILE-xx`, `BR-MIG-xx`, `BR-CFG-xx`, `BR-INFRA-xx`, `BR-ROLL-xx`, `BR-DEL-xx`) is therefore **UNTESTED**, not passed and not failed. This is itself the direct cause of BR-001/BR-002/BR-008 being marked as they are, per the template's instruction not to convert lack of access into a PASS.

---

## Finding Register

| Finding ID | Category | Severity | Asset/Scenario | Summary | Launch blocker? | Status |
|---|---|---|---|---|---|---|
| BR-001 | SCOPE/RPO | **BR0** | Primary Postgres DB | Supabase backup/PITR plan tier and configuration entirely unverified from source | **YES** | OPEN |
| BR-002 | MIG/REST | **BR0** | Primary Postgres DB | Full DB loss not recoverable from repo alone — migrations fail against empty DB (extends DI-001) | **YES** | OPEN |
| BR-003 | MIG/ROLL | BR1 | Community tables | Destructive migration has no backup/rollback evidence (extends DI-005) | Recommended | OPEN |
| BR-004 | REST/OWNER | BR1 | All | No DR runbook, RPO/RTO, or restore-testing process exists | **YES** | OPEN |
| BR-005 | MON | BR1 | Primary Postgres DB | Backup failure would be undetectable (extends RR-002) | **YES** | OPEN |
| BR-006 | SCOPE/FILE | BR2 | Local device cache | On-device health data backup posture undesigned, only incidental | NO (recommended) | OPEN |
| BR-007 | INFRA/CFG | BR2 | Supabase project config | No IaC/export of project settings; manual reconstruction only | NO | OPEN |
| BR-008 | REST | BR2 | All | No evidence any restore/rollback ever exercised (Golden Rule) | NO (compounds BR-001/BR-002) | OPEN |

**Totals:** BR0: 2 · BR1: 3 · BR2: 3 · BR3: 0 · BR4: 0
