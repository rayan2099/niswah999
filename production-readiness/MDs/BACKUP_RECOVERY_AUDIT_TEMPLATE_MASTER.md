# Backup & Recovery Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that critical application data, configuration, infrastructure state, and operational records can be recovered after accidental deletion, corruption, failed deployment, infrastructure outage, or operator error.
>
> This template is designed for systems built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark backup/recovery PASS because a provider says “backups enabled,” because snapshots exist, or because rollback commands are documented. Recovery readiness must be demonstrated through evidence and controlled restoration tests whenever practical.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current system can recover safely from realistic failure scenarios by verifying:

- Critical data is included in backup scope.
- Backup frequency matches business recovery expectations.
- Recovery Point Objective (RPO) is defined for critical systems.
- Recovery Time Objective (RTO) is defined for critical systems.
- Backup retention is intentional.
- Backups are stored independently enough to survive primary-system failure.
- Backup access is controlled.
- Backup encryption and secret handling are appropriate.
- Backups are actually being created.
- Backup failures are detectable.
- Restore procedures are documented.
- Restore procedures have been tested.
- Restored data is validated for integrity.
- Application configuration and infrastructure dependencies needed for recovery are known.
- Object/file storage is recoverable where required.
- Database schema/migrations are recoverable.
- Failed deployments can be rolled back.
- Data repair and point-in-time recovery are understood where supported.
- Recovery after accidental delete is understood.
- Recovery after bad migration is understood.
- Recovery after corrupted data is understood.
- Recovery after infrastructure/provider failure is understood.
- AI-generated deployment/database changes have not created undocumented recovery gaps.
- Recovery responsibilities are assigned and operationally actionable.

## 0.2 Non-goals

This audit does **not** replace:

- Security incident response.
- Full business continuity planning.
- Infrastructure high-availability design.
- Reliability/resilience audit.
- Database integrity audit.
- Legal retention review.
- Cyber insurance requirements.
- Formal disaster-recovery certification.

Cross-reference those areas where relevant.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Map critical data, storage systems, backup mechanisms, retention, dependencies, recovery objectives, and rollback capabilities | Backup/recovery map |
| 2A | **Static Verification** | Compare documented backup/recovery design against actual configuration and system dependencies | Recovery evidence matrix |
| 2B | **Controlled Restore Validation** | Execute safe restore/recovery tests in an isolated or approved environment | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design backup/recovery fixes — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence and issue launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**A backup that has never been restored is an unverified backup.**

For every critical recovery claim, distinguish:

- configured,
- observed,
- tested,
- successfully restored,
- validated after restore.

---

# 2. Report Header

Use this header in every phase report:

