# Analytics & Business Events Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that an application's analytics and business-event instrumentation can produce trustworthy product, operational, and commercial measurements after launch.
>
> **Core rule:** Do not mark analytics PASS because an SDK is installed, a dashboard exists, or events appear in a debug console. Critical events must be validated end-to-end against their actual business meaning and source of truth.

---

# 0. Audit Objective

Determine whether analytics and business-event instrumentation are production-ready by verifying:

- Critical business KPIs are explicitly defined.
- Critical events are inventoried and consistently named.
- Events fire at the correct lifecycle point.
- Success events represent confirmed success rather than user intent.
- Critical financial events match backend/provider truth.
- Events are neither missing nor unintentionally duplicated.
- Event properties are stable and correctly typed.
- Anonymous/authenticated identity is handled consistently.
- Logout/account switching does not contaminate identity.
- Funnels can be reconstructed reliably.
- Activation and retention can be measured.
- Attribution persists where required.
- Client-side vs server-side event ownership is intentional.
- Environment/test data does not contaminate production reporting.
- Analytics can be reconciled against source-of-truth records.
- Dashboards use the same definitions as instrumentation.
- AI-generated code has not introduced duplicate trackers, inconsistent event names, stale events, placeholder tracking, or incorrect success triggers.

## Non-goals

This audit does not replace:

- Privacy/compliance audit.
- Observability audit.
- Financial accounting/reconciliation.
- Database-integrity audit.
- Product strategy or KPI-definition workshops.
- Marketing attribution modeling.
- BI/data-warehouse architecture review.

Cross-reference those audits where relevant.

---

# 1. Mandatory Methodology

| Stage | Name | Required work | Output |
|---|---|---|---|
| 1 | Discovery | Map KPIs, events, funnels, identity, event ownership, destinations, and dashboards | Analytics map |
| 2A | Static Verification | Inspect event definitions, trigger points, properties, identity, duplication, and reporting logic | Evidence matrix |
| 2B | Controlled Event Validation | Execute synthetic journeys and verify emitted/downstream events | Test report |
| 3 | Remediation Design | Design root-cause fixes — **do not implement unless separately authorized** | Remediation plan |
| Final | Production Readiness | Consolidate evidence into one decision | GO / CONDITIONAL GO / NO-GO |

### Golden rule

For every critical event verify:

`Business condition → Source of truth → Trigger location → Event name → Properties → Identity → Timestamp → Destination → Deduplication → Dashboard usage`

---

# 2. Report Header

