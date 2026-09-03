# Reliability & Resilience Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that an application continues to behave safely, predictably, and recoverably when dependencies fail, resources become unavailable, requests are retried, processes restart, or partial failures occur.
>
> This template is designed for applications built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark reliability PASS because the happy path works or because errors are caught. Critical failure behavior must be proven through controlled fault scenarios whenever practical.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current system is sufficiently resilient for production by verifying:

- Critical services fail safely.
- Partial failures do not create corrupt or ambiguous state.
- Critical operations are retry-safe and idempotent.
- Database outages are handled predictably.
- Third-party provider outages do not create silent data loss.
- Timeouts are bounded.
- Retry behavior is bounded and intentional.
- Queue/worker failures do not lose important jobs.
- Duplicate jobs/events are safe.
- Process restarts do not lose critical work.
- Application startup fails clearly when critical dependencies are unavailable.
- Graceful degradation exists where appropriate.
- Users receive accurate status during failure.
- Recovery after outage is deterministic.
- Critical background work can resume after restart.
- Circuit breakers, backoff, dead-letter handling, and fallback mechanisms are used where justified.
- State reconciliation exists where multiple systems can disagree.
- Failure behavior is observable.
- AI-generated code has not introduced hidden retry loops, silent catches, duplicate side effects, or unsafe fallback behavior.

## 0.2 Non-goals

This audit does **not** replace:

- Security audit.
- Functional QA.
- Code quality audit.
- Database/data-integrity audit.
- API/backend audit.
- Performance/load testing.
- Backup/disaster-recovery audit.
- Infrastructure/SRE capacity planning.

If related findings emerge, cross-reference the appropriate specialist audit.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Map critical dependencies, failure domains, retries, queues, timeouts, jobs, recovery paths, and startup assumptions | Failure-domain map |
| 2A | **Static Verification** | Inspect implementation for resilience controls and failure anti-patterns | Resilience evidence matrix |
| 2B | **Controlled Fault Validation** | Execute safe fault scenarios in an approved environment | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design root-cause resilience fixes — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence into launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**Catching an error is not the same as recovering safely.**

For every critical failure, determine:

1. What state exists before failure?
2. What fails?
3. What state remains after failure?
4. What does the user/operator see?
5. Is retry safe?
6. Can the system recover automatically?
7. Is manual intervention required?
8. Is the failure observable?

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
| Environment status | `{🧪 Controlled / 🔴 Live production}` |
| Fault injection method | `{MOCK / PROVIDER SANDBOX / SERVICE STOP / NETWORK BLOCK / etc.}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Controlled Fault Test** | Proven by intentionally induced failure in an approved environment |
| 🟧 **Confirmed by Code/Config** | Proven by explicit implementation/config evidence |
| 🟨 **Likely** | Strong inference, but runtime fault behavior not proven |
| 🟦 **Requires Controlled Fault Test** | Must be tested before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was disproven |

For every important finding, include:

- Finding ID.
- Failure domain.
- Trigger.
- Expected system behavior.
- Actual behavior.
- Data/state impact.
- Recovery behavior.
- Evidence.
- Severity.
- Launch-blocker status.
- Confidence.

---

# 4. Severity Model

| Level | Classification | Reliability meaning | Launch treatment |
|---|---|---|---|
| **RR0** | Critical | Realistic dependency failure can cause data corruption, duplicate financial action, permanent work loss, or catastrophic outage | **Mandatory NO-GO** |
| **RR1** | High | Core workflow fails unsafely, cannot recover predictably, or produces ambiguous state | **Pre-launch blocker** |
| **RR2** | Medium | Failure behavior is degraded but bounded and recoverable | Explicit acceptance required |
| **RR3** | Low | Local resilience weakness with limited impact | Backlog acceptable |
| **RR4** | Observation | Improvement opportunity | Backlog |

## 4.1 Severity factors

Evaluate:

- Frequency of dependency failure.
- User impact.
- Data impact.
- Financial impact.
- Recoverability.
- Detection latency.
- Automation of recovery.
- Manual effort.
- Blast radius.
- Retry exposure.
- State ambiguity.
- Duration.
- Whether failure cascades.

---

# 5. Environment Warning

When testing outside production:

| Dimension | Evaluation |
|---|---|
| Technical severity | Based on failure behavior itself |
| Current actual impact | Based on controlled environment |
| Production impact | State expected impact under real traffic/users |
| Procedural classification | Unresolved RR0/RR1 findings are **Pre-Launch Blockers** |

Never inject destructive faults into production without explicit authorization.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Map where the system can fail and what depends on what.

### Mandatory restrictions

During discovery:

- Read only where practical.
- Do not stop production services.
- Do not disable live integrations.
- Do not corrupt queues.
- Do not block production networking.
- Do not kill production processes.
- Do not alter retry policies.
- Do not change infrastructure.

---

# 7. Critical Dependency Inventory

| Dependency ID | Dependency | Purpose | Critical path? | Failure mode | Current fallback | Recovery owner |
|---|---|---|---|---|---|---|
| `DEP-001` | `{SERVICE}` | `{PURPOSE}` | `{YES/NO}` | `{FAILURE}` | `{FALLBACK}` | `{OWNER}` |

Include:

- Primary database.
- Cache.
- Object storage.
- Payment provider.
- Email/SMS/push.
- Identity provider.
- Maps/geocoding.
- POS/ERP/CRM.
- AI provider.
- Queue/broker.
- Search service.
- File processor.
- CDN.
- Internal services.
- DNS/network dependencies.

---

# 8. Failure Domain Map

Identify independent failure domains:

- frontend/client,
- backend process,
- database,
- cache,
- queue,
- worker,
- external provider,
- storage,
- network,
- DNS,
- configuration,
- deployment,
- regional/zone failure where applicable.

Create a dependency chain:

`User → Client → API → DB → Provider → Queue → Worker`

For each chain, identify what happens if any link fails.

---

# 9. Critical Operation Inventory

Use stable IDs:

- `OP-001`, `OP-002`, ...

| Operation | Trigger | Systems involved | Irreversible side effect? | Retryable? | Recovery importance |
|---|---|---|---|---|---|
| `OP-001` | `{ACTION}` | `{SYSTEMS}` | `{YES/NO}` | `{YES/NO}` | `{Critical/High/Normal}` |

Examples:

- payment,
- refund,
- order creation,
- booking,
- subscription,
- account creation,
- file processing,
- notification dispatch,
- inventory decrement,
- driver assignment.

---

# 10. Timeout Inventory

| Dependency / Operation | Connection timeout | Request timeout | Job timeout | User timeout behavior | Evidence |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Flag:

- no timeout,
- infinite wait,
- mismatched nested timeouts,
- frontend timeout shorter than backend commit behavior,
- worker timeout shorter than external provider response.

---

# 11. Retry Inventory

| Operation | Retry exists? | Max attempts | Backoff | Jitter | Retryable conditions | Non-retryable conditions | Idempotent? |
|---|---|---:|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Flag:

- infinite retry,
- retry on all 4xx,
- retry without idempotency,
- nested retries causing amplification,
- retry storms.

---

# 12. Queue / Job Inventory

| Job ID | Queue | Trigger | Retry | Max attempts | Dead-letter / failed state | Idempotent? | Durable? |
|---|---|---|---|---|---|---|---|
| `JOB-001` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Document:

- visibility timeout,
- acknowledgement behavior,
- duplicate-delivery semantics,
- worker restart behavior,
- poison messages,
- job retention.

---

# 13. Startup Dependency Inventory

Determine what happens if application starts while:

- DB unavailable,
- cache unavailable,
- queue unavailable,
- external provider unavailable,
- required environment variable missing,
- migration incomplete.

Classify each dependency:

- required for startup,
- optional,
- degraded-mode capable.

---

# 14. Recovery Mechanism Inventory

Document:

- automatic retry,
- retry queue,
- reconciliation job,
- manual admin action,
- dead-letter replay,
- status polling,
- compensating transaction,
- scheduled repair job,
- operator runbook.

| Failure | Recovery method | Automatic? | Max recovery time known? | Data repair required? |
|---|---|---|---|---|
| `{}` | `{}` | `{YES/NO}` | `{}` | `{}` |

---

# 15. Degraded Mode Inventory

Identify whether system can continue when optional services fail.

Examples:

- app works without analytics,
- orders work without email,
- dashboard works without recommendation engine,
- payment unavailable but browsing remains usable.

Flag unnecessary full-system failure caused by non-critical dependency.

---

# 16. Reconciliation Inventory

Where two systems can disagree, identify reconciliation process.

Examples:

- payment provider vs order status,
- POS vs app order,
- queue job vs database status,
- external subscription provider vs local entitlement.

| Domain | Systems compared | Reconciliation mechanism | Frequency | Manual fallback |
|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 17. Restart / Resume Inventory

For processes/jobs:

- What state is persisted?
- What is in memory only?
- What happens after restart?
- Can in-flight work be resumed?
- Can work be duplicated?
- Can work be lost?

---

# 18. Existing Resilience Tooling

Document:

- circuit breakers,
- retry libraries,
- queue DLQ,
- health checks,
- readiness probes,
- liveness probes,
- supervisor/process manager,
- graceful shutdown,
- reconciliation jobs,
- uptime monitoring,
- incident alerts.

---

# 19. Discovery Execution Log

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

# 20. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Critical dependencies identified.
- [ ] Failure domains mapped.
- [ ] Critical operations identified.
- [ ] Timeouts inventoried.
- [ ] Retries inventoried.
- [ ] Queue/job behavior understood.
- [ ] Startup dependencies understood.
- [ ] Recovery mechanisms mapped.
- [ ] Reconciliation needs identified.
- [ ] Unknown resilience areas documented.

---

# PHASE 2A — STATIC VERIFICATION

# 21. Objective

Inspect implementation for unsafe failure behavior.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `TO-xx` | Timeout |
| `RT-xx` | Retry |
| `IDEM-xx` | Idempotency |
| `CB-xx` | Circuit breaker |
| `DBF-xx` | Database failure |
| `EXT-xx` | External dependency failure |
| `Q-xx` | Queue |
| `JOB-xx` | Worker/job |
| `RST-xx` | Restart/resume |
| `REC-xx` | Recovery |
| `RECON-xx` | Reconciliation |
| `DEG-xx` | Degraded mode |
| `START-xx` | Startup |
| `SHUT-xx` | Graceful shutdown |
| `CASCADE-xx` | Cascading failure |
| `AI-xx` | AI-agent-specific resilience defects |

---

# 22. Timeout Verification

Inspect every critical external call for:

- explicit timeout,
- bounded total operation duration,
- timeout classification,
- cancellation,
- safe client response,
- safe persisted state.

Flag no-timeout critical calls.

---

# 23. Retry Verification

Verify retries are:

- bounded,
- exponential where appropriate,
- jittered where appropriate,
- only for retryable failures,
- safe under idempotency,
- not duplicated at multiple layers unintentionally.

Calculate retry amplification when multiple nested layers retry.

Example:

`client 3 retries × API 3 retries × provider SDK 3 retries = 27 attempts`

Flag hidden amplification.

---

# 24. Idempotency Verification

For critical operations verify:

- stable idempotency key,
- persistence,
- duplicate request handling,
- transaction boundary,
- duplicate worker/job handling,
- duplicate webhook handling.

---

# 25. Database Failure Handling Audit

Inspect:

- connection failure,
- query timeout,
- deadlock,
- transaction rollback,
- connection pool exhaustion,
- read-only failure,
- failover assumptions.

Flag:

- catch DB error and return success,
- partial state in memory shown as committed,
- retry of non-idempotent DB operation without protection.

---

# 26. External Provider Failure Audit

For every critical provider inspect:

- timeout,
- 4xx,
- 5xx,
- rate limit,
- malformed response,
- auth failure,
- provider maintenance,
- partial success,
- delayed callback.

Determine whether user-visible state remains accurate.

---

# 27. Queue Failure Audit

Inspect:

- enqueue failure,
- duplicate job,
- delayed job,
- poison message,
- worker crash,
- broker unavailable,
- acknowledgement before durable completion,
- dead-letter behavior,
- replay behavior.

---

# 28. Worker Crash Audit

For long-running jobs determine:

- what happens if process dies midway,
- whether job is redelivered,
- whether partial side effects can duplicate,
- whether checkpointing exists,
- whether job is idempotent.

---

# 29. Graceful Shutdown Audit

Inspect:

- stop accepting new work,
- finish/abort in-flight work safely,
- close DB connections,
- stop consumers,
- release locks,
- persist progress,
- terminate within platform grace period.

Flag abrupt shutdown patterns.

---

# 30. Startup Failure Audit

Verify critical startup configuration/dependencies:

- missing required env fails clearly,
- incompatible schema detected,
- required DB unavailable,
- queue unavailable,
- cache unavailable.

Avoid silent startup into broken half-working state where that creates risk.

---

# 31. Circuit Breaker Audit

Where repeated provider failure could cause cascading damage, inspect:

- threshold,
- open state,
- half-open recovery,
- fallback,
- observability.

Do not require circuit breaker for every dependency; justify based on failure characteristics.

---

# 32. Cascading Failure Audit

Look for:

- retry storm,
- thread/connection pool exhaustion,
- queue flood,
- recursive fallback,
- synchronous dependency chain,
- cache failure causing DB overload,
- provider slowdown consuming all workers.

---

# 33. Degraded Mode Audit

Verify optional dependencies do not unnecessarily take down core service.

Document:

- feature disabled,
- stale data,
- placeholder state,
- user message,
- automatic recovery.

---

# 34. Reconciliation Audit

Verify mismatched states can be detected.

Examples:

- payment succeeded externally, local callback failed,
- order created, notification failed,
- POS accepted order but local status stale.

Reconciliation must identify source of truth.

---

# 35. AI-Agent-Specific Reliability Audit

Mandatory when AI agents were used.

Actively search for:

## 35.1 Silent catches

- `catch { return null; }`
- `catch { return true; }`
- errors logged but operation reported successful.

## 35.2 Retry loops

- recursive retry,
- unbounded while loop,
- fixed short retry interval,
- multiple layers retrying same call.

## 35.3 Unsafe fallbacks

- fallback creates fake success,
- cached value used when transaction result unknown,
- mock provider used on production error,
- local state treated as source of truth after server failure.

## 35.4 Duplicate side effects

- retry sends email twice,
- retry charges twice,
- job retry creates duplicate record,
- webhook retry repeats irreversible action.

## 35.5 In-memory critical state

- queue emulated with local array,
- unsaved pending work,
- process restart loses state,
- locks/counters only in process memory.

## 35.6 Partial refactors

- old retry code + new retry library both active,
- old queue path still reachable,
- fallback references removed service.

## 35.7 Hallucinated resilience primitives

- unsupported circuit breaker config,
- nonexistent SDK retry option,
- incorrect queue acknowledgement semantics,
- misunderstood transaction retry behavior.

---

# 36. Static Verification Matrix

| Check ID | Category | Scope | Expected resilient behavior | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 37. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Critical timeout behavior reviewed.
- [ ] Retry behavior reviewed.
- [ ] Idempotency reviewed.
- [ ] DB failure behavior reviewed.
- [ ] External failure behavior reviewed.
- [ ] Queue/worker behavior reviewed.
- [ ] restart/shutdown behavior reviewed.
- [ ] startup dependency behavior reviewed.
- [ ] reconciliation reviewed.
- [ ] AI-generated resilience risks reviewed.
- [ ] RR0/RR1 candidates have evidence.

---

# PHASE 2B — CONTROLLED FAULT VALIDATION

# 38. Objective

Prove critical failure behavior in an approved environment.

### Mandatory restrictions

- Prefer local/staging.
- Use synthetic data.
- Never disable production dependency without explicit authorization.
- Never corrupt production queues.
- Never intentionally cause real customer failure.
- Do not trigger real financial side effects.
- Document cleanup and restoration.

---

# 39. Fault Test Categories

| Prefix | Category |
|---|---|
| `RR-DB-xx` | Database |
| `RR-NET-xx` | Network |
| `RR-EXT-xx` | External provider |
| `RR-TO-xx` | Timeout |
| `RR-RT-xx` | Retry |
| `RR-Q-xx` | Queue |
| `RR-JOB-xx` | Worker |
| `RR-RST-xx` | Restart |
| `RR-SHUT-xx` | Shutdown |
| `RR-RECON-xx` | Reconciliation |
| `RR-DEG-xx` | Degraded mode |
| `RR-IDEM-xx` | Idempotency |

---

# 40. Controlled Fault Matrix

| Test ID | Failure injected | Operation | Expected state | Expected user/operator behavior | Actual state | Recovery | Evidence | Result |
|---|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 41. Database Outage Test

Where safe:

1. Begin critical operation.
2. Make DB unavailable or simulate failure.
3. Observe response.
4. Restore DB.
5. Verify persisted state.
6. Retry.
7. Verify no duplication/corruption.

---

# 42. Provider Timeout Test

Simulate timeout from critical provider.

Verify:

- client does not hang indefinitely,
- backend times out intentionally,
- persisted state is accurate,
- retry behavior is safe,
- user sees accurate status.

---

# 43. Provider 5xx Test

Verify:

- bounded retry,
- no duplicate side effect,
- correct error classification,
- fallback/degraded mode if applicable.

---

# 44. Rate Limit Test

Simulate provider/API 429.

Verify:

- retry-after respected where appropriate,
- no tight retry loop,
- user state remains correct,
- queue/backoff does not explode.

---

# 45. Queue Unavailable Test

Where safe:

- attempt enqueue,
- observe application behavior,
- verify critical request does not claim background work succeeded if enqueue failed,
- verify retry/fallback.

---

# 46. Worker Crash Test

Terminate worker during critical job in controlled environment.

Verify:

- job resumes/redelivers,
- partial side effect does not duplicate,
- final state becomes consistent,
- failure observable.

---

# 47. Duplicate Job/Event Test

Deliver same job/event twice.

Verify one logical outcome.

---

# 48. Process Restart Test

Restart backend/worker during:

- idle,
- active request where safe,
- queued job,
- delayed task.

Verify:

- no lost durable work,
- no duplicate irreversible work,
- service returns healthy only when ready.

---

# 49. Graceful Shutdown Test

Verify:

- readiness changes appropriately,
- new work stops,
- in-flight work handled safely,
- connections close,
- process exits within allowed period.

---

# 50. Degraded Mode Test

Disable optional dependency.

Verify core functionality remains available if designed to do so.

---

# 51. Reconciliation Test

Create controlled mismatch.

Verify reconciliation detects and corrects or flags it.

---

# 52. Recovery Time Measurement

For critical fault scenarios record:

- time to detect,
- time to recover,
- automatic vs manual,
- data repair needed,
- user impact window.

| Fault | Detection time | Recovery time | Automatic? | Data repair? |
|---|---:|---:|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 53. Controlled Fault Validation Summary

| Metric | Count |
|---|---:|
| Fault scenarios planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| RR0 findings | `{}` |
| RR1 findings | `{}` |
| RR2 findings | `{}` |

---

# 54. Controlled Fault Exit Gate

Phase 2B passes only when:

- [ ] Critical DB failure tested.
- [ ] Critical provider failure tested.
- [ ] Critical timeout behavior tested.
- [ ] Retry/idempotency tested.
- [ ] Queue/worker behavior tested where applicable.
- [ ] Restart behavior tested where applicable.
- [ ] Reconciliation tested where applicable.
- [ ] Recovery results documented.
- [ ] Every FAIL has a finding ID.
- [ ] No critical failure behavior is assumed from code alone.

---

# 55. Finding Register

| Finding ID | Category | Severity | Failure domain | Summary | Evidence | Recovery impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `RR-001` | `{}` | `{RR0-RR4}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 56. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** It requires technical review and a separate implementation decision. Nothing below should be described as fixed until controlled fault validation is rerun successfully.