| Field | Value |
|---|---|
| System | `{SYSTEM_NAME}` |
| Repository | `{REPOSITORY_NAME}` |
| Branch | `{BRANCH}` |
| Commit / Version | `{COMMIT_OR_VERSION}` |
| Phase | `{PHASE_NAME}` |
| Audit date | `{DATE}` |
| Environment | `{Local / Dev / Staging / Production}` |
| Primary database | `{DATABASE}` |
| Object/file storage | `{STORAGE}` |
| Hosting/provider | `{PROVIDER}` |
| Backup provider | `{PROVIDER / BUILT-IN / CUSTOM}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Restore Test** | Proven through successful controlled recovery/restoration |
| 🟧 **Confirmed by Configuration / Backup Artifact** | Proven by provider config, snapshot record, schedule, script, or backup inventory |
| 🟨 **Likely** | Strong inference but restore not proven |
| 🟦 **Requires Controlled Restore Test** | Must be restored/tested before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was disproven |

For every important finding include:

- Finding ID.
- Asset/system.
- Backup source.
- Backup frequency.
- Retention.
- RPO.
- RTO.
- Restore method.
- Evidence.
- Severity.
- Launch-blocker status.
- Confidence.

---

# 4. Severity Model

| Level | Classification | Backup/recovery meaning | Launch treatment |
|---|---|---|---|
| **BR0** | Critical | Critical data can be permanently lost, no usable recovery exists, or restore process is unknown/unworkable | **Mandatory NO-GO** |
| **BR1** | High | Critical backup/recovery capability exists but is materially incomplete, untested, or cannot meet required RPO/RTO | **Pre-launch blocker** |
| **BR2** | Medium | Important recovery gap exists with bounded impact/workaround | Explicit acceptance required |
| **BR3** | Low | Minor backup documentation/retention/recovery issue | Backlog acceptable |
| **BR4** | Observation | Improvement opportunity | Backlog |

## 4.1 Severity factors

Evaluate:

- Data criticality.
- Maximum data loss.
- Recovery time.
- Irreversibility.
- Backup age.
- Restore complexity.
- Dependency on one provider/account.
- Human intervention.
- Detection of backup failure.
- Whether failure impacts one record or entire system.
- Whether backup includes required linked assets/configuration.
- Whether restore creates compatibility issues.

---

# 5. Recovery Objectives

For each critical system define:

## Recovery Point Objective (RPO)

Maximum acceptable amount of data loss measured in time.

Examples:
- 5 minutes,
- 1 hour,
- 24 hours.

Do not invent RPO. If not defined, mark:

**BUSINESS OWNER DECISION REQUIRED**

## Recovery Time Objective (RTO)

Maximum acceptable time to restore service/data.

Do not invent RTO. If not defined, mark:

**BUSINESS OWNER DECISION REQUIRED**

| System | Criticality | RPO | RTO | Owner confirmed? | Notes |
|---|---|---|---|---|---|
| `{SYSTEM}` | `{}` | `{}` | `{}` | `{YES/NO}` | `{}` |

---

# 6. Environment Warning

When testing outside production:

| Dimension | Evaluation |
|---|---|
| Technical severity | Based on recovery gap itself |
| Current actual impact | Based on current environment |
| Production impact | State real data/service consequences |
| Procedural classification | Unresolved BR0/BR1 issues are **Pre-Launch Blockers** |

Never overwrite production data during restore testing without explicit authorization.

---

# PHASE 1 — DISCOVERY

# 7. Objective

Identify every critical asset that must survive loss or corruption.

### Mandatory restrictions

During discovery:

- Prefer read-only inspection.
- Do not trigger production restore.
- Do not alter retention.
- Do not delete backup artifacts.
- Do not rotate backup credentials.
- Do not disable backup jobs.
- Do not test destructive recovery in production.

---

# 8. Critical Asset Inventory

Use stable IDs:

- `ASSET-001`, `ASSET-002`, ...

Potential assets:

- relational database,
- document database,
- object storage,
- user uploads,
- configuration,
- infrastructure definitions,
- application secrets,
- environment config,
- search indexes if non-rebuildable,
- audit logs,
- generated reports,
- queues if durable business state depends on them,
- payment reconciliation data,
- external provider mappings.

| Asset ID | Asset | System | Criticality | Source of truth? | Rebuildable? | Backup required? |
|---|---|---|---|---|---|---|
| `ASSET-001` | `{}` | `{}` | `{}` | `{YES/NO}` | `{YES/NO/PARTIAL}` | `{YES/NO}` |

---

# 9. Backup Mechanism Inventory

| Backup ID | Asset | Mechanism | Provider/tool | Frequency | Retention | Automatic? | Evidence |
|---|---|---|---|---|---|---|---|
| `BKP-001` | `{ASSET}` | `{SNAPSHOT/PITR/EXPORT/etc.}` | `{}` | `{}` | `{}` | `{YES/NO}` | `{}` |

Include:

- automated snapshots,
- point-in-time recovery,
- logical dumps,
- physical backups,
- storage versioning,
- object lifecycle/versioning,
- file replication,
- infrastructure-as-code repository,
- config exports.

---

# 10. Backup Scope Inventory

Verify exactly what is included:

- schema,
- data,
- users,
- roles,
- extensions,
- stored procedures,
- triggers,
- indexes,
- object metadata,
- uploaded files,
- encrypted content,
- application settings,
- provider configuration where exportable.

Flag “database backup” assumptions that omit files/storage required by the application.

---

# 11. Backup Exclusion Inventory

Explicitly list what is not backed up.

| Asset/data | Excluded intentionally? | Rebuild method | Time to rebuild | Risk |
|---|---|---|---|---|
| `{}` | `{YES/NO}` | `{}` | `{}` | `{}` |

---

# 12. Backup Frequency Inventory

Compare backup schedule against RPO.

| Asset | RPO | Backup/PITR frequency | Meets RPO? | Evidence |
|---|---:|---:|---|---|
| `{}` | `{}` | `{}` | `{YES/NO/UNKNOWN}` | `{}` |

---

# 13. Retention Inventory

Document:

- short-term,
- daily,
- weekly,
- monthly,
- annual retention where applicable.

| Backup | Retention | Reason | Owner approved? | Legal/compliance dependency? |
|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{YES/NO}` | `{}` |