| Field | Value |
|---|---|
| System | `{SYSTEM_NAME}` |
| Repository | `{REPOSITORY_NAME}` |
| Branch | `{BRANCH}` |
| Commit / Version | `{COMMIT_OR_VERSION}` |
| Phase | `{PHASE_NAME}` |
| Audit date | `{DATE}` |
| Environment | `{Local / Dev / Staging / Production}` |
| Analytics platform(s) | `{PLATFORM}` |
| Data warehouse / BI | `{PLATFORM / N/A}` |
| Synthetic test prefix | `{QA_PREFIX}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |

---

# 3. Evidence and Confidence

| Symbol | Meaning |
|---|---|
| 🟥 Confirmed by End-to-End Event Test | Synthetic journey produced verified downstream event |
| 🟧 Confirmed by Code / Schema / Dashboard | Direct static evidence |
| 🟨 Likely | Strong inference but incomplete runtime proof |
| 🟦 Requires Controlled Event Test | Must be executed |
| ⬜ N/A / False Positive | Not applicable or disproven |

Each finding must contain:

- Finding ID.
- KPI/event.
- Journey.
- Source of truth.
- Instrumentation location.
- Expected behavior.
- Actual behavior.
- Evidence.
- Severity.
- Confidence.
- Launch-blocker status.

---

# 4. Severity Model

| Level | Meaning | Launch treatment |
|---|---|---|
| **AE0 — Critical** | Core financial/conversion/activation data materially false, duplicated, missing, or irreconcilable | **Mandatory NO-GO** |
| **AE1 — High** | Critical KPI/funnel cannot be measured reliably | **Pre-launch blocker** |
| **AE2 — Medium** | Important measurement gap but core launch KPIs remain usable | Explicit acceptance required |
| **AE3 — Low** | Minor naming/property/reporting inconsistency | Backlog |
| **AE4 — Observation** | Improvement opportunity | Backlog |

Evaluate severity using:

- KPI criticality.
- Revenue impact.
- Funnel distortion.
- Retention/cohort distortion.
- Frequency.
- Detectability.
- Historical repairability.
- Downstream automation impact.

---

# PHASE 1 — DISCOVERY

# 5. KPI Inventory

Use IDs such as `KPI-001`.

| KPI ID | KPI | Business definition | Numerator | Denominator | Source of truth | Owner |
|---|---|---|---|---|---|---|
| `KPI-001` | `{KPI}` | `{DEFINITION}` | `{}` | `{}` | `{}` | `{}` |

If a business definition is missing, mark:

**PRODUCT / BUSINESS OWNER DEFINITION REQUIRED**

Do not invent definitions.

---

# 6. Critical Event Inventory

Use IDs such as `EV-001`.

| Event ID | Event name | Business meaning | Trigger condition | Source of truth | Criticality |
|---|---|---|---|---|---|
| `EV-001` | `{event_name}` | `{MEANING}` | `{WHEN}` | `{SERVER/DB/CLIENT/PROVIDER}` | `{Critical/High/Normal}` |

Typical examples:

- `signup_started`
- `signup_completed`
- `onboarding_completed`
- `checkout_started`
- `order_created`
- `booking_created`
- `payment_succeeded`
- `payment_failed`
- `refund_completed`
- `subscription_started`
- `subscription_cancelled`
- `account_deleted`

---

# 7. Funnel Inventory

Use IDs such as `FUN-001`.

| Funnel ID | Funnel | Steps | Success definition | Time window | Owner |
|---|---|---|---|---|---|
| `FUN-001` | `{FUNNEL}` | `{EV-...}` | `{}` | `{}` | `{}` |

Examples:

- Visitor → Signup Started → Signup Completed → Onboarding Completed → First Core Action
- Product Viewed → Cart → Checkout Started → Payment Succeeded

---

# 8. Activation Definition

Document:

- What exactly counts as activation?
- Is activation one event or a compound condition?
- Must it occur inside a time window?
- Is it based on a value-generating action?

If undefined:

**PRODUCT / BUSINESS OWNER DEFINITION REQUIRED**

---

# 9. Retention Definition

Document what qualifies a user as retained:

- login,
- app open,
- core action,
- purchase,
- active subscription,
- weekly/monthly value event.

Do not assume app-open equals meaningful retention.

---

# 10. Revenue / Financial Event Inventory

| Event | Financial state represented | Source of truth | Server-side? | Reconciled? |
|---|---|---|---|---|
| `{EVENT}` | `{AUTHORIZED/CAPTURED/REFUNDED/etc.}` | `{}` | `{YES/NO}` | `{YES/NO}` |

Verify handling of:

- amount,
- currency,
- discounts,
- tax,
- refunds,
- partial refunds,
- renewals,
- cancellations.

### Critical rule

**Do not use a payment-button click as a revenue event. Revenue should reflect confirmed backend/provider state.**

---

# 11. Analytics Platform Inventory

| Platform | Purpose | Client / server | Environments | SDK/config location |
|---|---|---|---|---|
| `{PLATFORM}` | `{}` | `{}` | `{}` | `{}` |

Include:

- product analytics,
- web analytics,
- mobile analytics,
- ad pixels,
- data warehouse,
- BI,
- CRM/CDP events.

---

# 12. Event Ownership

Classify each critical event as:

- client-side,
- server-side,
- webhook-driven,
- database-derived,
- batch-derived,
- intentionally emitted from multiple sources.

Flag client + server duplication without a deduplication strategy.

---

# 13. Event Schema Catalog

| Event | Required properties | Optional properties | Property types | PII? | Schema version |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Common properties may include:

- environment,
- release/app version,
- platform,
- locale,
- user ID,
- anonymous ID,
- account/organization ID,
- session ID,
- order/booking/payment ID,
- currency,
- campaign/source,
- timestamp.

---

# 14. Identity Model

Document:

- anonymous ID,
- authenticated user ID,
- account/tenant ID,
- device ID,
- session ID,
- identity merge/alias behavior,
- logout reset behavior,
- account switching.

Flag:

- user A events attributed to user B,
- anonymous ID regenerated unexpectedly,
- multiple incompatible user-ID formats.

---

# 15. Session Definition

If session metrics are used, document:

- start condition,
- timeout,
- background/foreground behavior,
- cross-device limitations.

---

# 16. Timestamp Model

Identify whether event time comes from:

- client clock,
- server time,
- provider timestamp,
- ingestion time.

Critical financial/business events should not rely blindly on an untrusted client clock.

---

# 17. Attribution Inventory

Where required, inventory:

- UTM source,
- medium,
- campaign,
- referrer,
- ad click IDs,
- referral code,
- install attribution.

Document how attribution survives signup/conversion.

---

# 18. Experiment / Feature-Flag Analytics

Where applicable:

- assignment event,
- exposure event,
- variant,
- assignment source,
- exposure timing,
- conversion linkage.

Flag conversion analysis that lacks verified exposure.

---

# 19. Dashboard / Report Inventory

| Dashboard | KPIs/events | Data source | Owner | Environment filter | Trusted? |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO/UNKNOWN}` |