---

# 57. Objective

Design resilience fixes around root causes.

Prefer:

- bounded timeouts,
- explicit retries,
- idempotency,
- durable queues,
- reconciliation,
- graceful degradation,
- clear failure states,
- observable recovery.

---

# 58. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `RR-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 59. Remediation Principles

| Principle | Application |
|---|---|
| Fail bounded | No infinite waits/retries |
| Retry only when safe | Idempotency first |
| Persist important work | Do not rely on process memory |
| Recover from partial failure | Compensation/reconciliation |
| Degrade intentionally | Optional service failure should not cascade |
| Detect disagreement | Reconcile cross-system state |
| Restart safely | In-flight work must be recoverable |
| Preserve truth | Never fake success |
| Observe failure | Operators must know when recovery is incomplete |

---

# 60. Remediation Phase Table

| # | Action | Findings closed | Components | Failure behavior changed | Data impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 61. Retry Design Requirements

For every retry policy document:

- trigger conditions,
- max attempts,
- backoff,
- jitter,
- timeout,
- idempotency guarantee,
- terminal failure state,
- alerting,
- manual replay.

---

# 62. Reconciliation Design Requirements

For every cross-system reconciliation:

- source of truth,
- comparison key,
- frequency,
- mismatch categories,
- automatic repair vs manual review,
- audit trail,
- safety limit.

