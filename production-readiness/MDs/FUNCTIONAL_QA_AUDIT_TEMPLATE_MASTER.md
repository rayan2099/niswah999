# Functional QA Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that an application behaves correctly from the user's perspective before launch.
>
> This template is designed for projects built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark a feature PASS because code exists or because the UI looks complete. Critical behavior must be proven through controlled execution whenever possible.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current build is functionally ready for production by verifying:

- Critical user journeys complete successfully end-to-end.
- Each role can do what it should do — and cannot do what it should not do.
- Forms, validation, CRUD operations, state changes, calculations, and business rules behave as intended.
- Frontend behavior matches backend behavior and persisted data.
- Loading, empty, error, offline, retry, timeout, and permission-denied states are handled correctly.
- External integrations fail safely and recover predictably.
- Repeated actions, refreshes, duplicate submissions, and concurrent actions do not create inconsistent state.
- Users receive accurate success/error feedback.
- Important behavior works across the supported devices, browsers, platforms, screen sizes, and app lifecycle states.
- No critical feature is only visually implemented, mocked, stubbed, hardcoded, or disconnected from its real data source.
- Known functional defects are explicitly tracked to a launch decision.

## 0.2 Non-goals

This audit does **not** replace:

- Security testing.
- Performance/load testing.
- Privacy/legal review.
- Accessibility certification.
- Infrastructure/DevOps review.
- Disaster-recovery validation.

If one of those areas creates an obvious functional blocker during this audit, record it and cross-reference the appropriate specialist audit.

## 0.3 Mandatory methodology

Use the following stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Understand the application, users, roles, routes, features, business rules, data flow, and integrations without changing the system | Functional map |
| 2A | **Verification Design** | Convert discovered behavior into explicit expected outcomes and a controlled test matrix | Approved test plan |
| 2B | **Controlled Execution** | Execute functional tests against an approved environment using controlled test accounts/data | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design fixes for failed behavior and identify regression tests — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence and issue a launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**Never convert an assumption into a PASS.**

If runtime evidence is unavailable, use **INCONCLUSIVE / REQUIRES CONTROLLED TEST**, document the missing evidence, and keep the affected launch gate open when the behavior is critical.

---

# 1. Report Header

Use this header in every phase report:

| Field | Value |
|---|---|
| System | `{SYSTEM_NAME}` |
| Version / Commit | `{VERSION_OR_COMMIT}` |
| Phase | `{PHASE_NAME}` |
| Audit date | `{DATE}` |
| Previous report | `{PREVIOUS_REPORT_FILENAME}` |
| Environment | `{Local / Dev / Staging / Production}` |
| Environment status | `{🧪 Controlled / 🔴 Live production}` |
| Test accounts | `{ROLES_USED — never include passwords/tokens}` |
| Testing method | `{Static review / Browser / Mobile device / API client / Automated tests / Mixed}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 2. Evidence and Confidence Key

Use the same symbols throughout all reports:

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Runtime Test** | Behavior was directly executed and observed in an approved environment |
| 🟧 **Confirmed by Code** | Behavior is clearly supported by specific implementation evidence, but runtime behavior was not fully proven |
| 🟨 **Likely** | Strong inference, but direct evidence is incomplete |
| 🟦 **Requires Controlled Test** | Must be executed in an approved environment before a conclusion can be reached |
| ⬜ **Not Applicable / False Positive** | Does not apply or was proven irrelevant |

For every important conclusion, include:

- Evidence type.
- File/path, route, component, API, screen, database object, or test identifier where applicable.
- Expected behavior.
- Observed behavior.
- Final result.

---

# 3. Functional Severity Model

Do not confuse severity with inconvenience.

| Level | Classification | Functional meaning | Launch treatment |
|---|---|---|---|
| **P0** | Critical | Data loss/corruption, wrong payment/financial result, account takeover through functional logic, total failure of a core journey, irreversible wrong state, or system-wide blocker | **Mandatory NO-GO** |
| **P1** | High | A primary user journey fails, major role cannot complete its job, critical business rule is wrong, or common users are blocked without a safe workaround | **Pre-launch blocker** |
| **P2** | Medium | Important behavior is defective but a safe, documented workaround exists and core journeys remain usable | Requires explicit acceptance |
| **P3** | Low | Cosmetic/minor functional inconsistency with negligible operational impact | May ship if documented |
| **P4** | Observation | Improvement, ambiguity, or non-blocking product-quality note | Backlog |

## 3.1 Impact dimensions

For every P0–P2 defect, record:

- Roles affected.
- Feature/journey affected.
- Frequency or reproduction rate.
- Data impact.
- Financial impact.
- Operational impact.
- Recoverability.
- Workaround availability.
- Whether existing users/data are affected.
- Whether the defect becomes more severe at production scale.

---

# 4. Environment Warning

When testing is not being performed on live production:

| Dimension | Evaluation |
|---|---|
| Functional severity | Based on the defect itself |
| Current actual impact | Based on the controlled environment and available data |
| Production impact | State what would happen if the same defect reaches launch |
| Procedural classification | Treat unresolved P0/P1 issues as **Pre-Launch Blockers**, not active incidents unless live users/data are already affected |

Never perform destructive tests, irreversible writes, real charges, real user messaging, or production data manipulation unless explicitly authorized.

---

# PHASE 1 — DISCOVERY

## 5. Objective

Build an accurate map of how the application is supposed to work before judging whether it works.

### Mandatory restrictions

During discovery:

- Prefer read-only inspection.
- Do not modify source code.
- Do not run destructive database commands.
- Do not trigger real payments, real emails/SMS/push notifications, or external side effects.
- Do not create production data.
- Do not assume a UI control is functional merely because it exists.
- Do not mark undocumented behavior as a defect until intended behavior is established.

---

# 6. System Definition

Document:

- Application type:
  - Web
  - Mobile
  - Desktop
  - API
  - Admin portal
  - Multi-application ecosystem
- Architecture:
  - Monolith
  - Modular monolith
  - Client/server
  - Microservices
  - Serverless
  - Hybrid
- Frontend technology.
- Backend technology.
- Database(s).
- Authentication system.
- State-management approach.
- File/object storage.
- Background jobs/queues.
- Third-party services.
- Payment providers.
- Notification providers.
- Analytics providers.
- Feature-flag system.
- Supported deployment environments.

---

# 7. Role and Permission Map

Create a complete role inventory.

| Role | How created | Primary purpose | Main capabilities | Restricted capabilities | Evidence | Confidence |
|---|---|---|---|---|---|---|
| `{ROLE}` | `{METHOD}` | `{PURPOSE}` | `{CAPABILITIES}` | `{RESTRICTIONS}` | `{PATH/CONFIG}` | `{SYMBOL}` |

Include:

- Anonymous/guest.
- Authenticated user.
- User sub-types.
- Staff.
- Manager.
- Admin.
- Super-admin.
- Service/system actors.
- Partner/vendor roles.
- Suspended/deactivated users where applicable.

### Required question

**Does the backend enforce role behavior, or does the application only hide/show UI elements?**

Record the answer but defer security conclusions to the Security Audit.

---

# 8. Feature Inventory

Build a complete feature inventory from routes, screens, APIs, navigation, services, database usage, and documentation.

| ID | Feature | Role(s) | Entry point | Backend/API | Persistent data | External dependency | Criticality | Status |
|---|---|---|---|---|---|---|---|---|
| `FEAT-001` | `{FEATURE}` | `{ROLES}` | `{ROUTE/SCREEN}` | `{ENDPOINT/SERVICE}` | `{TABLE/COLLECTION}` | `{SERVICE}` | `{Critical/High/Normal}` | `{Discovered/Unclear}` |

Flag immediately:

- Mocked features.
- Placeholder UI.
- TODO behavior.
- Hardcoded results.
- Buttons without handlers.
- Disabled but visible controls.
- Backend endpoints with no UI.
- UI flows with no backend.
- Old/duplicate implementations.
- Experimental routes accessible in production builds.

---

# 9. Critical User Journeys

Define the journeys that must work for the product to deliver its core value.

Use IDs:

- `CJ-001`, `CJ-002`, ...
- A critical journey must be testable end-to-end.

Example structure:

| Journey ID | Role | Start | Steps | Expected final state | Data changed | Side effects | Criticality |
|---|---|---|---|---|---|---|---|
| `CJ-001` | `{ROLE}` | `{ENTRY}` | `{HIGH_LEVEL_STEPS}` | `{OUTCOME}` | `{DATA}` | `{EMAIL/PAYMENT/etc.}` | `{P0/P1/P2}` |

Typical journeys to look for:

- Registration.
- Login/logout.
- Password reset.
- Onboarding.
- Profile completion.
- Search/discovery.
- Create/read/update/delete primary objects.
- Checkout/payment.
- Booking/reservation.
- Ordering.
- Subscription.
- Upload/download.
- Messaging.
- Notifications.
- Driver/service-provider workflow.
- Staff/admin workflow.
- Cancellation/refund.
- Account deletion/deactivation.
- Re-authentication/session recovery.

Do not assume these apply. Include only what exists in the application.

---

# 10. Business Rule Inventory

Extract explicit and implicit business rules.

Use stable IDs:

- `BR-001`, `BR-002`, ...

| Rule ID | Rule | Source | Inputs | Expected decision/calculation | Where enforced | Ambiguity |
|---|---|---|---|---|---|---|
| `BR-001` | `{RULE}` | `{DOC/CODE/UI}` | `{INPUTS}` | `{RESULT}` | `{FRONTEND/BACKEND/BOTH}` | `{YES/NO}` |

Check especially:

- Prices.
- Fees.
- Discounts.
- Eligibility.
- Capacity.
- Availability.
- Time windows.
- Status transitions.
- Limits.
- Minimum/maximum values.
- Geographic rules.
- Subscription access.
- Role-specific behavior.
- Date/time/timezone logic.
- Rounding.
- Tax.
- Currency.
- Inventory.
- Cancellation logic.
- Refund logic.
- Quotas.
- Duplicate prevention.

If two sources conflict, mark the rule **UNRESOLVED** and do not invent the intended behavior.

---

# 11. State Machine Inventory

For each important entity, determine all valid states and transitions.

Examples:

- Order.
- Booking.
- Payment.
- Subscription.
- Delivery.
- Support request.
- Application.
- Account.

| Entity | Current state | Allowed next state(s) | Actor | Preconditions | Side effects | Invalid transitions |
|---|---|---|---|---|---|---|

Flag:

- Impossible states.
- Missing terminal states.
- UI/backend state mismatch.
- Status that can move backwards unexpectedly.
- Transitions with no authorization/validation.
- Duplicate terminal actions.
- State changes that are not transactional.

---

# 12. Integration Inventory

| Integration ID | Service | Purpose | Trigger | Success behavior | Failure behavior | Retry | Timeout | Sandbox available? |
|---|---|---|---|---|---|---|---|---|
| `INT-001` | `{SERVICE}` | `{PURPOSE}` | `{TRIGGER}` | `{EXPECTED}` | `{EXPECTED}` | `{YES/NO}` | `{VALUE}` | `{YES/NO}` |

Examples:

- Payment gateway.
- Email.
- SMS.
- Push notifications.
- Maps/geocoding.
- File storage.
- AI service.
- POS/ERP/CRM.
- Identity provider.
- Webhooks.
- External APIs.

---

# 13. Existing Test Inventory

Document:

- Unit tests.
- Integration tests.
- End-to-end tests.
- Widget/component tests.
- API tests.
- Snapshot tests.
- Manual QA documents.
- Test fixtures.
- Seed scripts.
- Staging test accounts.

For each suite:

| Test suite | Type | Scope | Runs successfully? | Last known result | Gaps | Confidence |
|---|---|---|---|---|---|---|

Do not count a test file as evidence that tests pass. If it was not executed, state that clearly.

---

# 14. Discovery Execution Log

Document:

### Fully reviewed
`{FILES / MODULES / ROUTES}`

### Partially reviewed
`{FILES / MODULES / ROUTES}`

### Structurally scanned only
`{AREAS}`

### Could not inspect
`{AREAS + REASON}`

### Commands/actions performed
| Action | Purpose | Result |
|---|---|---|

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|

---

# 15. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Core roles are identified.
- [ ] Feature inventory exists.
- [ ] Critical user journeys are identified.
- [ ] Important business rules are mapped.
- [ ] Important entity states are mapped.
- [ ] External integrations are identified.
- [ ] Existing tests are inventoried.
- [ ] Unknowns that could change expected behavior are explicitly listed.
- [ ] Areas not reviewed are explicitly listed.

If any critical journey cannot be defined because expected behavior is unknown, Phase 1 is **INCOMPLETE**.

---

# PHASE 2A — VERIFICATION DESIGN

## 16. Objective

Translate the application map into executable tests with explicit expected results.

No test may be considered valid if the expected outcome is undefined.

---

# 17. Test Data Plan

Define controlled test identities and data.

Use clearly marked synthetic data, for example:

`QA_{PROJECT}_{DATE}_{ROLE}_{CASE}`

Document:

| Test data | Purpose | Environment | Creation method | Cleanup method | Side effects |
|---|---|---|---|---|---|

Never place passwords, tokens, API secrets, full payment credentials, or sensitive live-user data inside the report.

---

# 18. Core Functional Test Categories

Use stable prefixes so defects can be traced from discovery through remediation.

| Prefix | Category |
|---|---|
| `AUTH-xx` | Authentication/session behavior |
| `ROLE-xx` | Role-specific functional behavior |
| `NAV-xx` | Navigation/routing/deep links |
| `FORM-xx` | Forms and field validation |
| `CRUD-xx` | Create/read/update/delete |
| `STATE-xx` | Status/state transitions |
| `BR-xx` | Business rules/calculations |
| `INT-xx` | External integrations |
| `ERR-xx` | Error/failure handling |
| `EDGE-xx` | Boundary/edge cases |
| `DUP-xx` | Duplicate/repeated actions/idempotency |
| `CONC-xx` | Concurrent actions/race behavior |
| `DATA-xx` | Data persistence/consistency |
| `NOTIF-xx` | Email/SMS/push/in-app notification behavior |
| `FILE-xx` | Upload/download/media behavior |
| `OFF-xx` | Offline/network interruption/recovery |
| `LIFE-xx` | App lifecycle/session restore/background/refresh |
| `ADMIN-xx` | Back-office/admin workflows |
| `CJ-xx` | Critical end-to-end journeys |

Use only categories relevant to the project.

---

# 19. Functional Test Matrix

Every executable test must use this structure:

| Test ID | Requirement / Journey | Role | Preconditions | Steps | Expected result | Data/side effect expected | Actual result | Evidence | Result |
|---|---|---|---|---|---|---|---|---|---|
| `{ID}` | `{REF}` | `{ROLE}` | `{PRECONDITIONS}` | `{STEPS}` | `{EXPECTED}` | `{EXPECTED_DATA}` | `{OBSERVED}` | `{SCREENSHOT/LOG/DB/API}` | `{PASS/FAIL/INCONCLUSIVE}` |

Allowed results:

- **PASS**
- **FAIL**
- **INCONCLUSIVE**
- **BLOCKED**
- **NOT APPLICABLE**

Never use "probably passes."

---

# 20. Required State Coverage

For each critical screen or operation, verify relevant states:

| State | Verified? | Test ID |
|---|---|---|
| Initial/default | `{}` | `{}` |
| Loading | `{}` | `{}` |
| Success | `{}` | `{}` |
| Empty | `{}` | `{}` |
| Validation error | `{}` | `{}` |
| Backend error | `{}` | `{}` |
| Timeout | `{}` | `{}` |
| Offline/network loss | `{}` | `{}` |
| Permission denied | `{}` | `{}` |
| Session expired | `{}` | `{}` |
| Partial/invalid data | `{}` | `{}` |
| Retry/recovery | `{}` | `{}` |

Do not force states that are impossible for the feature.

---

# 21. Boundary Value Coverage

For every numeric, date, capacity, distance, quantity, price, length, or eligibility boundary, test at minimum:

- Below minimum.
- Exactly minimum.
- Just above minimum.
- Normal value.
- Just below maximum.
- Exactly maximum.
- Above maximum.
- Null/empty where possible.
- Invalid format.
- Extreme but technically valid value.

Record each boundary as a separate test where behavior materially differs.

---

# 22. Form and Validation Coverage

Verify relevant behavior:

- Required fields.
- Optional fields.
- Min/max length.
- Numeric range.
- Decimal handling.
- Date validity.
- Time validity.
- Timezone behavior.
- Email/phone formatting.
- Unicode/Arabic/non-Latin text.
- Leading/trailing whitespace.
- Duplicate values.
- Unsupported file formats.
- File-size limits.
- Paste behavior.
- Multiple rapid submissions.
- Disabled submit behavior.
- Server-side rejection.
- Error-message accuracy.
- Preservation of valid user input after an error.

A green frontend validation state does not prove backend acceptance logic is correct.

---

# 23. Data Persistence and Consistency Coverage

For important mutations, verify:

1. UI shows success only after the operation actually succeeds.
2. Refreshing the screen preserves correct data.
3. Re-login preserves correct data.
4. Data shown on another relevant screen matches.
5. Admin/staff view matches user view where appropriate.
6. API result matches persisted state where observable.
7. Failed operations do not leave partial records.
8. Cancelled operations do not silently commit.
9. Deleted/archived records behave according to requirements.
10. Derived totals/counts update correctly.

---

# 24. Duplicate Action / Idempotency Coverage

For high-impact actions, test:

- Double-click.
- Double-tap.
- Rapid repeated submit.
- Browser refresh during submission.
- Back/forward navigation.
- Retry after timeout.
- Network disconnect immediately after submit.
- Reopening the same deep link.
- Duplicate webhook/event where controllable.

High-impact examples:

- Payment.
- Refund.
- Order creation.
- Booking.
- Subscription creation.
- Coupon redemption.
- Account deletion.
- Driver acceptance.
- Inventory decrement.
- Invitation.
- Message sending.

Expected result: one logical user action should not unexpectedly produce multiple irreversible side effects.

---

# 25. Concurrency Coverage

Where multiple actors can affect the same resource, define controlled tests for:

- Two users booking the last slot.
- Two staff members editing the same record.
- Two users claiming the same resource.
- User cancels while staff confirms.
- Payment completes while order is being cancelled.
- Inventory changes during checkout.
- Session/device A changes data while device B has stale state.

Document expected conflict-resolution behavior.

If expected behavior is not defined, mark **PRODUCT DECISION REQUIRED**, not PASS.

---

# 26. External Integration Failure Matrix

For each critical integration, test or document:

| Failure condition | Expected user behavior | Expected system behavior | Retry? | Data consistency requirement | Tested? |
|---|---|---|---|---|---|
| Provider 4xx | `{}` | `{}` | `{}` | `{}` | `{}` |
| Provider 5xx | `{}` | `{}` | `{}` | `{}` | `{}` |
| Timeout | `{}` | `{}` | `{}` | `{}` | `{}` |
| Network unavailable | `{}` | `{}` | `{}` | `{}` | `{}` |
| Invalid response | `{}` | `{}` | `{}` | `{}` | `{}` |
| Delayed webhook/callback | `{}` | `{}` | `{}` | `{}` | `{}` |
| Duplicate webhook/callback | `{}` | `{}` | `{}` | `{}` | `{}` |

Never intentionally disrupt a live provider without authorization.

---

# 27. Navigation and Lifecycle Coverage

Verify relevant items:

- Direct URL/deep link.
- Refresh.
- Browser back.
- Browser forward.
- Opening in new tab.
- App foreground/background.
- App termination/relaunch.
- Session restore.
- Token/session expiry.
- Logout.
- Login as another user.
- Multiple tabs/windows.
- Protected route behavior.
- Unsaved-change behavior.
- Notification/deep-link destination.
- Invalid/expired resource links.

---

# 28. Cross-Platform Coverage

Define the officially supported matrix before testing.

| Platform | Version | Device/browser | Required? | Result |
|---|---|---|---|---|
| `{Web/iOS/Android/etc.}` | `{VERSION}` | `{TARGET}` | `{YES/NO}` | `{PASS/FAIL/NOT TESTED}` |

Do not claim "cross-platform ready" if only one environment was tested.

---

# 29. Verification Design Exit Gate

Phase 2A passes only when:

- [ ] Every P0/P1 critical journey has executable tests.
- [ ] Expected outcomes are explicit.
- [ ] Required roles/test accounts are available or listed as blockers.
- [ ] Test data and cleanup approach are defined.
- [ ] External side effects are controlled.
- [ ] Boundary cases are included for critical business rules.
- [ ] Failure/recovery cases exist for critical integrations.
- [ ] Duplicate-action behavior is covered for irreversible actions.
- [ ] Concurrency cases are included where shared resources exist.
- [ ] Supported platforms are defined.
- [ ] No critical test relies on undefined product behavior.

---

# PHASE 2B — CONTROLLED EXECUTION

## 30. Objective

Execute the approved test plan and produce runtime evidence.

### Mandatory restrictions

- Prefer Staging or an equivalent controlled environment.
- Never use real customer credentials.
- Never expose secrets in logs/reports.
- Never perform real charges unless a dedicated sandbox/test method is explicitly approved.
- Never send messages to real customers.
- Never test destructive behavior against live production unless explicitly authorized.
- Clearly label all generated QA data.
- Document cleanup.

---

# 31. Execution Order

Recommended order:

1. Smoke test.
2. Authentication/session.
3. Core role behavior.
4. Critical journeys.
5. Business rules.
6. Data persistence.
7. State transitions.
8. Validation/boundaries.
9. Integrations.
10. Failure/recovery.
11. Duplicate/concurrency.
12. Cross-platform.
13. Regression rerun of affected critical journeys.

Stop and escalate if testing itself risks damaging live data or causing uncontrolled external side effects.

---

# 32. Smoke Test Gate

Before full execution, verify:

- [ ] Application starts/loads.
- [ ] Required backend services respond.
- [ ] Test users can authenticate where applicable.
- [ ] Primary navigation renders.
- [ ] Test database/environment is correct.
- [ ] No production credentials/data are accidentally being used.
- [ ] Test payment/integration mode is confirmed where applicable.

If smoke testing fails, record the blocker and do not pretend the deeper suite executed.

---

# 33. Runtime Evidence Requirements

For every P0/P1 test:

Include at least one appropriate evidence source:

- Screenshot.
- Screen recording reference.
- API request/response summary with secrets removed.
- Database before/after state.
- Application log reference.
- Automated test result.
- Event/webhook trace.
- Device/browser details.

Evidence must be sufficient for another reviewer to understand why the test was marked PASS or FAIL.

---

# 34. Failure Record

Every FAIL must create a defect entry:

| Defect ID | Test ID | Severity | Summary | Expected | Actual | Reproduction | Scope | Workaround | Evidence | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| `FQ-001` | `{TEST}` | `{P0-P4}` | `{SUMMARY}` | `{EXPECTED}` | `{ACTUAL}` | `{STEPS}` | `{ROLES/FEATURE}` | `{YES/NO}` | `{REF}` | `OPEN` |

### Root-cause status

Use one:

- Unknown.
- Likely frontend.
- Likely backend.
- Likely data/schema.
- Likely integration.
- Likely configuration.
- Likely race condition.
- Likely product-spec ambiguity.
- Confirmed root cause.

Do not claim a root cause without evidence.

---

# 35. Test Summary

Report:

| Metric | Count |
|---|---:|
| Total tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| BLOCKED | `{}` |
| NOT APPLICABLE | `{}` |
| Critical journeys PASS | `{}` |
| Critical journeys FAIL | `{}` |
| P0 defects | `{}` |
| P1 defects | `{}` |
| P2 defects | `{}` |
| P3 defects | `{}` |

Also calculate:

**Execution completeness**

`Executed tests / Applicable planned tests × 100`

**Critical journey pass rate**

`Passing critical journeys / Executed critical journeys × 100`

Do not use a high overall percentage to hide a failed critical journey.

---

# 36. Controlled Execution Exit Gate

Phase 2B passes only when:

- [ ] All executable P0/P1 tests were run.
- [ ] All critical journeys were executed or explicitly marked BLOCKED/INCONCLUSIVE.
- [ ] Every FAIL has a defect ID.
- [ ] Every P0/P1 result includes reproducible evidence.
- [ ] Test-data cleanup status is documented.
- [ ] No test result is inferred from code alone when runtime execution was required.
- [ ] Remaining unknowns are visible to the launch decision.

---

# PHASE 3 — REMEDIATION DESIGN

## 37. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** It requires technical review and a separate execution decision. Nothing below should be described as already fixed unless implementation and retesting have actually occurred.

---

# 38. Objective

Design fixes for confirmed functional defects while preventing regressions.

Fix root causes, not only visible symptoms.

---

# 39. Defect-to-Root-Cause Map

| Defect | Test(s) affected | Root cause | Confidence | Related defects | Proposed remediation phase |
|---|---|---|---|---|---|
| `FQ-001` | `{IDs}` | `{CAUSE}` | `{SYMBOL}` | `{IDs}` | `R1` |

Group related defects when one root cause creates several symptoms.

---

# 40. Remediation Phase Structure

Each remediation phase must include:

| # | Action | Defect(s) closed | Files/modules | Data/schema change | UI impact | Integration impact | Risks | Rollback | Regression tests |
|---|---|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{TEST IDs}` |