---

# 20. Source-of-Truth Reconciliation Inventory

| Event | Source-of-truth comparison | Frequency | Expected tolerance | Owner |
|---|---|---|---|---|
| `{}` | `{DB/PROVIDER/etc.}` | `{}` | `{}` | `{}` |

Prioritize:

- orders,
- payments,
- subscriptions,
- bookings,
- refunds,
- activation events.

---

# 21. Discovery Execution Log

### Fully reviewed
`{AREAS}`

### Partially reviewed
`{AREAS}`

### Structurally scanned
`{AREAS}`

### Could not inspect
`{AREAS + REASON}`

### Actions performed
| Action | Purpose | Result |
|---|---|---|

### Actions deliberately avoided
| Action | Reason |
|---|---|

---

# 22. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Critical KPIs identified or definition gaps documented.
- [ ] Critical events inventoried.
- [ ] Funnels mapped.
- [ ] Activation and retention definitions documented or escalated.
- [ ] Financial events mapped.
- [ ] Analytics platforms mapped.
- [ ] Event ownership known.
- [ ] Event schemas identified.
- [ ] Identity/session model understood.
- [ ] Attribution requirements understood.
- [ ] Dashboards/reports inventoried.
- [ ] Reconciliation paths identified.
- [ ] Unknown areas listed.

---

# PHASE 2A — STATIC VERIFICATION

# 23. Stable Check Prefixes

| Prefix | Category |
|---|---|
| `NAME-xx` | Event naming |
| `TRIG-xx` | Trigger timing |
| `PROP-xx` | Event properties |
| `TYPE-xx` | Property types |
| `ID-xx` | Identity |
| `SESS-xx` | Sessions |
| `DUP-xx` | Duplicates |
| `MISS-xx` | Missing events |
| `REV-xx` | Revenue |
| `FUN-xx` | Funnels |
| `ACT-xx` | Activation |
| `RET-xx` | Retention |
| `ATTR-xx` | Attribution |
| `EXP-xx` | Experiments |
| `ENV-xx` | Environment contamination |
| `DASH-xx` | Dashboards |
| `RECON-xx` | Reconciliation |
| `AI-xx` | AI-agent-specific defects |

---

# 24. Event Naming Audit

Verify:

- one naming convention,
- stable tense,
- stable vocabulary,
- no semantic duplicates.

Flag combinations such as:

- `order_complete`
- `order_completed`
- `completed_order`

when they represent the same business state.

---

# 25. Trigger Timing Audit

For every critical event verify it fires only when the represented state is actually true.

