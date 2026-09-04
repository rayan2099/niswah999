# Backup & Recovery — Production Readiness Report

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app + Supabase (Postgres) backend |
| Repository | Niswah |
| Branch | main |
| Commit / Version | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
| Phase | Final — Production Readiness Report |
| Audit date | 2026-09-04 |
| Environment | Static/read-only source review only — no live database, no Supabase dashboard, no restore test |
| Primary database | PostgreSQL, managed by Supabase |
| Object/file storage | Not confirmed to be used by the app in reviewed scope (unknown, not verified) |
| Hosting/provider | Supabase (managed) |
| Backup provider | **UNKNOWN / NOT VERIFIED FROM SOURCE** — see BR-001 |
| Restrictions | Auditor-only role: no code/config changes, no migrations run or rolled back, no live database connection, no restore test executed |
| Report created | `BR_production_readiness_report.md` |

---

## Executive Summary

### System
Niswah — women's health/religious-observance tracking mobile app, Flutter client + Supabase Postgres backend.

### Version / Commit
13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f

### Critical assets protected
**0 of 5 confirmed** critical assets (primary DB, on-device health cache, project config, schema/RLS/functions, Edge Function source) have a **verified, demonstrated** backup+restore path. Only the Edge Function source (ASSET-006, trivially — it's just source code in git) is unambiguously recoverable.

### Restore tests
**0 / 0 executed.** No controlled restore test was authorized or performed in this audit (static review only). Phase 2B is explicitly UNTESTED, not passed.

### Verified RPO
**NOT VERIFIED.** No RPO target has been set by any business owner, and the actual backup mechanism (if any) for the primary database is unknown from source.

### Verified RTO
**NOT VERIFIED.** Same reasons as above.

### Open findings
- BR0: **2**
- BR1: **3**
- BR2: **3**
- BR3: **0**
- BR4: **0**

### Critical unknowns
1. **Supabase plan tier / backup configuration for the production project is entirely unverified from source** (BR-001). This is the single most consequential unknown in this audit: Supabase Free tier ships with no automated backups at all; Pro tier ships with daily backups; PITR is a separate paid add-on. Nothing in this repository indicates which applies. This audit explicitly refuses to assume either default.
2. **No restore has ever been demonstrated** for any backup this project may or may not have (BR-008) — per the template's Golden Rule, an unrestored backup is an unverified backup, regardless of what BR-001 turns out to show.
3. **Whether the app uses Supabase Storage (object/file storage) at all** was not conclusively confirmed or ruled out within this audit's scope (flagged in `BR_discovery.md` §11) — recommend the API/Backend audit confirm this so a future backup audit can close the object-storage recovery question definitively.

### Final recommendation
🔴 **NO-GO**

---

## Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| LG-BR-01 | Zero open BR0 | BR-001, BR-002 both open | **FAIL** |
| LG-BR-02 | Zero launch-blocking BR1 | BR-003 (recommended, not hard-blocking), BR-004, BR-005 both launch-blocking and open | **FAIL** |
| LG-BR-03 | Critical assets covered | Primary DB backup status unknown (BR-001); DB not rebuildable from repo (BR-002); local health cache backup undesigned (BR-006) | **FAIL** |
| LG-BR-04 | Critical DB restore verified | Never attempted; no evidence any restore has ever occurred (BR-008) | **FAIL** |
| LG-BR-05 | Critical files/objects recoverable | Object/file storage usage itself unconfirmed in scope | **N/A / UNKNOWN** |
| LG-BR-06 | RPO requirement met | No RPO defined by any owner; actual capability unknown | **FAIL** |
| LG-BR-07 | RTO requirement met/validated | No RTO defined; no timed recovery evidence | **FAIL** |
| LG-BR-08 | Backup failures observable | No monitoring exists; compounds RR-002's app-wide silent-error-discard pattern | **FAIL** |
| LG-BR-09 | Migration recovery safe | DI-005's destructive migration has no enforced guard, no pre-migration backup, no rollback script | **FAIL** |
| LG-BR-10 | Config/infrastructure recovery documented | No runbook, no IaC, no project-config export exists | **FAIL** |
| LG-BR-11 | Recovery ownership assigned | No named recovery owner found anywhere in repo | **FAIL** |
| LG-BR-12 | No critical unknowns | Supabase backup posture and plan tier remain fully unknown (BR-001) | **FAIL** |

**11 of 12 launch gates FAIL** (one N/A pending confirmation elsewhere). Per template §73, any mandatory FAIL prevents GO, and multiple explicit NO-GO criteria are independently triggered (open BR0, no demonstrated restore, backup job could silently fail, critical backup/recovery behavior remains unknown).

---

## Recovery Scenario Summary

| Scenario | RPO achieved | RTO achieved | Restore verified? | Residual risk |
|---|---|---|---|---|
| Accidental row/bulk deletion | UNKNOWN | UNKNOWN | NO | High — no documented recovery path found |
| Database corruption | UNKNOWN | UNKNOWN | NO | High — same as above, compounded by BR-002 |
| Bad migration (e.g., DI-005's destructive drop, if ever replayed against populated data) | UNKNOWN | UNKNOWN | NO | High — no rollback script, no enforced guard, no restore evidence |
| Full DB loss | **None available today** | **Unbounded / not achievable today** | NO | **Critical** — tracked migrations cannot rebuild the schema from empty (confirmed by direct trace); recovery, if possible at all, depends entirely on an unverified Supabase-side mechanism (BR-001) |
| Local on-device cache loss (device loss/reinstall) | Dependent on unverified OS-level backup + whether remote sync had already succeeded | Not applicable (no app-level restore flow) | NO | Medium — DI-002 already shows remote sync can silently fail, making the local copy the only copy for an unknown fraction of entries |
| Failed deployment (mobile release) | Out of scope (cross-reference Release/Deployment audit) | Out of scope | Not assessed here | — |

---

## Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| RISK-BR-001 | BR-001 | BR0 | High (unverified is the default state, not a hypothetical) | If the project is on Free tier or backups are otherwise misconfigured, a full DB loss is permanent, complete, and irreversible | R1 (verify + document + upgrade if needed) | Unassigned | **YES** |
| RISK-BR-002 | BR-002 | BR0 | Certain (confirmed by direct trace, not probabilistic) | Repo alone cannot rebuild the schema after any loss event; recovery depends entirely on unverified external mechanism | R2 (tested from-empty rebuild) | Unassigned | **YES** |
| RISK-BR-003 | BR-003 | BR1 | Low probability of recurrence (specific migration already applied to reportedly-empty tables) but unbounded impact if ever replayed against populated data | Permanent, irreversible loss of all community content | R3 (guard + policy) | Unassigned | **YES** |
| RISK-BR-004 | BR-004 | BR1 | Certain (confirmed absent) | Any real incident would be handled ad hoc, under time pressure, with no agreed process or target | R4 (runbook + owner targets) | Unassigned | **YES** |
| RISK-BR-005 | BR-005 | BR1 | High (compounds already-confirmed RR-002 silent-failure pattern) | A backup could silently stop working indefinitely with no one aware | R5 (monitoring) | Unassigned | **YES** |
| RISK-BR-006 | BR-006 | BR2 | Medium | Sensitive health/religious data's OS-backup exposure is an unexamined default, not a decision | R6 (deliberate decision) | Unassigned | Recommended, not hard-blocking |
| RISK-BR-007 | BR-007 | BR2 | Medium | Project-level reconstruction depends on one or few individuals' account access and memory | R7 (document config, confirm access holders) | Unassigned | Recommended, not hard-blocking |
| RISK-BR-008 | BR-008 | BR2 | Certain (confirmed absent) | Whatever backup capability exists is unverified per the Golden Rule until actually restored | R8 (execute controlled restore test) | Unassigned | **YES** (prerequisite to closing BR-001/BR-002) |

---

## Assessment: Could this database actually be rebuilt from this repository alone if it were lost?

**No.** Tracing the full tracked migration sequence (`supabase/migrations/`, 15 files) against a fresh empty Postgres database in order fails partway through, at `20260822014500_niswah_schema_sync_and_indexes.sql`'s `CREATE INDEX ... ON public.cycle_entries(...)`, because no earlier tracked migration ever creates the `cycle_entries` table (this is a direct extension of DI-001's finding that 10 of 19 documented tables have no `CREATE TABLE` anywhere in tracked history). `schema.sql` cannot substitute for this gap either — DI-001 already establishes it is a hand-maintained approximation that has itself been shown to contradict the live schema it claims to describe.

The only paths that could plausibly restore this database today are entirely **external to this repository**: a Supabase-managed backup/PITR restore (existence and configuration unverified — BR-001), or manual reconciliation by an engineer with prior first-hand knowledge of the live schema's actual current shape. Neither of those is a repository-based guarantee, and neither has ever been demonstrated (BR-008).

---

## Out-of-Scope / Not Verified

- Actual Supabase project plan tier, backup schedule, retention window, and PITR status — dashboard-only, not authorized in this audit.
- Whether the app uses Supabase Storage (object/file uploads) at all — not conclusively confirmed or ruled out in reviewed scope.
- Live database row counts, whether `public.users` is actually populated for real accounts (cross-reference DI-004 — a separate, equally unresolved live-verification requirement).
- Whether DI-005's destructive migration was, in live fact, ever applied against genuinely empty tables (this audit could only confirm the claim is asserted in a comment, not independently verify it against a live audit log).
- Actual end-user device backup settings (iCloud/Google Backup enabled or not) — outside any app-level control or verification.
- Account-level cloud compromise, provider-region disaster, DNS recovery, secrets rotation/recovery — none tested, all out of this static audit's scope.
- Mobile app-store release rollback mechanics — cross-reference Release/Deployment audit.
- Legal/compliance data-retention requirements — not invented or assumed here; cross-reference Privacy/Compliance audit.

---

## Final One-Sentence Recommendation

> Backup & Recovery recommendation: **NO-GO** for commit `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` until findings BR-001 through BR-005 are remediated — specifically, until the actual Supabase backup/PITR configuration is verified and documented (not assumed), a genuinely replayable from-empty schema rebuild path is produced and tested, the DI-005 destructive migration is given an enforced safety guard, a disaster-recovery runbook with owner-approved RPO/RTO exists, backup-failure detection is wired up, and at least one controlled restore test has actually been executed and validated — because at present this system has two open BR0 findings, zero demonstrated restores of any kind, and a completely unverified backup posture for its sole system of record.