Do not execute remediation as part of this audit unless the owner separately authorizes implementation.

---

# 41. Regression Test Requirements

Every functional fix must map back to:

1. The original failing test.
2. At least one negative/edge test if relevant.
3. Any adjacent critical journey that could regress.
4. Any affected role.
5. Any affected platform.

A defect is **not closed** because code changed.

A defect becomes **Verified Closed** only after the relevant tests pass in an approved runtime environment.

---

# 42. Remediation Exit Gate

A remediation phase may be considered implementation-ready only when:

- [ ] Root cause is identified or uncertainty is explicitly recorded.
- [ ] Proposed changes are scoped.
- [ ] Data migration impact is understood.
- [ ] Backward compatibility is considered.
- [ ] Rollback exists where necessary.
- [ ] Regression tests are defined.
- [ ] Dependencies between fixes are documented.
- [ ] Product decisions required are separated from engineering fixes.

---

# FINAL — PRODUCTION READINESS REPORT

## 43. Objective

Produce one decision document for the release owner.

The final report must distinguish:

- What was inspected.
- What was executed.
- What passed.
- What failed.
- What remains unknown.
- What was outside scope.
- What has been fixed.
- What has merely been proposed.
- Whether the release is functionally safe to launch.

---

# 44. Executive Summary

Use this structure:

### System
`{SYSTEM_NAME}`

### Version
`{VERSION_OR_COMMIT}`

### Audit coverage
`{PERCENTAGE + IMPORTANT LIMITATIONS}`

### Critical journeys
`{PASS}/{TOTAL_EXECUTED}`

### Open defects
- P0: `{COUNT}`
- P1: `{COUNT}`
- P2: `{COUNT}`
- P3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final functional recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 45. Launch Decision Rules

## 🟢 GO

Use **GO** only when all of the following are true:

- Zero open P0 defects.
- Zero open P1 defects.
- 100% of defined critical user journeys pass.
- No critical journey remains INCONCLUSIVE or BLOCKED.
- Critical business rules have runtime evidence.
- Critical irreversible actions have duplicate/retry behavior verified where relevant.
- Critical shared-resource concurrency behavior has been verified where relevant.
- Critical integration success/failure behavior has been verified where relevant.
- No unresolved defect can cause data corruption, incorrect financial outcome, or unrecoverable user state.
- Any remaining P2/P3 items have documented ownership and do not undermine the core product promise.

## 🟡 CONDITIONAL GO

Use **CONDITIONAL GO** only when:

- Zero P0 defects.
- Zero P1 defects affecting a critical journey.
- All core journeys still complete successfully.
- Remaining issues are genuinely non-critical.
- Workarounds are safe and documented where needed.
- Release owner explicitly accepts the remaining P2 risks.
- No unknown critical behavior remains.