Examples:

- `signup_completed` after account creation succeeds.
- `payment_succeeded` after backend/provider confirmation.
- `booking_created` after booking persistence succeeds.

---

# 26. Duplicate Event Audit

Search for:

- event emitted from UI and service layer,
- event emitted from UI and backend,
- event firing on every render,
- duplicate lifecycle hooks,
- retries producing duplicate critical events,
- duplicate webhook-driven events.

---

# 27. Missing Event Audit

Compare event coverage against critical journeys.

Check for missing:

- success,
- failure,
- cancellation,
- refund,
- renewal,
- deletion,
- abandonment where business needs it.

---

# 28. Property Audit

Verify:

- required properties always present,
- types stable,
- null behavior known,
- enum vocabulary consistent,
- identifiers correct,
- financial amount/currency correct.

---

# 29. Property-Type Drift Audit

Flag patterns such as:

- amount sometimes number and sometimes string,
- booleans sent as `"true"`,
- IDs alternating integer/string,
- inconsistent enum spelling,
- currency sometimes omitted.

---

# 30. Identity Audit

Verify:

- identity set after authentication appropriately,
- logout resets identity where intended,
- account switching does not leak identity,
- anonymous history merge behavior matches product expectation.

---

# 31. Environment Contamination Audit

Verify:

- staging/dev events labeled or separated,
- production dashboards filter correctly,
- synthetic QA users can be identified/excluded,
- production and test analytics keys/projects are not confused.

---

# 32. Financial Event Audit

Verify:

- event triggered from authoritative state,
- exact amount,
- currency,
- order/payment ID,
- refunds handled,
- duplicate callbacks do not duplicate revenue.

Cross-reference API and Database audits.

---

# 33. Funnel Audit

For every funnel verify:

- all steps exist,
- identity survives between steps,
- event sequence is logically possible,
- success definition matches KPI.

---

# 34. Activation Audit

Verify that activation can be calculated from actual available events/data.

---

# 35. Retention Audit

Verify retention metric reflects the approved business definition.

---

# 36. Attribution Audit

Verify:

- attribution captured at entry,
- persisted,
- preserved through conversion,
- not overwritten unexpectedly.

---

# 37. Experiment Analytics Audit

Verify:

- exposure occurs only when user actually receives variant,
- stable assignment,
- variant captured,
- conversion can be linked to exposure.

---

# 38. Dashboard Definition Audit

Compare dashboard logic against canonical KPI/event definitions.

Flag:

- old event name,
- wrong denominator,
- staging data included,
- revenue based on intent event,
- query that excludes valid states.

---

# 39. Reconciliation Audit

For critical metrics compare analytics counts to authoritative records.

If no reconciliation exists for critical financial/business metrics, record risk.

---

# 40. Privacy Cross-Check

Without replacing Privacy Audit:

- identify unnecessary PII,
- identify sensitive properties,
- verify optional tracking dependencies where applicable.

Escalate privacy findings.

---

# 41. AI-Agent-Specific Analytics Audit

Mandatory where AI agents were used.

Actively search for:

## 41.1 Inconsistent event vocabulary
Different agents create different names for the same behavior.

## 41.2 Click tracked as completion
Intent is incorrectly recorded as successful business outcome.

## 41.3 Duplicate instrumentation
Client, service, and backend all emit the same event without deduplication.

## 41.4 Placeholder events
Examples:
- `track("event")`
- `button_clicked`
- TODO event names.

## 41.5 Stale events
Removed feature still sends events or dashboards still use old names.

## 41.6 Schema drift
Same event has different properties/types in different files.

## 41.7 Identity mistakes
Random IDs, user identify before auth, failure to clear identity.

## 41.8 Fake coverage
Analytics wrapper exists but critical journeys never invoke it.

## 41.9 Duplicate analytics libraries
Multiple SDKs added for overlapping purposes without intention.

---

# 42. Static Verification Matrix

