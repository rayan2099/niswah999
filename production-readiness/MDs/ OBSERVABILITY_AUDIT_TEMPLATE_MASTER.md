# Observability Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that an application is sufficiently observable to detect, diagnose, triage, and resolve production issues after launch.
>
> This template is designed for applications built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark observability PASS because logs exist or because an error-tracking SDK is installed. Critical failures must produce actionable, correlated, and appropriately routed signals.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current system is observable enough for production by verifying:

- Critical failures are visible.
- Important errors are captured centrally.
- Logs are structured and actionable.
- Requests/actions can be correlated across services.
- Critical backend operations expose useful context.
- Key business and technical metrics are measurable.
- Alerts exist for conditions that require action.
- Alerts are not so noisy that they become ignored.
- Health/readiness signals accurately reflect service state.
- Background jobs, queues, and integrations are observable.
- External provider failures are distinguishable from internal failures.
- Production incidents can be traced to affected requests, users, jobs, or transactions without exposing sensitive data.
- Audit-relevant state changes are traceable where required.
- Dashboards cover critical system health.
- Silent failure paths are minimized.
- Release/version information is available in errors and logs.
- AI-generated code has not introduced swallowed exceptions, console-only diagnostics, misleading success logs, or missing context.

## 0.2 Non-goals

This audit does **not** replace:

- Security monitoring/SIEM review.
- Reliability/resilience testing.
- Functional QA.
- Performance/load testing.
- Privacy/legal review.
- Incident-response planning.
- Backup/disaster-recovery validation.

Cross-reference those audits where relevant.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Map logging, error tracking, metrics, traces, alerts, dashboards, health checks, audit events, and critical blind spots | Observability map |
| 2A | **Static Verification** | Inspect implementation/configuration for coverage and signal quality | Observability evidence matrix |
| 2B | **Controlled Signal Validation** | Trigger safe synthetic failures/events and verify that signals actually appear | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design observability improvements — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence into launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**Installed tooling is not proof of observability.**

A signal is useful only if:

1. the event is captured,
2. enough context is attached,
3. the event can be correlated,
4. someone or something can find it,
5. critical events trigger appropriate attention,
6. the signal does not expose prohibited/sensitive data.

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
| Logging platform | `{PLATFORM}` |
| Error tracking | `{PLATFORM}` |
| Metrics/APM | `{PLATFORM}` |
| Alerting | `{PLATFORM}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Signal Test** | Proven by triggering a controlled event and observing the resulting signal |
| 🟧 **Confirmed by Code/Config** | Proven by explicit instrumentation/config evidence |
| 🟨 **Likely** | Strong inference but runtime signal not directly confirmed |
| 🟦 **Requires Controlled Signal Test** | Must be tested before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was disproven |

For every important finding include:

- Finding ID.
- Signal type.
- Trigger/event.
- Expected telemetry.
- Actual telemetry.
- Context fields available.
- Destination/tool.
- Alert behavior.
- Evidence.
- Severity.
- Launch-blocker status.
- Confidence.

---

# 4. Severity Model

| Level | Classification | Observability meaning | Launch treatment |
|---|---|---|---|
| **OB0** | Critical | Critical production failure can occur with no reliable detection or diagnosis path | **Mandatory NO-GO** |
| **OB1** | High | Core production failures are captured poorly, lack essential context, or cannot trigger timely response | **Pre-launch blocker** |
| **OB2** | Medium | Important visibility gap exists but issue remains diagnosable through a safe workaround | Explicit acceptance required |
| **OB3** | Low | Local signal-quality or dashboard gap | Backlog acceptable |
| **OB4** | Observation | Improvement opportunity | Backlog |

## 4.1 Severity factors

Evaluate:

- Criticality of hidden failure.
- Detection delay.
- Diagnostic difficulty.
- Blast radius.
- Frequency.
- Whether user reports are required for discovery.
- Whether data/financial errors can remain silent.
- Whether failure can be correlated across systems.
- Whether alert fatigue is likely.
- Whether issue blocks incident response.

---

# 5. Environment Warning

When testing outside production:

| Dimension | Evaluation |
|---|---|
| Technical severity | Based on visibility gap itself |
| Current actual impact | Based on current environment |
| Production impact | State how blind spot affects live incident detection/diagnosis |
| Procedural classification | Unresolved OB0/OB1 findings are **Pre-Launch Blockers** |

Do not generate real incidents, real customer notifications, or production alert storms without explicit authorization.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Understand all existing observability channels and blind spots.

### Mandatory restrictions

During discovery:

- Prefer read-only inspection.
- Do not rotate DSNs/keys.
- Do not change alert routes.
- Do not trigger production paging.
- Do not enable high-volume debug logging in production.
- Do not modify dashboards.
- Do not change retention.
- Do not add instrumentation while auditing.

---

# 7. Observability Stack Inventory

Document:

- Application logger.
- Central log platform.
- Error tracking.
- APM.
- Metrics backend.
- Tracing.
- Dashboard platform.
- Alerting platform.
- Uptime monitoring.
- Synthetic monitoring.
- Queue monitoring.
- Database monitoring.
- Cloud/provider logs.
- Release tracking.
- Audit logging.

| Component | Tool | Purpose | Environment(s) | Actually active? | Evidence |
|---|---|---|---|---|---|
| `{COMPONENT}` | `{TOOL}` | `{PURPOSE}` | `{}` | `{YES/NO}` | `{}` |

---

# 8. Critical Event Inventory

Use stable IDs:

- `EVT-001`, `EVT-002`, ...

Identify events that must be observable:

- login failure spikes,
- payment failures,
- duplicate payment attempts,
- order creation failure,
- booking failure,
- database outage,
- queue backlog,
- worker failures,
- external provider failure,
- webhook failures,
- authorization failures where operationally relevant,
- high error rate,
- latency spikes,
- app crash,
- file-processing failure,
- failed scheduled job,
- reconciliation mismatch.

| Event ID | Event | Severity | Expected signal | Expected destination | Alert required? |
|---|---|---|---|---|---|
| `EVT-001` | `{EVENT}` | `{Critical/High/Normal}` | `{LOG/METRIC/ERROR/TRACE}` | `{TOOL}` | `{YES/NO}` |

---

# 9. Log Inventory

Document:

- logger abstraction,
- structured vs plain text,
- JSON formatting,
- levels,
- timestamps,
- environment,
- service name,
- request ID,
- user/account ID policy,
- transaction/order/payment ID,
- source file/module,
- exception stack,
- release/version.

---

# 10. Log Level Model

Verify use of:

- DEBUG
- INFO
- WARN
- ERROR
- FATAL/CRITICAL where available

Flag:

- all logs at INFO,
- critical failures only logged as debug,
- ordinary user validation logged as error,
- production debug flood,
- misleading “success” logs before transaction completion.

---

# 11. Structured Context Inventory

For critical logs determine whether context includes appropriate identifiers:

- request/correlation ID,
- trace ID,
- service,
- environment,
- version/release,
- endpoint/job,
- user/account pseudonymous identifier,
- order/booking/payment ID,
- provider event ID,
- retry attempt,
- error category.

Do not log secrets or prohibited sensitive data.

---

# 12. Error Tracking Inventory

Document:

- SDK initialization.
- Environment tagging.
- Release tagging.
- source maps/symbolication.
- breadcrumbs.
- user/context policy.
- handled vs unhandled exception capture.
- frontend crash capture.
- backend exception capture.
- mobile crash capture.

Flag installed SDK with no environment/release tagging.

---

# 13. Metrics Inventory

Identify technical metrics:

- request rate,
- error rate,
- latency,
- CPU,
- memory,
- DB connections,
- queue depth,
- worker failures,
- cache hit rate,
- external provider latency,
- webhook failure count.

Identify business/operational metrics where useful:

- orders created,
- payments completed/failed,
- bookings created/cancelled,
- subscriptions activated,
- critical job completion.

---

# 14. Trace Inventory

Where tracing exists document:

- incoming request trace,
- DB spans,
- external API spans,
- queue propagation,
- background job trace,
- frontend-to-backend trace,
- sampling.

Flag partial tracing that breaks at important boundaries.

---

# 15. Correlation ID Inventory

Determine:

- how request IDs are created,
- whether propagated to downstream services,
- whether returned to client/support,
- whether queue jobs preserve them,
- whether webhook processing gets event/correlation IDs.

---

# 16. Alert Inventory

| Alert ID | Condition | Threshold | Window | Severity | Destination | Owner | Runbook? |
|---|---|---|---|---|---|---|---|
| `ALT-001` | `{CONDITION}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` |

Flag:

- no owner,
- no threshold rationale,
- no action,
- duplicate alerts,
- alerts on symptoms with no operational response.

---

# 17. Dashboard Inventory

Document dashboards for:

- application health,
- API latency/errors,
- database,
- queue/workers,
- external integrations,
- business-critical transactions,
- mobile/web crash rate.

For each dashboard:

| Dashboard | Purpose | Critical signals covered | Owner | Freshness |
|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 18. Health Check Inventory

Document:

- liveness endpoint,
- readiness endpoint,
- dependency checks,
- version info,
- build info.

Flag:

- health endpoint always returning 200,
- readiness ignoring critical DB dependency,
- liveness depending on optional provider and causing restart loops.

---

# 19. Background Job Observability Inventory

Verify:

- job start,
- success,
- failure,
- duration,
- retry attempt,
- final dead-letter state,
- queue age,
- backlog,
- job correlation ID.

---

# 20. Integration Observability Inventory

For each external integration:

| Integration | Success visible? | Failure visible? | Latency metric? | Provider request/event ID stored? | Alert? |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 21. Audit Trail Inventory

For business-critical state changes determine whether system can answer:

- who initiated action,
- what changed,
- when,
- previous state,
- new state,
- source/system,
- related transaction/event.

Do not require full audit logs for every application unless domain needs them.

---

# 22. Retention Inventory

Document retention for:

- logs,
- traces,
- metrics,
- errors,
- audit events.

Flag retention too short to investigate likely incident/dispute windows.

Privacy/legal implications should be cross-referenced.

---

# 23. Discovery Execution Log

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

# 24. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Observability stack mapped.
- [ ] Critical events identified.
- [ ] Logging architecture understood.
- [ ] Error tracking understood.
- [ ] Metrics identified.
- [ ] Tracing/correlation identified.
- [ ] Alerts inventoried.
- [ ] Dashboards inventoried.
- [ ] Health checks understood.
- [ ] Job/integration observability mapped.
- [ ] Unknown blind spots explicitly listed.

---

# PHASE 2A — STATIC VERIFICATION

# 25. Objective

Inspect whether observability implementation is complete and actionable.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `LOG-xx` | Logging |
| `ERR-xx` | Error tracking |
| `CTX-xx` | Context/correlation |
| `MET-xx` | Metrics |
| `TRACE-xx` | Tracing |
| `ALT-xx` | Alerting |
| `DASH-xx` | Dashboards |
| `HEALTH-xx` | Health checks |
| `JOB-xx` | Jobs/queues |
| `INT-xx` | Integrations |
| `AUDIT-xx` | Audit trail |
| `REL-xx` | Release/version context |
| `NOISE-xx` | Signal noise |
| `SILENT-xx` | Silent failure |
| `AI-xx` | AI-agent-specific observability defects |

---

# 26. Logging Verification

Inspect:

- centralized logger use,
- structured fields,
- level correctness,
- error object preserved,
- stack trace preserved,
- no critical reliance on console output only,
- no logging after irreversible side effect described as before completion.

---

# 27. Silent Failure Audit

Actively search for:

- empty catch blocks,
- ignored promise/future failures,
- returned null on error,
- fallback with no log,
- background job failure swallowed,
- webhook error ignored,
- external provider failure hidden,
- UI suppressing backend errors.

Every critical silent failure is high priority.

---

# 28. Correlation Verification

Verify critical path can be traced through:

`Client → API → Service → Database → External Provider → Queue → Worker`

At minimum, use one stable correlation mechanism appropriate to architecture.

Flag fragmented logs with no shared ID.

---

# 29. Release / Version Verification

Verify signals identify:

- release/version,
- commit,
- environment,
- service.

Without this, post-deploy regressions are difficult to isolate.

---

# 30. Error Tracking Verification

Inspect:

- unhandled exceptions captured,
- handled critical exceptions captured where needed,
- environment tags,
- release tags,
- source maps/symbols,
- grouping quality,
- alert integration.

---

# 31. Metrics Verification

For every critical service verify availability of golden signals where applicable:

- latency,
- traffic,
- errors,
- saturation.

For queue/job systems:

- queue depth,
- queue age,
- failure rate,
- processing duration,
- retry count.

---

# 32. Business-Critical Signal Verification

For critical transactions verify success/failure counts are measurable.

Examples:

- payment success/failure,
- booking creation failure,
- order submission failure,
- subscription activation failure.

This does not require analytics-level product instrumentation; focus on operationally critical outcomes.

---

# 33. Alert Quality Audit

For each alert evaluate:

- actionable?
- threshold justified?
- correct owner?
- severity?
- deduplicated?
- rate-limited?
- escalation?
- runbook?
- testable?

Flag alerts that cannot lead to an action.

---

# 34. Alert Coverage Audit

Critical conditions commonly requiring alerts:

- high server error rate,
- payment failure spike,
- queue backlog,
- worker failure,
- DB unavailable,
- DB connection exhaustion,
- external provider sustained failure,
- crash-rate spike,
- job stuck,
- reconciliation mismatch,
- uptime failure.

Only require those applicable to the system.

---

# 35. Alert Noise Audit

Look for:

- per-request paging,
- duplicate alerts from multiple tools,
- alerts triggered by expected user validation,
- thresholds with no duration window,
- flapping.

Alert fatigue can make observability ineffective.

---

# 36. Dashboard Verification

Verify dashboards answer:

- Is the system healthy?
- Are users experiencing errors?
- Which service is failing?
- Is latency abnormal?
- Is a dependency failing?
- Are queues backing up?
- Did this begin after a deployment?

---

# 37. Health Check Verification

Verify:

- liveness represents process health,
- readiness represents ability to serve traffic,
- critical dependency checks appropriate,
- optional dependency failure does not necessarily fail liveness,
- endpoint does not expose secrets/internal details.

---

# 38. Job/Queue Observability Verification

Inspect:

- failed job capture,
- retries visible,
- dead-letter visible,
- queue age visible,
- job duration visible,
- job identity/correlation available.

---

# 39. Integration Observability Verification

For each provider verify ability to diagnose:

- request sent,
- response class,
- provider request/event ID,
- timeout,
- retry,
- final failure,
- local entity affected.

---

# 40. Audit Trail Verification

For critical state changes, verify audit information is durable where required.

Flag ordinary application logs being incorrectly treated as durable audit history when retention/mutability do not support that use.

---

# 41. Sensitive Data Logging Cross-Check

Without performing the full privacy/security audit, inspect obvious risks:

- passwords,
- access tokens,
- refresh tokens,
- API keys,
- full payment card data,
- authorization headers,
- sensitive personal payloads.

Escalate findings to Security/Privacy audit.

---

# 42. AI-Agent-Specific Observability Audit

Mandatory when AI agents were used.

Actively search for:

## 42.1 Console-only diagnostics

- `console.log`
- `print`
- debug statements as sole error visibility.

## 42.2 Misleading success logs

- log `"success"` before DB commit/provider confirmation,
- success logged in `finally`.

## 42.3 Silent catch patterns

- catch-and-return-default,
- catch-and-ignore.

## 42.4 Inconsistent logging libraries

- multiple agents introducing different loggers,
- structured logger bypassed in new modules.

## 42.5 Missing context

- generated logs like `"Error occurred"` with no IDs, endpoint, or operation.

## 42.6 Excessive logs

- log every render,
- log full payload,
- log in large loops,
- repeated exception at every layer.

## 42.7 Duplicate error reporting

- same exception captured manually and globally several times.

## 42.8 Missing release/env tags

- error tool installed but all environments mixed together.

## 42.9 Mocked monitoring

- placeholder metrics,
- fake health endpoint,
- TODO alert configuration.

---

# 43. Static Verification Matrix

| Check ID | Category | Scope | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 44. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Logging quality reviewed.
- [ ] Silent failures reviewed.
- [ ] Correlation reviewed.
- [ ] Release/version tagging reviewed.
- [ ] Error tracking reviewed.
- [ ] Critical metrics reviewed.
- [ ] Alert coverage/quality reviewed.
- [ ] Dashboards reviewed.
- [ ] Health checks reviewed.
- [ ] Job/integration observability reviewed.
- [ ] AI-generated observability risks reviewed.
- [ ] OB0/OB1 candidates have evidence.

---

# PHASE 2B — CONTROLLED SIGNAL VALIDATION

# 45. Objective

Prove that critical events actually generate usable signals.

### Mandatory restrictions

- Prefer staging/test.
- Use synthetic users/data.
- Do not trigger production paging.
- Do not create alert storms.
- Do not leak secrets in test payloads.
- Mark synthetic events clearly.

---

# 46. Signal Test Categories

| Prefix | Category |
|---|---|
| `OBS-LOG-xx` | Logging |
| `OBS-ERR-xx` | Error tracking |
| `OBS-MET-xx` | Metrics |
| `OBS-TRACE-xx` | Tracing |
| `OBS-ALT-xx` | Alerting |
| `OBS-HEALTH-xx` | Health |
| `OBS-JOB-xx` | Jobs |
| `OBS-INT-xx` | Integrations |
| `OBS-AUDIT-xx` | Audit trail |

---

# 47. Controlled Signal Matrix

| Test ID | Trigger | Expected signal | Required context | Destination | Actual result | Alert? | Evidence | Result |
|---|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 48. Application Error Test

Trigger a safe known application error.

Verify:

- error captured,
- stack/source available,
- environment correct,
- release correct,
- correlation ID present,
- user/request context appropriate,
- no secrets exposed.

---

# 49. Backend 5xx Signal Test

Trigger controlled backend failure.

Verify:

- structured error log,
- request ID,
- endpoint,
- latency/error metric increment,
- error tracker event if intended,
- alert behavior if threshold met.

---

# 50. External Provider Failure Signal Test

Simulate provider failure.

Verify signal distinguishes:

- internal failure,
- provider failure,
- timeout,
- provider status class.

Verify provider request/event identifier stored when appropriate.

---

# 51. Queue / Job Failure Signal Test

Trigger safe failed job.

Verify:

- failure visible,
- retry attempt visible,
- final dead-letter/failed state visible,
- queue metrics update,
- alert if critical.

---

# 52. Health Check Test

Test:

- healthy service,
- critical dependency unavailable,
- optional dependency unavailable.

Verify liveness/readiness behave intentionally.

---

# 53. Correlation Test

Execute one critical journey.

Verify reviewer can follow a stable ID through relevant layers.

---

# 54. Alert Test

For critical alerts, use safe test mechanism where available.

Verify:

- alert fires,
- destination correct,
- severity correct,
- message contains actionable context,
- runbook/link present if intended,
- resolution behavior understood.

---

# 55. Release Tag Test

Deploy/test or simulate tagged release where feasible.

Verify new error/log includes expected version/commit.

---

# 56. Signal Latency Test

For critical alerts/errors record:

- event occurrence time,
- ingestion time,
- alert time.

Flag excessive delay for urgent conditions.

---

# 57. Controlled Signal Validation Summary

| Metric | Count |
|---|---:|
| Signal tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| OB0 findings | `{}` |
| OB1 findings | `{}` |
| OB2 findings | `{}` |

---

# 58. Controlled Signal Exit Gate

Phase 2B passes only when:

- [ ] Critical app/backend errors produce signals.
- [ ] Critical provider failures produce signals.
- [ ] Critical queue/job failures produce signals where applicable.
- [ ] Correlation verified.
- [ ] Health checks verified.
- [ ] Critical alerts tested or explicitly blocked.
- [ ] Release/environment tagging verified.
- [ ] Every FAIL has a finding ID.
- [ ] No critical observability claim is based only on SDK installation.

---

# 59. Finding Register

| Finding ID | Category | Severity | Signal / Area | Summary | Evidence | Diagnostic impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `OB-001` | `{}` | `{OB0-OB4}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 60. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** It requires technical review and a separate implementation decision. Nothing below should be described as fixed until controlled signal validation is rerun successfully.