Do **not** use CONDITIONAL GO to soften an unresolved launch blocker.

## 🔴 NO-GO

Use **NO-GO** if any of the following is true:

- Any P0 defect remains open.
- Any P1 defect blocks or materially corrupts a critical journey.
- A critical financial/business rule is wrong or unverified.
- A critical journey is BLOCKED or INCONCLUSIVE.
- Data can become inconsistent or irrecoverable during a core action.
- Duplicate/retry behavior can create multiple irreversible transactions.
- A critical external integration has no safe failure behavior.
- Test coverage is too incomplete to support a production claim.

---

# 46. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-FQ-01` | All critical journeys pass | `{TEST IDs}` | `{PASS/FAIL}` |
| `LG-FQ-02` | Zero open P0 | `{DEFECT REGISTER}` | `{PASS/FAIL}` |
| `LG-FQ-03` | Zero launch-blocking P1 | `{DEFECT REGISTER}` | `{PASS/FAIL}` |
| `LG-FQ-04` | Critical business rules verified | `{BR TEST IDs}` | `{PASS/FAIL}` |
| `LG-FQ-05` | Critical persistence/state behavior verified | `{DATA/STATE TEST IDs}` | `{PASS/FAIL}` |
| `LG-FQ-06` | Critical integrations verified | `{INT TEST IDs}` | `{PASS/FAIL}` |
| `LG-FQ-07` | Duplicate/retry safety verified where applicable | `{DUP TEST IDs}` | `{PASS/FAIL}` |
| `LG-FQ-08` | Concurrency verified where applicable | `{CONC TEST IDs}` | `{PASS/FAIL}` |
| `LG-FQ-09` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |
| `LG-FQ-10` | Required supported platforms tested | `{PLATFORM MATRIX}` | `{PASS/FAIL}` |