| Check ID | Category | Event/KPI | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 43. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Naming reviewed.
- [ ] Trigger timing reviewed.
- [ ] Duplicates/missing events reviewed.
- [ ] Property schemas reviewed.
- [ ] Identity/session reviewed.
- [ ] Financial events reviewed.
- [ ] Funnel/activation/retention reviewed.
- [ ] Attribution reviewed where applicable.
- [ ] Dashboards reviewed.
- [ ] Reconciliation reviewed.
- [ ] AI-generated analytics risks reviewed.
- [ ] AE0/AE1 candidates have evidence.

---

# PHASE 2B — CONTROLLED EVENT VALIDATION

# 44. Rules

- Prefer staging/test analytics workspace.
- Use synthetic users/data.
- Prefix synthetic IDs when possible.
- Do not contaminate production reporting.
- Do not include real sensitive data.
- Record exact timestamps and event IDs where available.

---

# 45. Test Prefixes

| Prefix | Category |
|---|---|
| `AE-EVENT-xx` | Event emission |
| `AE-DUP-xx` | Duplicate behavior |
| `AE-ID-xx` | Identity |
| `AE-FUN-xx` | Funnel |
| `AE-REV-xx` | Revenue |
| `AE-ATTR-xx` | Attribution |
| `AE-ENV-xx` | Environment separation |
| `AE-RECON-xx` | Reconciliation |

---

# 46. Controlled Event Matrix

| Test ID | Journey | Expected events | Expected properties | Expected identity | Actual downstream result | Evidence | Result |
|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 47. Critical Journey Event Test

For each critical journey:

1. Create synthetic user.
2. Perform journey.
3. Record timestamps.
4. Inspect debug/event stream.
5. Verify downstream event.
6. Verify order.
7. Verify properties.
8. Verify identity.
9. Verify no unintended duplicate.

---

# 48. Success vs Failure Test

Execute one successful and one controlled failed operation.

Verify:

- success event only on actual success,
- failure event behaves as designed,
- contradictory success/failure events do not both fire incorrectly.

---

# 49. Duplicate Submission Test

Repeat, refresh, retry, or replay the same logical action.

Verify critical-event duplication behavior.

---

# 50. Identity Transition Test

Test:

1. anonymous browsing,
2. signup/login,
3. authenticated action,
4. logout,
5. second user login.

Verify identity remains correct throughout.

---

# 51. Revenue Event Test

Using sandbox/synthetic payment flow:

- initiate,
- receive backend/provider confirmation,
- inspect event,
- verify one event,
- verify amount/currency/order/payment identifiers.

Do not use real charges unless separately authorized.

---

# 52. Refund / Cancellation Test

Where applicable:

- create synthetic successful transaction,
- refund/cancel,
- verify reversal event semantics,
- verify reporting can account for reversal.

---

# 53. Funnel Reconstruction Test

Execute full funnel for one synthetic user and verify downstream analytics can reconstruct every intended step.

---

# 54. Attribution Persistence Test

Where applicable:

- enter using test attribution parameters,
- navigate,
- signup,
- convert,
- verify attribution persists according to approved model.

---

# 55. Environment Isolation Test

Verify staging/test events do not distort production dashboards or are safely filterable.

---

# 56. Reconciliation Test

Use a controlled sample.

Example:

`10 confirmed synthetic orders → exactly 10 order_created events`

Document acceptable ingestion latency.

---

# 57. Controlled Validation Summary

| Metric | Count |
|---|---:|
| Tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| AE0 findings | `{}` |
| AE1 findings | `{}` |
| AE2 findings | `{}` |
| Critical reconciliations passed | `{}` |

---

# 58. Controlled Validation Exit Gate

Phase 2B passes only when:

- [ ] Critical events validated end-to-end.
- [ ] Success triggers verified.
- [ ] Duplicate behavior tested.
- [ ] Identity transition tested.
- [ ] Financial events tested where applicable.
- [ ] Funnel reconstruction tested.
- [ ] Environment isolation verified.
- [ ] Critical reconciliation performed where applicable.
- [ ] Every FAIL has finding ID.
- [ ] No critical event is marked PASS only because code exists.

---

# 59. Finding Register

