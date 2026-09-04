# Backup & Recovery Audit — Phase 1: Discovery

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app + Supabase (Postgres) backend |
| Repository | Niswah (local checkout) |
| Branch | main |
| Commit / Version | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
| Phase | 1 — Discovery |
| Audit date | 2026-09-04 |
| Environment | Static source-code review only. No live database connection, no Supabase dashboard access, no migration execution, no restore test, no rollback exercised. |
| Primary database | PostgreSQL, managed by Supabase |
| Object/file storage | No evidence of Supabase Storage bucket usage found in `lib/` or `supabase/` (not confirmed in scope — see §11) |
| Hosting/provider | Supabase (managed) |
| Backup provider | **UNKNOWN / NOT VERIFIED FROM SOURCE** — see BR-001 |
| Restrictions | Auditor role only: no code changes, no migrations run/rolled back, no live DB connection, read-only static review |
| Report created | `BR_discovery.md` |

Builds directly on prior-wave findings DI-001, DI-002, DI-004, DI-005, and RR-002 (see audit brief). This report does not re-derive those; it extends them into backup/recovery scope.

---

## 1. What this audit could and could not verify from source alone

Supabase automated backups (daily backups, Point-in-Time Recovery) are a **project-dashboard / billing-plan setting**, not something expressed anywhere in a git-tracked repository. Concretely:

- `supabase/config.toml` — **does not exist** anywhere in this repo (`find` for `*.toml` outside `node_modules` returns nothing under `supabase/`). The Supabase CLI's local-dev config file, which sometimes documents `[db.seed]` or environment settings, was never committed.
- No `.env`, infra-as-code (Terraform/Pulumi), or CI/CD workflow references a Supabase project ref, backup schedule, or plan tier.
- No `.github/workflows/` directory exists at all in this repo.

**Conclusion: the actual Supabase billing/plan tier for this project cannot be determined from source.** This matters materially because:
- Supabase's **Free tier has no automated backups at all** (no daily backups, no PITR).
- Supabase's **Pro tier** includes daily backups (7-day retention) by default; **PITR is a separate paid add-on** on top of Pro/Team, with its own retention window (commonly 7–35 days depending on configuration) purchased separately.
- Nothing in this repository states, or implies via any config, which of these applies to Niswah's actual production project.

This audit explicitly does **not** assume either default. It marks the actual backup posture of the production Supabase project as **UNKNOWN / NOT VERIFIED** (see BR-001) rather than inferring from typical behavior of either tier.

---

## 2. Critical Asset Inventory

| Asset ID | Asset | System | Criticality | Source of truth? | Rebuildable? | Backup required? |
|---|---|---|---|---|---|---|
| ASSET-001 | Postgres database (schema + all rows) — 19 documented tables incl. `cycle_entries`, `pregnancy_milestones`, `wellbeing_logs`, `chat_threads/messages`, `private_conversations/messages`, `community_posts/comments/likes`, `profiles`, `users` | Supabase (managed Postgres) | **Critical** — includes health/religious tracking data (`cycle_entries.fiqh_state`), private messages, chat history | YES for all cloud-synced data | **NO** — confirmed by DI-001: replaying tracked migrations against an empty DB fails partway through (10 of 19 `schema.sql` tables have no `CREATE TABLE` in any tracked migration; `20260822014500_niswah_schema_sync_and_indexes.sql` references `prayer_log`/`pregnancy_records`/`cycle_entries` that no prior migration created) | YES |
| ASSET-002 | Local on-device cache — `cycle_entries` equivalent (`niswah_cycle_tracking_logs`) via `shared_preferences` | Device (Android/iOS local storage) | **High** — per DI-002, this is the **authoritative** copy for cycle/haid data whenever remote sync silently fails | Partial — device-local only, no export path found | Partial — only if it also exists server-side, which DI-002 shows is not guaranteed | Not currently designed for — see §4 below |
| ASSET-003 | Local on-device cache — `pregnancy_milestones` (`niswah_pregnancy_tracking_milestones`) via `shared_preferences` | Device | **High** — same local-first/authoritative pattern as ASSET-002 (DI-002) | Partial | Partial | Not currently designed for |
| ASSET-004 | RLS policies, functions, triggers (`handle_new_user`, `trg_touch_private_conversation`) | Supabase Postgres | High — required for the app to function/be secure post-restore | N/A — code, tracked in migrations (where they exist) | Only as complete as the migration history itself (i.e., not fully — same DI-001 gap) | YES |
| ASSET-005 | Supabase project-level configuration (auth provider settings, redirect URLs, storage buckets/policies, Edge Function secrets, region, plan tier) | Supabase dashboard/project settings | High — required to stand the project back up, not just the schema | N/A | **NO** — nothing in repo captures this; dashboard-only | Not verifiable from repo |
| ASSET-006 | Supabase Edge Function `dr-niswah-chat` (source in `supabase/functions/dr-niswah-chat/`) | Supabase Edge Functions | Medium | YES — source is tracked in git | YES (source is in repo, redeployable) | N/A (git is the backup) |
| ASSET-007 | Application secrets (Supabase URL/anon key, Gemini API key, etc.) | Environment/build config | High (required for recovery, not itself "data" to back up) | N/A | Only if documented elsewhere (not found in-repo — see §24) | Out of scope (cross-ref Dependencies/Config audit) |