---

# 63. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root cause documented.
- [ ] Timeout/retry behavior explicit.
- [ ] Idempotency strategy defined.
- [ ] Recovery mechanism defined.
- [ ] Data consistency impact reviewed.
- [ ] Rollback defined.
- [ ] Fault retests defined.
- [ ] Observability requirements defined.
- [ ] No fake-success fallback proposed.

---

# FINAL — RELIABILITY & RESILIENCE PRODUCTION READINESS REPORT

# 64. Objective

Produce one release decision for the exact audited version.

---

# 65. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Critical fault scenarios tested
`{PASS}/{EXECUTED}`

### Open findings
- RR0: `{COUNT}`
- RR1: `{COUNT}`
- RR2: `{COUNT}`
- RR3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 66. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open RR0.
- Zero open RR1.
- Critical DB outage behavior safe.
- Critical external provider failure safe.
- Critical operations have bounded timeouts.
- Retry behavior bounded.
- High-impact retries are idempotent.
- Queue/worker failures do not lose critical work.
- Restart behavior safe.
- Reconciliation exists where systems can diverge.
- Optional dependencies degrade safely where appropriate.
- No critical recovery unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero RR0.
- Zero launch-blocking RR1.
- Critical failure modes are safe and recoverable.
- Remaining gaps are bounded RR2 issues.
- Release owner explicitly accepts residual risk.
- No critical unknown remains.