| Finding ID | Category | Severity | Event/KPI | Summary | Evidence | Business impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `AE-001` | `{}` | `{AE0-AE4}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 60. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** Analytics changes may affect historical continuity, KPI definitions, dashboards, attribution, and downstream automation. Nothing below should be described as fixed until event validation and reporting checks pass.

---

# 61. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `AE-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 62. Remediation Principles

| Principle | Application |
|---|---|
| Measure business truth | Events represent confirmed states |
| Define before instrumenting | KPI/event meaning explicit |
| One canonical event | Avoid semantic duplicates |
| Stable schema | Property names/types controlled |
| Identity intentionally | Anonymous/auth transitions explicit |
| Reconcile critical metrics | Analytics compared with source of truth |
| Separate environments | QA/staging cannot distort production |
| Preserve continuity | Renames/schema changes documented |
| Retest reporting | Event fix incomplete if dashboards remain wrong |

---

# 63. Event Migration Requirements

If renaming/replacing an event, document:

- old event,
- new event,
- transition date,
- dashboard impact,
- historical mapping,
- downstream consumers,
- deprecation plan.

---

# 64. Property Schema Change Requirements

Document:

- property,
- old type/meaning,
- new type/meaning,
- consumers,
- compatibility,
- rollout sequence.

---

# 65. Dashboard Remediation Requirements

Document:

- KPI definition,
- affected dashboards,
- event/query change,
- environment filters,
- validation query,
- owner.

---

# 66. Remediation Phase Table

| # | Action | Findings closed | Events/KPIs | Dashboard impact | Continuity risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 67. Remediation Exit Gate

Implementation-ready only when:

- [ ] Business definition confirmed.
- [ ] Event ownership defined.
- [ ] Trigger point explicit.
- [ ] Property schema explicit.
- [ ] Identity behavior defined.
- [ ] Reporting impact identified.
- [ ] Historical continuity understood.
- [ ] Reconciliation test defined.
- [ ] No generic “track more events” fix proposed without business purpose.

---

# FINAL — ANALYTICS & BUSINESS EVENTS PRODUCTION READINESS REPORT

# 68. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Critical KPIs measurable
`{COUNT}/{TOTAL}`

### Critical events validated
`{PASS}/{EXECUTED}`

### Critical reconciliations
`{PASS}/{TOTAL}`

### Open findings
- AE0: `{COUNT}`
- AE1: `{COUNT}`
- AE2: `{COUNT}`
- AE3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 69. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open AE0.
- Zero open AE1.
- Critical launch KPIs are measurable.
- Critical events have stable definitions.
- Success events fire only after actual success.
- Financial/revenue events reflect source-of-truth state.
- Critical events are not unintentionally duplicated.
- Identity transitions are correct.
- Critical funnels can be reconstructed.
- Staging/test events do not distort production.
- Critical analytics can be reconciled against source-of-truth data.
- No critical analytics unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero AE0.
- Zero launch-blocking AE1.
- Core launch KPIs remain reliable.
- Remaining gaps are bounded AE2 issues.
- Business/release owner explicitly accepts residual risk.
- No critical unknown remains.

## 🔴 NO-GO

Use if:

- Any AE0 remains.
- Revenue/payment metrics are materially false or duplicated.
- Activation/conversion KPI cannot be measured.
- Success events fire on intent rather than confirmed outcome.
- Critical funnel steps are missing.
- Identity attribution is materially wrong.
- Test/staging traffic contaminates production reporting materially.
- Core business events cannot be reconciled.
- Critical measurement behavior remains unknown.

---

# 70. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-AE-01` | Zero open AE0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-AE-02` | Zero launch-blocking AE1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-AE-03` | Critical KPIs defined/measurable | `{KPI INVENTORY}` | `{PASS/FAIL}` |
| `LG-AE-04` | Critical events validated | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AE-05` | Success triggers reflect true success | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AE-06` | Financial events accurate | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-AE-07` | Duplicate event behavior controlled | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AE-08` | Identity behavior verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AE-09` | Critical funnels reconstructable | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AE-10` | Environment isolation verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AE-11` | Critical reconciliation passes | `{RECON}` | `{PASS/FAIL}` |
| `LG-AE-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 71. KPI Readiness Table