---

## 3. Backup Mechanism Inventory

| Backup ID | Asset | Mechanism | Provider/tool | Frequency | Retention | Automatic? | Evidence |
|---|---|---|---|---|---|---|---|
| BKP-001 | ASSET-001 (Postgres DB) | **UNKNOWN** — presumed Supabase-managed snapshot/PITR *if* the project is on a paid tier, but this cannot be confirmed from source | Supabase (if enabled) | UNKNOWN | UNKNOWN | UNKNOWN | None found in repo. No `config.toml`, no docs, no README reference. Marked UNKNOWN per audit brief instruction — not assumed. |
| BKP-002 | ASSET-002/003 (local device cache) | Incidental OS-level app-data backup (Android Auto Backup / iOS device backup of `NSUserDefaults`), **not a deliberate app design** | OS-level (Google/Apple), not the app | Whatever cadence the OS/user's cloud-backup settings use | OS-controlled, not app-controlled | Depends entirely on user's device backup settings; the app does not opt in or out explicitly (see §4) | `android/app/src/main/AndroidManifest.xml` has no `android:allowBackup` attribute (Android default = `true`, i.e., included by default); no `NSURLIsExcludedFromBackupKey`/`NSFileProtection`/backup-exclusion code found anywhere in `lib/`, iOS project files, or platform channel code |
| BKP-003 | ASSET-006 (Edge Function source) | Git version control itself | GitHub/local git | On every commit | Full git history | N/A (git, not a "backup" mechanism in the DR sense, but functionally equivalent for source) | `supabase/functions/dr-niswah-chat/index.ts` tracked in repo |
| BKP-004 | ASSET-004 (schema/functions/triggers) | Migration files in `supabase/migrations/` (15 files) | Supabase CLI / git | Ad hoc, on schema change | Full git history of migration files | N/A | Confirmed incomplete per DI-001 — this is a *source* artifact, not a *backup* artifact, and it cannot itself reconstruct the schema (see §5) |
| BKP-005 | ASSET-005 (project config) | None found | N/A | N/A | N/A | NO | No IaC, no exported project settings anywhere in repo |

**No logical dump (`pg_dump`), no physical backup script, no export tooling, no scheduled job definition, and no restore script of any kind exist anywhere in this repository.** Repo-wide search for `pg_dump`, `pg_restore`, `supabase db dump`, `supabase db pull`, `supabase db push` in scripts/docs/configs returned zero matches (only unrelated npm package name collisions — `restore-cursor` — in `package-lock.json`).

---

## 4. Local/On-Device Data Durability Assessment

Per the audit brief, cycle-tracking and pregnancy-tracking data is cached locally via `shared_preferences`:

- `lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart` — stores the full list of cycle logs as one JSON blob under key `niswah_cycle_tracking_logs`.
- `lib/features/pregnancy_tracking/data/datasources/local_pregnancy_tracking_data_source.dart` — stores milestones as one JSON blob under key `niswah_pregnancy_tracking_milestones`.

Both use the Flutter `shared_preferences` plugin (`^2.3.3` in `pubspec.yaml`), which on Android is backed by `SharedPreferences`/an XML file in the app's private data directory, and on iOS by `NSUserDefaults`.

**Android:** `android/app/src/main/AndroidManifest.xml` contains no `android:allowBackup` attribute at all. The Android platform default for this attribute is `true` — meaning, absent an explicit override, this app's private data directory (including the `SharedPreferences` XML files holding cycle/pregnancy data) **is eligible for Android Auto Backup** (to the user's Google account) whenever the OS performs one, with no code in this repo opting in or out of that behavior deliberately.