## 🔴 NO-GO

Use if:

- Any RR0 remains.
- Database/provider failure can corrupt core state.
- Retry can duplicate critical irreversible action.
- Queue/worker crash can permanently lose important work.
- Critical operations can hang indefinitely.
- Process restart can lose critical state.
- System claims success after failed critical dependency.
- Cross-system mismatch cannot be reconciled.
- Critical failure behavior remains unknown.

---

# 67. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-RR-01` | Zero open RR0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-RR-02` | Zero launch-blocking RR1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-RR-03` | Critical DB failure safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RR-04` | Critical provider failure safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RR-05` | Critical timeouts bounded | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RR-06` | Retry behavior safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RR-07` | Critical idempotency verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RR-08` | Queue/job recovery safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RR-09` | Restart/shutdown safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RR-10` | Reconciliation verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RR-11` | Degraded mode safe where applicable | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RR-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 68. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-RR-001` | `{REF}` | `{RR}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 69. Out-of-Scope / Not Verified

Explicitly list:

- production failover not tested,
- region outage not tested,
- cloud provider outage not tested,
- managed DB failover not tested,
- queue broker HA not tested,
- DNS failure not tested,
- autoscaling not tested,
- disaster recovery not tested,
- backup restore not tested,
- provider sandbox unavailable,
- anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 70. Final One-Sentence Recommendation