Do not invent legal retention requirements.

---

# 14. Backup Location / Independence Inventory

Determine whether backup is:

- same region,
- separate region,
- same cloud account,
- separate account,
- same credentials,
- immutable,
- replicated.

Flag backups that would be lost with the same failure that destroys primary data.

---

# 15. Backup Access Inventory

Document:

- who can view,
- who can restore,
- who can delete,
- who can change retention,
- service account involved.

Security specifics should be cross-referenced to Security Audit.

---

# 16. Backup Encryption Inventory

Verify whether backup is:

- encrypted at rest,
- encrypted in transit,
- uses provider-managed key,
- customer-managed key,
- key dependency documented.

Flag backup that cannot be restored because encryption key dependency is undocumented.

---

# 17. Backup Monitoring Inventory

Document:

- backup success signal,
- backup failure alert,
- stale backup alert,
- storage-capacity alert,
- retention job alert.

Flag backup jobs that can silently stop.

---

# 18. Restore Procedure Inventory

For each critical asset:

| Asset | Restore method | Required tools | Required permissions | Destination | Estimated steps | Documented? |
|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 19. Restore Dependency Inventory

Identify dependencies needed for recovery:

- cloud account access,
- database credentials,
- encryption keys,
- DNS,
- infrastructure definitions,
- runtime version,
- migration tooling,
- package registry,
- storage credentials,
- payment-provider config,
- auth provider configuration.

---

# 20. Point-in-Time Recovery Inventory

Where supported, document:

- retention window,
- granularity,
- restore method,
- restore destination,
- limitations,
- RPO capability.

---

# 21. Rollback Inventory

Document rollback mechanisms for:

- application release,
- database migration,
- infrastructure change,
- feature flag,
- config change,
- mobile/web deployment where applicable.

| Change type | Rollback method | Data rollback needed? | Tested? | Limitations |
|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{YES/NO}` | `{}` |

---

# 22. Migration Recovery Inventory

For destructive/high-risk migrations document:

- backup before migration,
- point-in-time restore,
- reverse migration,
- data backfill rollback,
- deployment sequence,
- compatibility window.

---

# 23. File / Object Storage Recovery Inventory

Verify:

- versioning,
- delete protection,
- retention,
- restore procedure,
- metadata restore,
- signed URL regeneration,
- user ownership references.

---

# 24. Configuration Recovery Inventory

Document recoverability of:

- env variable names,
- secret references,
- feature flags,
- provider settings,
- DNS,
- build config,
- app-store/console config where applicable.

Never include secret values in reports.

---

# 25. Infrastructure Recovery Inventory

Where infrastructure-as-code exists:

- repo,
- state,
- modules,
- provider versions,
- remote state backup,
- required secrets.

Where no IaC exists, document manual reconstruction risk.

---

# 26. Recovery Ownership Inventory

| Recovery area | Primary owner | Backup owner | Escalation | Access verified? |
|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 27. Recovery Scenario Inventory

Use stable IDs:

- `SCN-001`, `SCN-002`, ...

Required scenarios where applicable:

- accidental row deletion,
- accidental bulk deletion,
- corrupted table,
- bad migration,
- failed deployment,
- DB unavailable,
- full DB loss,
- object/file deletion,
- object storage loss,
- application config loss,
- cloud account/provider issue,
- operator mistake,
- compromised credentials causing destructive change,
- external integration state mismatch.

| Scenario ID | Failure | Assets affected | Recovery method | Expected RPO | Expected RTO | Tested? |
|---|---|---|---|---|---|---|
| `SCN-001` | `{}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 28. Discovery Execution Log