**iOS:** No `NSURLIsExcludedFromBackupKey` (the runtime API/flag used to exclude a file from iCloud/iTunes device backups) appears anywhere in `lib/`, `ios/`, or platform channel code. No `NSFileProtection` entitlement or backup-exclusion configuration was found in `ios/Runner/Info.plist`, `macos/Runner/*.entitlements`, or elsewhere. `NSUserDefaults` is, by iOS platform default, included in standard device (iCloud/iTunes/Finder) backups unless a developer explicitly marks the underlying file excluded — which this app does not do.

**Assessment:** This app has **never made a deliberate decision** about whether cycle-tracking and pregnancy-tracking data (health and, via `fiqh_state`, religious-observance data) should or should not travel inside OS-level device backups. It is not "backed up by design" — it is backed up **only incidentally**, as a side effect of never having touched the platform defaults, and only if/when the end user's own device has cloud backup enabled at all (many users do not, or exclude specific apps). This is not a reliable, verifiable, or restore-tested backup mechanism for this data — see BR-006.

---

## 5. Migration-as-Recovery-Mechanism Trace (building on DI-001)

Tracing what happens if the full tracked migration sequence in `supabase/migrations/` (15 files, in timestamp order) were run against a genuinely empty Postgres database today:

1. `20260820174500_niswah_production_schema_security.sql` — runs (creates `profiles`, `handle_new_user()` trigger, RLS scaffolding referencing `auth.users`, which is a Supabase-managed schema always present).
2. `20260822014500_niswah_schema_sync_and_indexes.sql` — **fails here**. Per DI-001, this file contains `ALTER TABLE IF EXISTS public.prayer_log RENAME TO prayer_entries`, `ALTER TABLE IF EXISTS public.pregnancy_records RENAME TO pregnancy_milestones`, and `CREATE INDEX ... ON public.cycle_entries(...)`. The `RENAME` statements are guarded by `IF EXISTS` so they no-op silently rather than erroring — but the subsequent `CREATE INDEX ... ON public.cycle_entries` has **no such guard** and requires the table to exist. Since no prior migration created `cycle_entries`, this statement raises `relation "cycle_entries" does not exist` and the migration — and the whole sequence, since Supabase migrations run transactionally/sequentially — **halts here**.
3. Every subsequent migration (`20260822210000` onward, 11 files) is never reached in a from-scratch replay.

**What would actually be needed to recover the schema from this repository alone, if the live database were lost entirely:** the tracked migrations **cannot do it**. The only path that could work today is:
   a. A **fresh `information_schema`-derived dump of the actual live schema**, taken *before* any loss occurs (not present in this repo — `schema.sql` claims to be this, but per DI-001 is a hand-maintained approximation that contradicts the migrations it supposedly matches, e.g. the `cycle_entries.symptoms` `JSONB` vs. `TEXT[]` type contradiction), or
   b. **Manual reconciliation**: an engineer with dashboard/database access would need to reconstruct the missing 10 tables' definitions from Supabase's own PITR/snapshot (if one exists — unknown, see BR-001) or from institutional memory, then patch the migration history, before the app could be redeployed against a fresh project.

**There is currently no artifact in this repository that can rebuild the database from nothing.** If Supabase-side backups also do not exist or are insufficient (unverified — BR-001), a full loss of the live database is **not recoverable using anything in this repository.**

---

## 6. Restore Procedure Inventory

| Asset | Restore method | Required tools | Required permissions | Destination | Estimated steps | Documented? |
|---|---|---|---|---|---|---|
| ASSET-001 (DB) | UNKNOWN — no restore procedure of any kind found in-repo. If Supabase-managed backups exist, restore would be via the Supabase dashboard "Restore" flow, but this repo documents no such runbook, no trigger criteria, no validation steps | Supabase dashboard/CLI (external to this repo) | Supabase project owner/admin access | Same or new Supabase project | Unknown — undocumented | **NO** |
| ASSET-002/003 (local cache) | None — no export/import, no cloud-sync-repair tool, no user-facing "restore my data" flow found in `lib/` | N/A | N/A | N/A | N/A | **NO** |
| ASSET-005 (project config) | None found | N/A | N/A | N/A | N/A | **NO** |

---

## 7. Rollback Inventory

| Change type | Rollback method | Data rollback needed? | Tested? | Limitations |
|---|---|---|---|---|
| Database migration | None — no `down`/reverse migration exists for any of the 15 tracked migrations; Supabase CLI migrations in this repo are forward-only SQL files with no paired rollback script | Varies per migration; YES for DI-005's destructive `DROP TABLE CASCADE` | **NO** — no evidence any migration rollback has ever been exercised (see §8) | No tooling or convention for reverse migrations exists in this repo at all |
| Application release (mobile) | Out of scope for this audit (cross-reference Release/Deployment audit) — no CI/CD or app-store rollback config found in-repo (no `.github/workflows/`) | N/A | Not assessed here | — |
| Config change | Not documented — no config inventory or secret-recovery runbook found | Possibly | NO | — |