---

# 61. Objective

Design observability improvements around operational questions:

- What failed?
- Where?
- For whom/which transaction?
- Since when?
- How often?
- After which release?
- Is it getting worse?
- Who needs to act?

---

# 62. Root-Cause Map

| Finding | Blind spot | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `OB-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 63. Remediation Principles

| Principle | Application |
|---|---|
| Capture critical failure | No silent critical paths |
| Add context, not noise | IDs and operation context matter more than verbose text |
| Correlate across boundaries | Request/job/provider IDs |
| Alert on actionable conditions | Avoid noise |
| Tag releases | Diagnose regressions |
| Separate logs/metrics/traces | Use each for appropriate purpose |
| Preserve privacy | Never improve observability by leaking sensitive data |
| Test signals | Instrumentation is incomplete until verified |

---

# 64. Remediation Phase Table

| # | Action | Findings closed | Components | Signals added/changed | Alert impact | Privacy risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 65. Alert Design Requirements

Every new critical alert should define:

- condition,
- threshold,
- duration/window,
- severity,
- destination,
- owner,
- escalation,
- suppression/deduplication,
- runbook/action,
- test method.

---

# 66. Logging Design Requirements

For new critical logs define:

- event name,
- severity,
- context fields,
- correlation IDs,
- redaction rules,
- destination,
- sampling policy where relevant.

---

# 67. Remediation Exit Gate

Implementation-ready only when:

- [ ] Blind spot/root cause identified.
- [ ] Required signals defined.
- [ ] Correlation strategy defined.
- [ ] Alert action/owner defined.
- [ ] Privacy/security review considered.
- [ ] Noise risk considered.
- [ ] Retest defined.
- [ ] No unnecessary high-volume logging proposed.

---

# FINAL — OBSERVABILITY PRODUCTION READINESS REPORT

# 68. Objective

Produce one release decision for the exact audited version.

---

# 69. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Critical events covered
`{PASS}/{TOTAL}`

### Controlled signal tests
`{PASS}/{EXECUTED}`

### Open findings
- OB0: `{COUNT}`
- OB1: `{COUNT}`
- OB2: `{COUNT}`
- OB3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 70. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open OB0.
- Zero open OB1.
- Critical application/backend failures are captured.
- Critical provider failures are distinguishable.
- Critical queue/job failures are visible.
- Request/transaction correlation exists where needed.
- Release/environment tags exist.
- Critical metrics exist.
- Critical actionable alerts exist.
- Health/readiness signals are accurate.
- No critical silent-failure path remains.
- No critical observability unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero OB0.
- Zero launch-blocking OB1.
- Core incidents remain detectable and diagnosable.
- Remaining gaps are bounded OB2 issues.
- Release owner explicitly accepts residual risk.
- No critical unknown remains.

## 🔴 NO-GO

Use if:

- Any OB0 remains.
- Critical failures can occur silently.
- Critical payment/order/data errors cannot be detected.
- No usable error tracking/logging exists for core backend failures.
- Critical queues/jobs can fail silently.
- No way exists to correlate core transaction failures.
- Health check misrepresents service readiness in a dangerous way.
- Production alerts are absent for critical conditions.
- Critical monitoring behavior remains unknown.

---

# 71. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-OB-01` | Zero open OB0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-OB-02` | Zero launch-blocking OB1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-OB-03` | Critical errors captured | `{TESTS}` | `{PASS/FAIL}` |
| `LG-OB-04` | Critical provider failures observable | `{TESTS}` | `{PASS/FAIL}` |
| `LG-OB-05` | Critical jobs/queues observable | `{TESTS}` | `{PASS/FAIL}` |
| `LG-OB-06` | Correlation IDs verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-OB-07` | Release/environment tagging verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-OB-08` | Critical metrics available | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-OB-09` | Critical alerts actionable | `{TESTS}` | `{PASS/FAIL}` |
| `LG-OB-10` | Health/readiness accurate | `{TESTS}` | `{PASS/FAIL}` |
| `LG-OB-11` | No critical silent failures | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-OB-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 72. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-OB-001` | `{REF}` | `{OB}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 73. Out-of-Scope / Not Verified

Explicitly list:

- production alert route not tested,
- production dashboards unavailable,
- cloud infrastructure metrics excluded,
- mobile crash symbolication unavailable,
- distributed tracing not available,
- provider monitoring unavailable,
- audit logs not required/reviewed,
- long-term retention not verified,
- SIEM/security monitoring excluded,
- anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 74. Final One-Sentence Recommendation

### GO example

> Observability recommendation: **GO for production** for `{VERSION}` because all mandatory observability launch gates passed and critical failures, dependencies, jobs, and production health can be detected and diagnosed with sufficient context.

### CONDITIONAL GO example

> Observability recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented OB2 residual gaps; all critical production failures remain detectable and diagnosable.

### NO-GO example

> Observability recommendation: **NO-GO** for `{VERSION}` until findings `{OB-xxx...}` are remediated and the associated logging, error-tracking, correlation, alert, and health-check validations pass.

---

# 75. Required Deliverables

A complete Observability Audit should produce:

1. `01_OBSERVABILITY_DISCOVERY_REPORT.md`
2. `02_OBSERVABILITY_STATIC_VERIFICATION_REPORT.md`
3. `03_OBSERVABILITY_SIGNAL_TEST_REPORT.md`
4. `04_OBSERVABILITY_REMEDIATION_PLAN.md`
5. `05_OBSERVABILITY_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `CRITICAL_EVENT_INVENTORY.md`
- `LOGGING_CONTEXT_MATRIX.md`
- `ALERT_INVENTORY.md`
- `DASHBOARD_COVERAGE_MAP.md`
- `HEALTH_CHECK_MATRIX.md`
- `OBSERVABILITY_FINDINGS.csv`