### Fully reviewed
`{AREAS}`

### Partially reviewed
`{AREAS}`

### Structurally scanned only
`{AREAS}`

### Could not inspect
`{AREAS + REASON}`

### Actions performed
| Action | Purpose | Result |
|---|---|---|

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|

---

# 29. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Critical assets identified.
- [ ] Backup mechanisms mapped.
- [ ] Backup scope understood.
- [ ] RPO/RTO defined or owner gaps documented.
- [ ] Backup frequency/retention mapped.
- [ ] Backup location/independence known.
- [ ] Backup monitoring known.
- [ ] Restore procedures identified.
- [ ] Restore dependencies identified.
- [ ] Rollback mechanisms mapped.
- [ ] Recovery scenarios identified.
- [ ] Recovery owners identified.
- [ ] Unknown recovery areas explicitly listed.

---

# PHASE 2A — STATIC VERIFICATION

# 30. Objective

Determine whether backup/recovery design is internally consistent and capable of meeting recovery objectives.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `SCOPE-xx` | Backup scope |
| `FREQ-xx` | Frequency |
| `RET-xx` | Retention |
| `RPO-xx` | Recovery point objective |
| `RTO-xx` | Recovery time objective |
| `LOC-xx` | Backup independence/location |
| `ACCESS-xx` | Backup access |
| `ENC-xx` | Backup encryption |
| `MON-xx` | Backup monitoring |
| `REST-xx` | Restore process |
| `PITR-xx` | Point-in-time recovery |
| `ROLL-xx` | Rollback |
| `MIG-xx` | Migration recovery |
| `FILE-xx` | File/object recovery |
| `CFG-xx` | Config recovery |
| `INFRA-xx` | Infrastructure recovery |
| `OWNER-xx` | Recovery ownership |
| `AI-xx` | AI-agent-specific recovery defects |

---

# 31. Backup Scope Verification

For every critical asset verify:

- included,
- intentionally excluded,
- rebuildable,
- dependency on another backed-up asset.

Flag orphan backup design.

Example:

Database restored but user-uploaded files cannot be restored.

---

# 32. RPO Verification

Compare actual backup/PITR capability to required RPO.

If:

`Actual recoverable point > required RPO`

mark FAIL.

If RPO undefined:

mark INCONCLUSIVE and require owner decision.

---

# 33. RTO Verification

Estimate recovery path:

- access,
- provision destination,
- restore backup,
- apply config,
- run migrations if needed,
- verify,
- switch traffic.

If likely recovery exceeds required RTO, record finding.

Do not claim RTO met without timed recovery evidence when critical.

---

# 34. Retention Verification

Check:

- expected restore points available,
- retention not shorter than operational need,
- expired backups removed as intended,
- legal retention questions separated.

---

# 35. Backup Independence Verification

Inspect whether one destructive event can remove both primary and backups.

Risks:

- same account credentials,
- same region only,
- no versioning,
- backup deletion permission same as primary delete.

---

# 36. Backup Monitoring Verification

Verify:

- successful creation observable,
- failed job observable,
- stale backup detectable,
- alert route known.

---

# 37. Restore Documentation Verification

A valid restore procedure should include:

1. prerequisites,
2. required access,
3. backup selection,
4. destination,
5. exact sequence,
6. validation,
7. rollback if restore fails,
8. traffic cutover if applicable.

---

# 38. Restore Compatibility Verification

Check whether backup can restore into:

- current engine version,
- supported runtime,
- expected schema,
- expected application version.

Flag backups with undocumented version dependency.

---

# 39. Migration Recovery Verification

Inspect dangerous migrations for:

- restore point before change,
- rollback method,
- forward-fix alternative,
- compatibility window,
- backup validity.

---

# 40. File/Object Recovery Verification

Verify user-upload recovery independently from DB recovery.

Flag DB references restored but files permanently missing.

---

# 41. Configuration Recovery Verification

Check whether recovery can reconstruct production configuration without relying on one engineer's local files.

---

# 42. Infrastructure Recovery Verification

Assess whether environment can be reconstructed from:

- IaC,
- documented manual steps,
- provider backups,
- account configuration.

Flag undocumented manual-only critical infrastructure.

---

# 43. AI-Agent-Specific Backup & Recovery Audit

Mandatory when AI agents were used.

Actively search for:

## 43.1 Destructive migrations without recovery plan

- drop column/table,
- rename with no compatibility,
- bulk rewrite.

## 43.2 Generated migration chains

- agent produces multiple conflicting migrations,
- rollback scripts missing.

## 43.3 False backup assumptions

- comments say provider handles backups but no evidence,
- README says PITR exists but plan/config unknown.

## 43.4 Local-only recovery scripts

- script depends on local path,
- hardcoded developer machine,
- undocumented credentials.

## 43.5 Config not recoverable

- new environment variables added but no inventory,
- critical feature flag configured only manually.

## 43.6 File-storage omission

- agent backs up DB but ignores user-upload bucket.

## 43.7 Backup bypass during refactor

- new storage/database introduced but backup process still covers old system only.

## 43.8 Unsafe repair scripts

- generated mass update/delete script with no dry run,
- no snapshot prerequisite,
- no verification.

---

# 44. Static Verification Matrix

| Check ID | Category | Asset / Scenario | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 45. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Critical backup scope verified.
- [ ] RPO capability reviewed.
- [ ] RTO path reviewed.
- [ ] Retention reviewed.
- [ ] Backup independence reviewed.
- [ ] Backup monitoring reviewed.
- [ ] Restore procedures reviewed.
- [ ] Migration rollback/recovery reviewed.
- [ ] File/object recovery reviewed.
- [ ] Config/infrastructure recovery reviewed.
- [ ] AI-generated recovery risks reviewed.
- [ ] BR0/BR1 candidates have evidence.

---

# PHASE 2B — CONTROLLED RESTORE VALIDATION

# 46. Objective

Prove that critical backups can actually be restored.

### Mandatory restrictions

- Restore only to isolated/test destination unless explicitly authorized.
- Never overwrite production as part of routine audit.
- Use synthetic or approved data where possible.
- Do not expose backup contents unnecessarily.
- Record start/end time.
- Validate restored data.

---

# 47. Restore Test Categories

| Prefix | Category |
|---|---|
| `BR-DB-xx` | Database restore |
| `BR-PITR-xx` | Point-in-time restore |
| `BR-FILE-xx` | File/object restore |
| `BR-MIG-xx` | Migration recovery |
| `BR-CFG-xx` | Config recovery |
| `BR-INFRA-xx` | Infrastructure recovery |
| `BR-ROLL-xx` | Release rollback |
| `BR-DEL-xx` | Accidental deletion recovery |

---

# 48. Controlled Restore Matrix

| Test ID | Scenario | Backup used | Restore destination | Expected result | Actual result | Restore time | Evidence | Result |
|---|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 49. Database Restore Test

Recommended controlled sequence:

1. Identify backup.
2. Provision isolated restore target.
3. Restore.
4. Confirm schema.
5. Confirm representative records.
6. Confirm relationships.
7. Start compatible application if safe.
8. Execute read tests.
9. Execute controlled write if allowed.
10. record time.