---

## 8. Cross-reference: DI-005 destructive migration — was any restore/rollback ever exercised?

`supabase/migrations/20260830140000_community_schema_reset.sql` (per DI-005) drops and recreates `community_posts`, `community_post_comments`/`community_comments`, `community_post_likes`/`community_likes`, justified only by an in-file comment claiming the tables were confirmed empty at authoring time.

Evidence searched for and **not found**:
- No paired rollback/down migration for this file.
- No backup-before-migration artifact (dump, snapshot reference, or even a comment describing one being taken) anywhere in the repo.
- `git log --oneline --all -- supabase/` shows the entire `supabase/` directory (schema, all 15 migrations, functions) was introduced in a **single commit** (`6d59bfe feat: initial clean commit for Niswah mobile app`) with no subsequent history — meaning this repository's git history itself cannot show whether this migration was ever actually applied, rolled back, or restored-from-backup on the live project; that information, if it exists, lives only outside version control (Supabase's own migration-history table / dashboard logs, which this audit was not authorized to query).

**Conclusion: no evidence exists in this repository that any restore or rollback — for this migration or any other — has ever been exercised.** Per the template's Golden Rule ("a backup that has never been restored is an unverified backup"), even if Supabase-managed backups exist for this project, they must be treated as **unverified** until an actual restore is demonstrated.

---

## 9. Disaster-Recovery Runbook / RTO / RPO Search

Searched `README.md`, `MANIFEST.md`, `FLUTTER_UI_PARITY_GUIDE.md`, `haidfigh.md`, `docs/` (`niswah-master-verification-addendum.md`, `UI_PARITY_TEST_PLAN.md`, `parity-checklist.md`), and repo-wide for `backup`, `restore`, `disaster recovery`, `RTO`, `RPO`, `point-in-time`, `PITR`, `rollback`.

**Result: no disaster-recovery runbook, no RTO/RPO target of any kind, and no restore-testing process is documented anywhere in this repository.** The only "restore"-adjacent string found in application code is an unrelated UI label (`profile_screen.dart:1938`, "RESTORE PURCHASE" — an IAP-restore button, not a data-recovery mechanism). Confirmed by search, not assumed.

---

## 10. Recovery Objectives (RPO/RTO)

No RPO or RTO has been defined by any product/business owner anywhere in this repository.

| System | Criticality | RPO | RTO | Owner confirmed? | Notes |
|---|---|---|---|---|---|
| Primary Postgres DB (all cloud data) | Critical | **BUSINESS OWNER DECISION REQUIRED** | **BUSINESS OWNER DECISION REQUIRED** | NO | No target exists to measure against |
| Local on-device cache (cycle/pregnancy) | High | **BUSINESS OWNER DECISION REQUIRED** | **BUSINESS OWNER DECISION REQUIRED** | NO | Currently has no deliberate backup at all (§4) |

---

## 11. Backup Exclusion Inventory

| Asset/data | Excluded intentionally? | Rebuild method | Time to rebuild | Risk |
|---|---|---|---|---|
| Full DB schema (10 of 19 tables) from migrations | NO — not intentional, this is drift (DI-001) | Manual reconciliation against live `information_schema` (if DB still exists) or Supabase PITR (unknown) | Unknown — unbounded without owner access | High |
| Local on-device health data from any deliberate backup design | NO — never addressed, not a conscious exclusion (§4) | None — relies entirely on OS-default behavior, unverified per-user | N/A | Medium (data loss on device loss/reinstall if remote sync also failed, per DI-002) |
| Supabase project-level settings (auth, storage, region, plan tier) | Not documented as excluded or included anywhere | Manual reconstruction from dashboard access / institutional memory only | Unknown | Medium-High |
| Object/file storage (Supabase Storage buckets) | Not confirmed the app uses Storage at all — out of this audit's confirmed scope; flagged as **UNKNOWN**, not "N/A" | N/A | N/A | Unknown — requires confirmation from API/Backend audit whether any bucket exists |

---

## 12. Discovery Execution Log