---

# 76. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not change logging/alerting configuration during Discovery or Verification.
3. Do not trigger production paging without explicit authorization.
4. Do not assume an installed SDK is active.
5. Do not assume console logs are production observability.
6. Do not assume an exception is captured because it is thrown.
7. Do not assume a metric exists because a dashboard panel exists.
8. Do not assume an alert is useful because it is configured.
9. Verify critical events with controlled signal tests where possible.
10. Inspect silent catches and ignored async failures.
11. Inspect misleading success logs.
12. Inspect missing correlation IDs.
13. Inspect release/environment tagging.
14. Inspect queue/job failure visibility.
15. Inspect external-provider diagnostic context.
16. Do not log secrets or sensitive payloads.
17. Cite exact instrumentation/config paths.
18. Preserve stable finding IDs.
19. Cross-reference Security, Privacy, Reliability, Performance, API, and Database audits where relevant.
20. Retest signals before marking findings Verified Closed.
21. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 77. Completion Standard

This audit is complete only when an independent reviewer could answer:

- What logging/error/metrics/tracing tools exist?
- Which critical events must be visible?
- Are critical failures actually captured?
- Can requests/transactions be correlated?
- Is release/version context available?
- Are critical queues/jobs observable?
- Are provider failures distinguishable?
- Are health checks accurate?
- Are critical alerts actionable?
- Is alert noise controlled?
- Are dashboards sufficient to assess system health?
- What signal tests were actually executed?
- What remains unknown?
- What remediation is proposed versus verified?
- Can the team detect and diagnose realistic production failures after launch?

If those questions cannot be answered from the audit outputs, the audit is not complete.