| KPI | Definition confirmed? | Required events available? | Reconciled? | Ready? |
|---|---|---|---|---|
| `{KPI}` | `{YES/NO}` | `{YES/NO}` | `{YES/NO/N/A}` | `{YES/NO}` |

---

# 72. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Business impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-AE-001` | `{REF}` | `{AE}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 73. Out-of-Scope / Not Verified

Explicitly list:

- production analytics workspace unavailable,
- historical data quality not reviewed,
- ad-platform attribution not tested,
- BI warehouse excluded,
- CRM/CDP sync excluded,
- long-term cohort calculations excluded,
- privacy/legal tracking requirements handled separately,
- anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 74. Final One-Sentence Recommendation

### GO example

> Analytics & Business Events recommendation: **GO for production** for `{VERSION}` because all mandatory measurement gates passed and critical launch KPIs, conversion events, financial outcomes, identity, and funnels can be measured and reconciled reliably.

### CONDITIONAL GO example

> Analytics & Business Events recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented AE2 measurement gaps; all critical launch KPIs remain trustworthy.

### NO-GO example

> Analytics & Business Events recommendation: **NO-GO** for `{VERSION}` until findings `{AE-xxx...}` are remediated and the associated event, identity, financial, funnel, environment-isolation, and reconciliation validations pass.

---

# 75. Required Deliverables

A complete Analytics & Business Events Audit should produce:

1. `01_ANALYTICS_DISCOVERY_REPORT.md`
2. `02_ANALYTICS_STATIC_VERIFICATION_REPORT.md`
3. `03_ANALYTICS_EVENT_VALIDATION_REPORT.md`
4. `04_ANALYTICS_REMEDIATION_PLAN.md`
5. `05_ANALYTICS_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `KPI_DICTIONARY.md`
- `EVENT_TAXONOMY.md`
- `EVENT_SCHEMA_CATALOG.md`
- `FUNNEL_MAP.md`
- `IDENTITY_MODEL.md`
- `ANALYTICS_RECONCILIATION_REPORT.md`
- `ANALYTICS_FINDINGS.csv`

---

# 76. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not invent KPI definitions.
3. Do not change instrumentation during Discovery or Verification.
4. Do not send test events into production unless safely isolated.
5. Do not assume installed SDK means analytics works.
6. Do not assume button click equals business success.
7. Inspect exact lifecycle trigger for critical events.
8. Inspect duplicate event paths.
9. Inspect missing failure/cancellation events.
10. Inspect property schema/type consistency.
11. Inspect identity changes on login/logout/account switching.
12. Inspect financial events against backend/provider truth.
13. Inspect environment contamination.
14. Inspect dashboard definitions against event definitions.
15. Inspect source-of-truth reconciliation.
16. Inspect AI-generated generic, stale, duplicate, or fake events.
17. Cite exact instrumentation paths and dashboard/query definitions when available.
18. Preserve stable finding IDs.
19. Cross-reference Privacy, Observability, Database, API, Functional QA, and Release audits where relevant.
20. Retest events and reports before marking findings Verified Closed.
21. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 77. Completion Standard

This audit is complete only when an independent reviewer could answer:

- What are the critical launch KPIs?
- How is each KPI defined?
- Which events support each KPI?
- When does each critical event fire?
- Are event properties stable?
- Is identity handled correctly?
- Are success events tied to true backend success?
- Are financial/revenue events accurate?
- Are duplicate events controlled?
- Are funnels reconstructable?
- Are activation and retention measurable?
- Is attribution preserved where required?
- Are staging/test events isolated?
- Can analytics be reconciled against source-of-truth records?
- What event tests were actually executed?
- What remains unknown?
- What remediation is proposed versus verified?
- Can this exact version produce trustworthy business and product measurement after launch?

If those questions cannot be answered from the audit outputs, the audit is not complete.