### Fully reviewed
- `supabase/schema.sql`, all 15 files in `supabase/migrations/`, `supabase/functions/dr-niswah-chat/`
- `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `macos/Runner/*.entitlements`
- `lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart`
- `lib/features/pregnancy_tracking/data/datasources/local_pregnancy_tracking_data_source.dart`
- `pubspec.yaml` (local-storage-relevant dependencies)
- `README.md`, `MANIFEST.md`, `docs/*.md`, `haidfigh.md`, `FLUTTER_UI_PARITY_GUIDE.md`
- Prior-wave reports: `production-readiness-results/database/DI_findings.md`, `production-readiness-results/reliability/RR_findings.md`
- Repo-wide git history for `supabase/` (`git log --oneline --all -- supabase/`)

### Partially reviewed
- Full `lib/` tree — targeted grep for `shared_preferences`/`SharedPreferences` usages and backup-exclusion APIs, not a full file-by-file read of every consumer (out of scope for this audit's domain)

### Structurally scanned only
- `node_modules/`, `build/` directories — confirmed irrelevant (build artifacts / unrelated JS tooling), not analyzed further

### Could not inspect
- Supabase project dashboard (backup schedule, PITR status, plan tier, project settings) — **no live access authorized or available**; this is the central UNKNOWN of this audit (BR-001)
- Live database state (whether `public.users` is populated, actual row counts, whether DI-005's migration was ever truly replayed against non-empty data) — no live DB connection authorized
- Actual end-user device backup settings (whether real users have iCloud/Google backup enabled) — not determinable from source

### Actions performed
| Action | Purpose | Result |
|---|---|---|
| Read `BACKUP_RECOVERY_AUDIT_TEMPLATE_MASTER.md` in full | Establish methodology, IDs, severity model | Done |
| Repo-wide grep for backup/restore/PITR/rollback/disaster-recovery terms | Find any documented backup policy | None found outside prior-audit reports and an unrelated IAP-restore UI label |
| Searched for `supabase/config.toml` and any `*.toml` under `supabase/` | Determine whether Supabase CLI config was committed | Not found |
| Searched `AndroidManifest.xml` for `allowBackup` | Determine Android OS-backup posture | Attribute absent → platform default (`true`) applies |
| Searched for iOS backup-exclusion APIs (`NSURLIsExcludedFromBackupKey`, `NSFileProtection`) | Determine iOS OS-backup posture | Not found anywhere in repo |
| Traced tracked migration sequence in file-order against DI-001's findings | Determine exact failure point of a from-scratch rebuild | Fails at `20260822014500_niswah_schema_sync_and_indexes.sql`'s `CREATE INDEX ... ON public.cycle_entries` |
| `git log --oneline --all -- supabase/` | Look for evidence of restore/rollback history | Single squashed initial commit; no history to inspect |
| Searched for `.github/workflows/`, `pg_dump`/`pg_restore`/`supabase db dump` usage, `*.sh` scripts | Find any backup/export tooling | None found |

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|
| Connecting to the live Supabase database | Explicitly out of scope per audit brief — auditor-only, read-only, no live DB access |
| Running, applying, or rolling back any migration | Explicitly prohibited per audit brief |
| Querying Supabase dashboard/API for backup/PITR status | No credentials provided/authorized; would exceed "static/read-only review only" scope |
| Testing actual device-level OS backup/restore behavior | Requires a live device and real backup cycle; out of scope for a static source review |

---

## 13. Discovery Exit Gate

- [x] Critical assets identified (§2).
- [x] Backup mechanisms mapped (§3) — mapped as **mostly UNKNOWN/absent**, which is itself the key finding.
- [x] Backup scope understood (§11) — understood to the extent determinable; DB backup existence itself unverified.
- [x] RPO/RTO defined or owner gaps documented (§10) — no targets exist; documented as BUSINESS OWNER DECISION REQUIRED.
- [x] Backup frequency/retention mapped — N/A, no backup mechanism confirmed to map.
- [x] Backup location/independence known — N/A, same reason.
- [x] Backup monitoring known — confirmed absent (no monitoring possible for an unconfirmed mechanism).
- [x] Restore procedures identified (§6) — confirmed **none exist** in-repo.
- [x] Restore dependencies identified (§6, §9) — Supabase account/dashboard access is the sole path, undocumented.
- [x] Rollback mechanisms mapped (§7) — confirmed **none exist** for any tracked migration.
- [x] Recovery scenarios identified — see `BR_findings.md` finding register and scenario table in the final report.
- [x] Recovery owners identified — **none found**; no ownership documentation exists anywhere in repo.
- [x] Unknown recovery areas explicitly listed (§1, §9, §12 "Could not inspect").

Phase 1 (Discovery) is complete.