---

# 50. Point-in-Time Recovery Test

Where supported:

1. create synthetic data,
2. record timestamp,
3. modify/delete data,
4. restore to point before loss,
5. verify expected state,
6. record recovery granularity and duration.

---

# 51. Accidental Deletion Recovery Test

Using synthetic data:

- delete representative record/object,
- execute documented recovery method,
- verify restored references and associated files.

---

# 52. File/Object Restore Test

Verify:

- file content,
- metadata,
- ownership/reference,
- storage path/key,
- application access after restore.

---

# 53. Migration Recovery Test

In isolated environment:

1. start prior version/schema,
2. snapshot,
3. apply risky migration,
4. simulate failure,
5. execute recovery/rollback,
6. verify prior application can operate or documented forward-fix succeeds.

---

# 54. Release Rollback Test

Where deployment platform supports it:

- deploy test release,
- introduce controlled failure or use safe prior release,
- rollback,
- verify service,
- verify data compatibility.

---

# 55. Configuration Recovery Test

Using synthetic/non-secret values where possible:

- reconstruct environment from documented config inventory,
- start application,
- verify no undocumented local config required.

---

# 56. Restore Integrity Validation

After restore verify:

- record counts,
- critical relationships,
- checksums where useful,
- schema version,
- file references,
- recent transactions,
- application compatibility.

Do not use row count alone as proof of integrity.

---

# 57. Recovery Time Measurement

Record:

- detection start,
- recovery start,
- backup selection time,
- provisioning time,
- restore duration,
- validation duration,
- total recovery time.

Compare with RTO.

---

# 58. Recovery Point Measurement

Determine newest recoverable transaction/time.

Compare with RPO.

---

# 59. Controlled Restore Summary

| Metric | Result |
|---|---|
| Critical restore tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| BR0 findings | `{}` |
| BR1 findings | `{}` |
| BR2 findings | `{}` |
| Best verified RPO | `{}` |
| Best verified RTO | `{}` |

---

# 60. Controlled Restore Exit Gate

Phase 2B passes only when:

- [ ] Critical DB restore executed.
- [ ] Critical file/object restore tested where applicable.
- [ ] PITR tested where relied upon.
- [ ] Migration recovery tested for high-risk migrations where applicable.
- [ ] Restore integrity validated.
- [ ] Restore time measured.
- [ ] Recoverable point measured.
- [ ] Every FAIL has finding ID.
- [ ] No critical recovery capability is assumed solely from provider marketing/config.

---

# 61. Finding Register

| Finding ID | Category | Severity | Asset / Scenario | Summary | Evidence | RPO/RTO impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `BR-001` | `{}` | `{BR0-BR4}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 62. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** Backup, restore, retention, and rollback changes can affect production safety and must be reviewed separately. Nothing below should be described as recoverable until controlled restore validation succeeds.

---

# 63. Objective

Design improvements that reduce both:

- maximum data loss,
- time to restore service.

---

# 64. Root-Cause Map

| Finding | Recovery gap | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `BR-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 65. Remediation Principles

| Principle | Application |
|---|---|
| Back up source-of-truth assets | Do not assume rebuildability |
| Verify restores | Backup creation is not enough |
| Define RPO/RTO | Business expectations drive technical design |
| Separate failure domains | Primary loss should not destroy all backups |
| Automate where practical | Reduce recovery dependence on memory |
| Preserve configuration | Data alone cannot restore service |
| Protect migrations | Recovery before destructive changes |
| Validate recovered state | Restore success ≠ application correctness |
| Practice recovery | Keep procedures current |

---

# 66. Backup Remediation Requirements

For new/changed backup process document:

- assets covered,
- frequency,
- RPO,
- retention,
- location,
- encryption,
- access,
- monitoring,
- restore method,
- test frequency.

---

# 67. Recovery Runbook Requirements