### GO example

> Reliability & Resilience recommendation: **GO for production** for `{VERSION}` because all mandatory resilience launch gates passed and no unresolved critical failure-recovery, retry, queue, restart, or reconciliation risk remains.

### CONDITIONAL GO example

> Reliability & Resilience recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented RR2 residual risks; all critical failure modes remain safely recoverable.

### NO-GO example

> Reliability & Resilience recommendation: **NO-GO** for `{VERSION}` until findings `{RR-xxx...}` are remediated and the associated fault-injection, retry, restart, recovery, and reconciliation tests pass.

---

# 71. Required Deliverables

A complete Reliability & Resilience Audit should produce:

1. `01_RELIABILITY_DISCOVERY_REPORT.md`
2. `02_RELIABILITY_STATIC_VERIFICATION_REPORT.md`
3. `03_RELIABILITY_FAULT_TEST_REPORT.md`
4. `04_RELIABILITY_REMEDIATION_PLAN.md`
5. `05_RELIABILITY_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `FAILURE_DOMAIN_MAP.md`
- `DEPENDENCY_FAILURE_MATRIX.md`
- `RETRY_POLICY_INVENTORY.md`
- `QUEUE_JOB_RESILIENCE_MAP.md`
- `RECONCILIATION_PLAN.md`
- `RELIABILITY_FINDINGS.csv`

---

# 72. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not inject faults into production without explicit authorization.
3. Do not modify retry/timeout behavior while auditing.
4. Do not assume catch blocks equal resilience.
5. Do not assume retries are safe.
6. Do not assume external providers deliver callbacks once.
7. Do not assume queue jobs run exactly once.
8. Do not assume process memory survives restart.
9. Do not assume successful enqueue means successful processing.
10. Do not assume timeout means provider did not complete the action.
11. Do not fake success on dependency failure.
12. Inspect nested retry amplification.
13. Inspect duplicate side effects.
14. Inspect graceful shutdown.
15. Inspect startup dependency behavior.
16. Inspect reconciliation for cross-system state.
17. Inspect AI-generated retry loops/fallbacks.
18. Cite exact paths/services/jobs for findings.
19. Preserve stable finding IDs.
20. Cross-reference API, Database, Functional QA, Performance, and Observability audits where relevant.
21. Retest fault scenarios before marking findings Verified Closed.
22. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 73. Completion Standard

This audit is complete only when an independent reviewer could answer:

- What can fail?
- Which dependencies are critical?
- Which operations are irreversible?
- What are the timeout policies?
- What are the retry policies?
- Are retries idempotent?
- Can queues lose work?
- What happens if workers crash?
- What happens if processes restart?
- What happens if the DB is unavailable?
- What happens if a third-party provider is slow or down?
- Can the system degrade safely?
- Can cross-system inconsistencies be reconciled?
- What failures were actually tested?
- How does the system recover?
- What remains unknown?
- What remediation is proposed versus verified?
- Can this exact version recover safely from realistic failures in production?

If those questions cannot be answered from the audit outputs, the audit is not complete.