If any mandatory gate is FAIL, the functional audit cannot issue GO.

---

# 47. Open Risk Register

| Risk ID | Defect/test | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-FQ-001` | `{REF}` | `{P0-P4}` | `{LOW/MED/HIGH}` | `{IMPACT}` | `{ACTION}` | `{OWNER}` | `{YES/NO}` |

---

# 48. Out-of-Scope / Not Verified

Explicitly list:

- Platforms not tested.
- Roles not tested.
- Integrations not accessible.
- External dashboards not accessible.
- Devices not available.
- Production-only behavior not exercised.
- Features hidden behind unavailable flags.
- Business rules with no authoritative specification.
- Tests blocked by missing credentials/accounts.
- Areas inspected only statically.
- Anything intentionally excluded by the owner.

Do not convert lack of access into either PASS or FAIL.

---

# 49. Final One-Sentence Recommendation

Use one unambiguous sentence:

**Example GO**

> Functional QA recommendation: **GO for production** for version `{VERSION}` because all critical journeys and functional launch gates passed, with only the documented non-blocking residual risks remaining.

**Example CONDITIONAL GO**

> Functional QA recommendation: **CONDITIONAL GO** for version `{VERSION}`, subject to explicit acceptance of the documented non-critical residual risks; no critical functional blocker remains.

**Example NO-GO**

> Functional QA recommendation: **NO-GO** for version `{VERSION}` until launch blockers `{FQ-xxx...}` are remediated and the associated regression tests pass.

---

# 50. AI-Agent-Specific Verification Rules

This section is mandatory when the application was built partly or primarily by AI coding agents.

The auditor must actively look for **false completeness**, including:

- UI that appears finished but has no working handler.
- Buttons that do nothing.
- Temporary `alert()` / console-only feedback.
- Hardcoded sample data.
- Mock APIs still active.
- Demo accounts or bypasses.
- Placeholder responses.
- TODO/FIXME markers on production paths.
- Functions returning unconditional success.
- Silent exception handling.
- Empty `catch` blocks.
- Catch-and-ignore behavior.
- Duplicate components/services implementing the same feature differently.
- Old code paths still reachable.
- Frontend assumptions not enforced by backend logic.
- Backend behavior not represented correctly in the frontend.
- Database fields the UI never persists.
- UI fields the backend ignores.
- Routes that compile but fail when opened directly.
- Environment variables that exist locally but not in production configuration.
- Test-only feature flags enabled.
- Fake loading delays.
- Optimistic success that is not rolled back after backend failure.
- Generated types/models that no longer match API/database schemas.
- Stale imports and partially completed refactors.
- Multiple competing sources of truth.
- Code added by a previous agent session but never connected to execution paths.

For each suspected instance:

1. Trace the real execution path.
2. Determine whether the code is reachable.
3. Determine whether it connects to the intended data/service.
4. Execute a controlled runtime test if the behavior is important.
5. Record evidence.
6. Never mark complete based on naming, comments, or visual appearance alone.

---

# 51. Required Deliverables

A complete Functional QA Audit should produce:

1. `01_FUNCTIONAL_DISCOVERY_REPORT.md`
2. `02_FUNCTIONAL_TEST_PLAN.md`
3. `03_FUNCTIONAL_TEST_EXECUTION_REPORT.md`
4. `04_FUNCTIONAL_REMEDIATION_PLAN.md`
5. `05_FUNCTIONAL_PRODUCTION_READINESS_REPORT.md`

Optional evidence directory:

`/qa-evidence/{VERSION_OR_DATE}/`

Do not include credentials, secrets, personal user data, or unrestricted production exports in evidence.

---

# 52. Instructions to the AI Auditor

When this file is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not collapse the phases into one vague review.
3. Do not modify application code during Discovery or Test Planning.
4. Do not claim runtime verification unless a runtime test was actually executed.
5. Do not use destructive production actions without explicit authorization.
6. Do not reveal secrets.
7. Preserve stable feature, business-rule, test, defect, risk, and launch-gate IDs.
8. Cite exact file paths/components/endpoints when making code-derived claims.
9. Record what was not reviewed as carefully as what was reviewed.
10. Separate product ambiguity from engineering defects.
11. Do not invent requirements.
12. Do not silently fix defects while auditing unless implementation is separately authorized.
13. If implementation is authorized later, retest before changing defect status to Verified Closed.
14. Treat any unverified critical journey as an open launch-gate issue.
15. End with exactly one functional production recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 53. Completion Standard

This audit is complete only when a technically independent reviewer could answer:

- What does the application do?
- Who uses it?
- What are its critical journeys?
- What exact behavior was tested?
- What environment was used?
- What passed?
- What failed?
- What remains unknown?
- What evidence supports each critical conclusion?
- What needs fixing?
- What fixes are only proposed versus actually verified?
- What areas were outside scope?
- Can this exact version be launched from a **functional** standpoint?

If those questions cannot be answered from the audit outputs, the audit is not complete.