Every critical runbook should include:

- trigger/scenario,
- owner,
- required access,
- backup selection,
- exact restore steps,
- validation checks,
- traffic/cutover steps,
- rollback,
- escalation,
- completion criteria.

---

# 68. Migration Recovery Requirements

For risky migration:

- pre-migration backup,
- compatibility period,
- rollback/forward-fix,
- restore trigger,
- validation,
- owner.

---

# 69. Remediation Phase Table

| # | Action | Findings closed | Assets | RPO impact | RTO impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 70. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root cause documented.
- [ ] Backup scope explicit.
- [ ] RPO/RTO impact defined.
- [ ] Restore procedure defined.
- [ ] Monitoring defined.
- [ ] Rollback defined.
- [ ] Recovery test defined.
- [ ] Ownership defined.
- [ ] No untested “provider handles it” assumption remains.

---

# FINAL — BACKUP & RECOVERY PRODUCTION READINESS REPORT

# 71. Objective

Produce one release decision for recovery readiness.

---

# 72. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Critical assets protected
`{COUNT}/{TOTAL}`

### Restore tests
`{PASS}/{EXECUTED}`

### Verified RPO
`{RPO / NOT VERIFIED}`

### Verified RTO
`{RTO / NOT VERIFIED}`

### Open findings
- BR0: `{COUNT}`
- BR1: `{COUNT}`
- BR2: `{COUNT}`
- BR3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 73. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open BR0.
- Zero open BR1.
- All critical source-of-truth assets are backed up or intentionally rebuildable.
- Critical DB restore has been verified.
- Critical object/file recovery verified where applicable.
- Backup frequency meets approved RPO.
- Recovery process meets or is credibly within approved RTO.
- Backup failure is observable.
- Migration recovery exists for critical destructive changes.
- Configuration needed for recovery is known.
- Recovery ownership is assigned.
- No critical backup/recovery unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero BR0.
- Zero launch-blocking BR1.
- Critical data is recoverable.
- Remaining issues are bounded BR2 gaps.
- Approved RPO/RTO are still achievable.
- Release owner accepts residual risk.
- No critical recovery unknown remains.

## 🔴 NO-GO

Use if:

- Any BR0 remains.
- Critical source-of-truth data has no usable backup.
- Backups exist but restore cannot be demonstrated for critical data.
- Backup frequency cannot satisfy required RPO.
- Recovery path cannot satisfy critical RTO.
- User files/objects required for service are unrecoverable.
- Destructive migration has no recovery path.
- Backup job can silently fail.
- Recovery depends on undocumented local knowledge/config.
- Critical backup/recovery behavior remains unknown.

---

# 74. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-BR-01` | Zero open BR0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-BR-02` | Zero launch-blocking BR1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-BR-03` | Critical assets covered | `{INVENTORY}` | `{PASS/FAIL}` |
| `LG-BR-04` | Critical DB restore verified | `{TEST}` | `{PASS/FAIL}` |
| `LG-BR-05` | Critical files/objects recoverable | `{TEST}` | `{PASS/FAIL/N/A}` |
| `LG-BR-06` | RPO requirement met | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-BR-07` | RTO requirement met/validated | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-BR-08` | Backup failures observable | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-BR-09` | Migration recovery safe | `{EVIDENCE}` | `{PASS/FAIL/N/A}` |
| `LG-BR-10` | Config/infrastructure recovery documented | `{RUNBOOK}` | `{PASS/FAIL}` |
| `LG-BR-11` | Recovery ownership assigned | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-BR-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 75. Recovery Scenario Summary

| Scenario | RPO achieved | RTO achieved | Restore verified? | Residual risk |
|---|---|---|---|---|
| Accidental deletion | `{}` | `{}` | `{}` | `{}` |
| Database corruption | `{}` | `{}` | `{}` | `{}` |
| Bad migration | `{}` | `{}` | `{}` | `{}` |
| Full DB loss | `{}` | `{}` | `{}` | `{}` |
| File/object loss | `{}` | `{}` | `{}` | `{}` |
| Failed deployment | `{}` | `{}` | `{}` | `{}` |

Use only applicable scenarios.

---

# 76. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-BR-001` | `{REF}` | `{BR}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 77. Out-of-Scope / Not Verified

Explicitly list:

- provider-region disaster not tested,
- account-level cloud compromise not tested,
- full infrastructure rebuild not tested,
- DNS recovery not tested,
- secrets rotation/recovery not tested,
- mobile-store rollback not applicable/tested,
- long-term archive restore not tested,
- legal retention not reviewed,
- third-party SaaS backup unavailable,
- anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 78. Final One-Sentence Recommendation

### GO example

> Backup & Recovery recommendation: **GO for production** for `{VERSION}` because all mandatory recovery launch gates passed, critical data is verifiably restorable, and the tested recovery process meets the approved RPO/RTO requirements.

### CONDITIONAL GO example

> Backup & Recovery recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented BR2 residual risks; critical data remains recoverable within approved recovery objectives.

### NO-GO example

> Backup & Recovery recommendation: **NO-GO** for `{VERSION}` until findings `{BR-xxx...}` are remediated and the associated backup, restore, rollback, integrity-validation, RPO, and RTO tests pass.

---

# 79. Required Deliverables

A complete Backup & Recovery Audit should produce:

1. `01_BACKUP_RECOVERY_DISCOVERY_REPORT.md`
2. `02_BACKUP_RECOVERY_STATIC_VERIFICATION_REPORT.md`
3. `03_BACKUP_RESTORE_TEST_REPORT.md`
4. `04_BACKUP_RECOVERY_REMEDIATION_PLAN.md`
5. `05_BACKUP_RECOVERY_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `CRITICAL_ASSET_INVENTORY.md`
- `BACKUP_INVENTORY.md`
- `RPO_RTO_MATRIX.md`
- `RECOVERY_SCENARIO_MATRIX.md`
- `RESTORE_RUNBOOK.md`
- `MIGRATION_RECOVERY_PLAN.md`
- `BACKUP_RECOVERY_FINDINGS.csv`

---

# 80. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not overwrite production during restore testing.
3. Do not assume provider-enabled backups are restorable.
4. Do not claim RPO/RTO without owner-defined targets.
5. Do not invent recovery objectives.
6. Do not expose backup credentials or secret values.
7. Identify all source-of-truth assets.
8. Include user-upload/file storage where critical.
9. Inspect backup monitoring.
10. Inspect migration recovery.
11. Inspect application/config dependencies needed after restore.
12. Inspect AI-generated destructive migrations and storage changes.
13. Do not delete backup artifacts.
14. Do not alter retention while auditing.
15. Do not run mass data-repair scripts against production.
16. Record exact restore target and timing.
17. Validate restored integrity, not just restore command success.
18. Cite exact configuration/runbook/migration paths.
19. Preserve stable finding IDs.
20. Cross-reference Database Integrity, Reliability, Security, Dependencies/Config, and Release/Deployment audits where relevant.
21. Retest recovery before marking findings Verified Closed.
22. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 81. Completion Standard

This audit is complete only when an independent reviewer could answer:

- What data/assets are critical?
- What is backed up?
- What is not backed up?
- How frequently are backups created?
- What is the retention period?
- What RPO is required?
- What RTO is required?
- Do current backups meet those objectives?
- Are backups independent enough from the primary system?
- Are backup failures detectable?
- Can the database actually be restored?
- Can user files/objects be restored?
- Can bad migrations be recovered?
- Can a failed release be rolled back?
- Is production configuration recoverable?
- Who owns recovery?
- What recovery tests were actually performed?
- How long did recovery take?
- What remains unknown?
- What remediation is proposed versus verified?
- Can this exact production system recover from realistic data-loss and deployment-failure scenarios?

If those questions cannot be answered from the audit outputs, the audit is not complete.
