# API & Backend Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that an application's API and backend layer are correct, consistent, resilient, observable, and safe to expose before launch.
>
> This template is designed for systems built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark backend/API behavior PASS because endpoints exist, routes compile, or frontend flows appear to work. Critical contracts and server-side guarantees must be proven through code evidence and controlled execution whenever possible.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current API/backend layer is production-ready by verifying:

- Every critical endpoint has a clear contract.
- Authentication and authorization are enforced server-side.
- Validation occurs at the correct boundary.
- Status codes and error responses are consistent.
- Business rules are not trusted to the client.
- Idempotency exists for retryable high-impact operations.
- Webhooks and callbacks are verified and duplicate-safe.
- Retries, timeouts, and partial failures are handled intentionally.
- Pagination, filtering, sorting, and limits are bounded.
- External API integrations fail safely.
- Backend operations are transactionally consistent where required.
- Versioning and backward compatibility are considered.
- API schema and frontend/client assumptions are aligned.
- Background jobs and async workflows have explicit ownership.
- APIs do not silently return success after backend failure.
- Logs and errors are sufficient to debug backend incidents.
- AI-generated endpoints are not duplicated, disconnected, mocked, or inconsistent.
- Production configuration does not expose test/debug behavior.

## 0.2 Non-goals

This audit does **not** replace:

- Security audit.
- Functional QA.
- Code quality audit.
- Database/data-integrity audit.
- Performance/load testing.
- Privacy/legal review.
- DevOps/infrastructure review.

If obvious findings from those disciplines appear, record them and cross-reference the specialist audit.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Understand routes, services, controllers, jobs, integrations, contracts, auth, validation, and backend data flow | Backend/API map |
| 2A | **Static Verification** | Review implementation against explicit backend/API quality rules | Contract & control evidence matrix |
| 2B | **Controlled Validation** | Execute safe API/backend tests on an approved environment | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design root-cause fixes — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence and issue launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**Frontend success is not proof of backend correctness.**

A backend/API requirement is not considered verified merely because one UI path appears to work.

---

# 2. Report Header

Use this header in every phase report:

| Field | Value |
|---|---|
| System | `{SYSTEM_NAME}` |
| Repository | `{REPOSITORY_NAME}` |
| Branch | `{BRANCH}` |
| Commit / Version | `{COMMIT_OR_VERSION}` |
| Backend framework | `{FRAMEWORK}` |
| API style | `{REST / GraphQL / RPC / WebSocket / Mixed}` |
| Phase | `{PHASE_NAME}` |
| Audit date | `{DATE}` |
| Environment | `{Local / Dev / Staging / Production}` |
| Environment status | `{🧪 Controlled / 🔴 Live production}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Runtime Test** | Proven by controlled request/response or backend execution |
| 🟧 **Confirmed by Code** | Proven from exact route/controller/service/schema implementation |
| 🟨 **Likely** | Strong inference with incomplete direct evidence |
| 🟦 **Requires Controlled Test** | Must be executed before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was disproven |

For every important finding, include:

- Finding ID.
- Endpoint/job/integration.
- Role/actor.
- Request shape.
- Expected behavior.
- Actual behavior.
- Evidence.
- Severity.
- Launch-blocker status.
- Confidence.

---

# 4. Severity Model

| Level | Classification | Backend/API meaning | Launch treatment |
|---|---|---|---|
| **AB0** | Critical | Can cause data corruption, financial duplication, privilege breach, catastrophic inconsistency, or total critical API failure | **Mandatory NO-GO** |
| **AB1** | High | Core endpoint or backend workflow is incorrect, unsafe, inconsistent, or materially unreliable | **Pre-launch blocker** |
| **AB2** | Medium | Important issue with bounded impact and safe workaround | Explicit acceptance required |
| **AB3** | Low | Minor contract/consistency issue | Backlog acceptable |
| **AB4** | Observation | Improvement opportunity | Backlog |

## 4.1 Severity factors

Evaluate:

- Endpoint criticality.
- Financial/data impact.
- Auth scope.
- Retry exposure.
- External dependency exposure.
- Concurrency exposure.
- Recoverability.
- Blast radius.
- Client compatibility.
- Frequency.
- Debuggability.
- Whether issue is silent.

---

# 5. Environment Warning

When testing outside production:

| Dimension | Evaluation |
|---|---|
| Technical severity | Based on defect itself |
| Current actual impact | Based on current environment |
| Production impact | State likely impact under real traffic/users |
| Procedural classification | Unresolved AB0/AB1 issues are **Pre-Launch Blockers** |

Do not execute destructive live API calls, real payments, real messaging, mass writes, or production data mutations without explicit authorization.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Understand the backend and API surface before judging it.

### Mandatory restrictions

During discovery:

- Prefer read-only review.
- Do not mutate production state.
- Do not replay live webhooks.
- Do not invoke real payment/refund endpoints.
- Do not rotate secrets.
- Do not alter API gateway rules.
- Do not deploy.
- Do not auto-refactor.

---

# 7. Backend Architecture Inventory

Document:

- Backend framework.
- Runtime.
- API style.
- Controller/route layer.
- Service/application layer.
- Domain layer.
- Persistence layer.
- Background jobs.
- Queues.
- Webhooks.
- Scheduled tasks.
- External integrations.
- Realtime channels.
- File processing.
- Email/SMS/push dispatch.
- Admin/backend-only interfaces.

| Component | Purpose | Entry point | Dependencies | Criticality | Evidence |
|---|---|---|---|---|---|
| `{COMPONENT}` | `{PURPOSE}` | `{PATH}` | `{}` | `{}` | `{}` |

---

# 8. Endpoint Inventory

Create a complete endpoint inventory.

| API ID | Method | Route / Operation | Purpose | Auth required? | Roles | Request model | Response model | Criticality |
|---|---|---|---|---|---|---|---|---|
| `API-001` | `{GET/POST/...}` | `{ROUTE}` | `{PURPOSE}` | `{YES/NO}` | `{ROLES}` | `{SCHEMA}` | `{SCHEMA}` | `{}` |

Include:

- Public endpoints.
- Authenticated endpoints.
- Admin endpoints.
- Internal endpoints.
- Webhooks.
- Health endpoints.
- Debug/test endpoints.
- Legacy/v1/v2 endpoints.
- Realtime events where applicable.

Flag:

- Unused endpoints.
- Undocumented endpoints.
- Duplicate endpoints for same responsibility.
- Old and new endpoints both active.
- Debug endpoints reachable in production.
- Endpoints with unclear ownership.

---

# 9. Authentication Map

Document:

- Session/JWT/API key/OAuth/etc.
- Token validation.
- Token expiry.
- Refresh mechanism.
- Backend session lookup.
- Service-to-service auth.
- Webhook auth.
- Admin auth.

| Actor | Auth mechanism | Token/session source | Backend validation | Expiry | Revocation | Evidence |
|---|---|---|---|---|---|---|
| `{ACTOR}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 10. Authorization Map

For each critical endpoint:

| API ID | Role(s) allowed | Resource ownership check? | Admin override? | Server enforced? | Evidence |
|---|---|---|---|---|---|
| `{API}` | `{ROLES}` | `{YES/NO}` | `{YES/NO}` | `{YES/NO}` | `{PATH}` |

Critical rule:

**Hidden UI is not authorization.**

Any endpoint relying only on frontend visibility must be flagged.

---

# 11. Request Validation Inventory

Document:

- Path params.
- Query params.
- Headers.
- Body fields.
- File uploads.
- Content type.
- Enum handling.
- Numeric limits.
- Date/time format.
- Pagination bounds.
- String lengths.
- Unknown fields.
- Nested objects.

| API ID | Validation layer | Schema | Rejects unknown fields? | Server-side? | Notes |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 12. Response Contract Inventory

For each critical endpoint, document:

- Success code.
- Error codes.
- Response schema.
- Null behavior.
- Empty collection behavior.
- Pagination shape.
- Metadata.
- Date/time format.
- Error envelope.

Flag inconsistent shapes.

---

# 13. Status Code Inventory

Review use of:

- 200
- 201
- 202
- 204
- 400
- 401
- 403
- 404
- 409
- 422
- 429
- 5xx

Flag:

- 200 on failed operation.
- 500 for expected validation errors.
- 401 vs 403 confusion where it matters.
- 404 used to hide all authorization behavior inconsistently.
- 204 with response body.
- 201 without created resource reference where expected.

---

# 14. Error Contract Inventory

Document:

| Error category | HTTP/status behavior | Response shape | Internal logging | User-safe? | Retryable? |
|---|---|---|---|---|---|
| `{VALIDATION}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Flag:

- Raw stack traces.
- DB errors sent directly.
- Inconsistent error envelopes.
- Generic `"Something went wrong"` for all operational classes.
- Success envelope carrying error text.
- Internal details leaked.

---

# 15. Business Rule Enforcement Map

For every critical business rule:

| Rule ID | Rule | Endpoint(s) | Server enforced? | Client also enforces? | Source of truth |
|---|---|---|---|---|---|
| `BR-001` | `{RULE}` | `{API}` | `{YES/NO}` | `{YES/NO}` | `{}` |

Flag client-only enforcement.

---

# 16. External Integration Inventory

| Integration ID | Service | Purpose | Auth | Timeout | Retry | Idempotency | Failure handling | Sandbox? |
|---|---|---|---|---|---|---|---|---|
| `INT-001` | `{SERVICE}` | `{PURPOSE}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Examples:

- Payment.
- Maps.
- Email.
- SMS.
- Push.
- POS.
- ERP.
- CRM.
- AI provider.
- Identity provider.
- Storage.
- Geocoding.
- Tax service.

---

# 17. Webhook Inventory

| Webhook ID | Provider | Endpoint | Signature verification | Event ID | Duplicate-safe? | Ordering assumption | Retry handling |
|---|---|---|---|---|---|---|---|
| `WH-001` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Flag:

- No signature verification.
- No event ID persistence.
- Duplicate processing.
- Assuming one delivery.
- Assuming ordered delivery.
- Returning 200 before durable processing without strategy.
- Returning 500 after successful side effect, causing duplicate retry.

---

# 18. Background Job Inventory

| Job ID | Trigger | Purpose | Queue/runner | Retry | Idempotent? | Dead-letter handling | Criticality |
|---|---|---|---|---|---|---|---|
| `JOB-001` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Include:

- Cron.
- Workers.
- Queue jobs.
- Scheduled cleanup.
- Delayed notifications.
- Payment reconciliation.
- Data sync.

---

# 19. API Versioning Inventory

Document:

- URL versioning.
- Header versioning.
- Schema evolution.
- Deprecation.
- Legacy clients.
- Mobile app compatibility.
- Web client compatibility.

Flag breaking changes without compatibility strategy.

---

# 20. Pagination / Filtering / Sorting Inventory

For list endpoints, verify:

- Page size limit.
- Max page size.
- Cursor vs offset.
- Stable ordering.
- Sort field allowlist.
- Filter allowlist.
- Default sort.
- Empty results.
- Invalid cursor/page behavior.

Unbounded list endpoints should be flagged.

---

# 21. File Upload / Download Inventory

Where applicable:

- Upload route.
- Content type validation.
- Size limit.
- Storage.
- Processing.
- Virus/malware handling cross-reference to Security.
- Signed URLs.
- Expiry.
- Authorization.
- Download ownership.

---

# 22. Discovery Execution Log

### Fully reviewed
`{ROUTES / CONTROLLERS / SERVICES / SCHEMAS / JOBS}`

### Partially reviewed
`{AREAS}`

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

# 23. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Backend architecture is mapped.
- [ ] Critical endpoints are inventoried.
- [ ] Authentication is mapped.
- [ ] Authorization is mapped.
- [ ] Request validation is understood.
- [ ] Response/error contracts are understood.
- [ ] Critical business rules are mapped.
- [ ] External integrations are mapped.
- [ ] Webhooks/jobs are mapped.
- [ ] Versioning and pagination are understood.
- [ ] Unknown/unreviewed areas are explicitly listed.

---

# PHASE 2A — STATIC VERIFICATION

# 24. Objective

Evaluate backend/API implementation against explicit production rules.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `AUTHN-xx` | Authentication |
| `AUTHZ-xx` | Authorization |
| `VAL-xx` | Validation |
| `RESP-xx` | Response contract |
| `HTTP-xx` | Status codes |
| `ERR-xx` | Error handling |
| `BR-xx` | Business rules |
| `IDEM-xx` | Idempotency |
| `WH-xx` | Webhooks |
| `JOB-xx` | Background jobs |
| `EXT-xx` | External integrations |
| `TIMEOUT-xx` | Timeout |
| `RETRY-xx` | Retry |
| `PAG-xx` | Pagination |
| `VER-xx` | Versioning |
| `FILE-xx` | File API |
| `RATE-xx` | Rate/usage limits |
| `CACHE-xx` | Backend caching correctness |
| `ASYNC-xx` | Async ownership |
| `CONTRACT-xx` | Client/server contract drift |
| `AI-xx` | AI-agent-specific backend defects |

---

# 25. Authentication Verification

Verify:

- Token/session is validated.
- Expired token rejected.
- Revoked/deactivated user handling.
- Missing auth rejected.
- Malformed auth rejected.
- Service tokens scoped correctly.
- Backend does not trust user ID from body when identity exists in auth context.

---

# 26. Authorization Verification

For every critical endpoint:

- Role check.
- Resource ownership check.
- Tenant/organization boundary where applicable.
- Admin-only behavior.
- Server-side enforcement.
- Object-level authorization.

Flag:

- `user_id` accepted from request and trusted.
- Ownership inferred only from frontend.
- Admin route guarded only by UI.
- Generic auth check without object permission.

---

# 27. Validation Verification

Inspect:

- Required fields.
- Types.
- Ranges.
- enums.
- date formats.
- max lengths.
- arrays.
- nested structures.
- unknown fields.
- file metadata.
- pagination.

Flag:

- accepting arbitrary JSON into persistence model.
- ORM/model mass assignment without allowlist.
- inconsistent validation across create/update.
- update route allowing immutable field change.

---

# 28. Response Contract Verification

Check consistency of:

- JSON shape.
- field naming.
- null behavior.
- list shape.
- metadata.
- timestamps.
- IDs.
- numeric formatting.
- pagination.
- error envelope.

Frontend parsing assumptions must match.

---

# 29. HTTP Semantics Verification

Review:

- Method correctness.
- Idempotent method behavior.
- safe GET behavior.
- POST vs PUT/PATCH semantics.
- delete semantics.
- cacheability implications.
- 201/202/204 correctness.

Flag state-changing GET endpoints.

---

# 30. Error Handling Verification

For critical routes:

1. What can fail?
2. Where is failure caught?
3. What HTTP code is returned?
4. Is partial state possible?
5. Is error logged?
6. Is retry safe?
7. Is client given enough information to respond correctly?

Flag success-after-failure.

---

# 31. Idempotency Verification

For high-impact POST/callback operations:

- Payment.
- Refund.
- Order creation.
- Booking.
- Subscription.
- Coupon redemption.
- External callbacks.

Verify:

- idempotency key or stable event ID.
- persistence of processed key.
- duplicate response behavior.
- transaction safety.
- expiry policy if relevant.

---

# 32. Webhook Verification

Verify:

- Signature/authentication.
- Timestamp/replay protection where provider supports it.
- Event type allowlist.
- Event ID uniqueness.
- Duplicate-safe processing.
- Unknown event behavior.
- Retry semantics.
- Ordering assumptions.
- durable processing.
- post-processing errors.

Cross-reference Security Audit for cryptographic verification specifics.

---

# 33. Retry Verification

Inspect whether retries are:

- bounded.
- only used for retryable failures.
- jittered/backed off where appropriate.
- safe for idempotent operations.
- not applied to validation/4xx errors blindly.
- observable.

Flag infinite retry loops.

---

# 34. Timeout Verification

Every external network call should have intentional timeout behavior.

Inspect:

- connection timeout.
- request timeout.
- total timeout.
- user-facing timeout behavior.
- worker timeout.
- cleanup/cancellation.

Flag no-timeout calls on critical paths.

---

# 35. External Failure Verification

For each integration:

| Failure | Expected backend behavior | Expected client behavior | Retry? | Data consistency |
|---|---|---|---|---|
| 4xx | `{}` | `{}` | `{}` | `{}` |
| 5xx | `{}` | `{}` | `{}` | `{}` |
| Timeout | `{}` | `{}` | `{}` | `{}` |
| Invalid payload | `{}` | `{}` | `{}` | `{}` |
| Delayed callback | `{}` | `{}` | `{}` | `{}` |
| Duplicate callback | `{}` | `{}` | `{}` | `{}` |

---

# 36. Business Rule Verification

For each critical `BR-xxx`:

Verify:

- server-side enforcement.
- exact calculation.
- boundary values.
- role-specific behavior.
- state-specific behavior.
- no client override.
- consistent use across endpoints.

Flag rule duplication across controllers/services.

---

# 37. Pagination Verification

Inspect:

- enforced maximum size.
- stable order.
- duplicate/missing item risk between pages.
- invalid page/cursor behavior.
- expensive unrestricted filters.
- total-count behavior.
- cursor integrity.

---

# 38. Filtering / Sorting Verification

Verify:

- allowlisted fields.
- validated direction.
- no arbitrary raw query fragments.
- default ordering.
- case sensitivity expectations.
- null sorting behavior.

---

# 39. Versioning / Backward Compatibility Verification

For breaking changes:

- old fields still accepted where needed.
- clients can transition.
- response fields not silently renamed.
- mobile versions considered.
- migration window documented.
- deprecation strategy exists.

---

# 40. Async / Background Ownership Verification

Inspect:

- who owns job lifecycle.
- retries.
- poison messages.
- dead-letter queue.
- duplicate delivery.
- job visibility timeout.
- cancellation.
- timeout.
- idempotency.
- monitoring.

---

# 41. Cache Correctness Verification

Where backend caching exists:

- key ownership.
- tenant/user isolation.
- invalidation.
- stale-data tolerance.
- TTL.
- write-through/write-behind behavior.
- cache stampede considerations.
- permission-sensitive data.

Security/privacy implications should be cross-referenced.

---

# 42. AI-Agent-Specific Backend Audit

Mandatory when AI agents were used.

Actively search for:

## 42.1 Duplicate routes

- Same path in multiple files.
- v1/v2 implementations both active unexpectedly.
- old handler not removed.
- two controllers for same resource.

## 42.2 False completeness

- Route defined but not registered.
- Controller exists but service is stubbed.
- Service returns mock response.
- Endpoint always returns success.
- frontend calls outdated endpoint.
- response schema differs from actual return.

## 42.3 Hallucinated framework/library behavior

- middleware option does not exist.
- route guard assumes unsupported behavior.
- SDK method not available in installed version.
- fake decorator/annotation.
- unsupported transaction option.
- incorrect webhook verification method.

## 42.4 Contract drift

- frontend sends old field.
- backend renamed field.
- enum mismatch.
- nullable mismatch.
- list vs object mismatch.
- date format mismatch.
- generated API client stale.

## 42.5 Patch layering

- repeated `if` patches instead of fixing root cause.
- duplicated validation.
- route-specific exceptions.
- special-case bypasses.
- fallback logic masking errors.

## 42.6 Hidden test/demo behavior

- hardcoded test account.
- dev-only bypass in route.
- `if NODE_ENV !== production` logic inverted.
- mock provider accidentally active.
- fake success response.

## 42.7 Unsafe mass-assignment

- request body spread directly into model/database.
- entire DTO passed to update.
- client can mutate server-owned fields.

---

# 43. Static Verification Matrix

| Check ID | Category | API/Job | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 44. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Critical auth/authz reviewed.
- [ ] Validation reviewed.
- [ ] Response/error contracts reviewed.
- [ ] HTTP semantics reviewed.
- [ ] Critical business rules reviewed.
- [ ] Idempotency reviewed.
- [ ] Webhooks reviewed.
- [ ] Retries/timeouts reviewed.
- [ ] External failure handling reviewed.
- [ ] Pagination/versioning reviewed.
- [ ] AI-generated backend risks reviewed.
- [ ] All AB0/AB1 candidates have evidence.

---

# PHASE 2B — CONTROLLED VALIDATION

# 45. Objective

Prove backend/API behavior in an approved environment.

### Mandatory restrictions

- Prefer local/test/staging.
- Use synthetic data.
- Do not charge real cards.
- Do not send real customer messages.
- Do not replay production webhooks.
- Do not expose secrets.
- Do not perform destructive live writes.
- Document cleanup.

---

# 46. API Test Categories

| Prefix | Category |
|---|---|
| `API-AUTHN-xx` | Authentication |
| `API-AUTHZ-xx` | Authorization |
| `API-VAL-xx` | Validation |
| `API-RESP-xx` | Response |
| `API-ERR-xx` | Error behavior |
| `API-BR-xx` | Business rules |
| `API-IDEM-xx` | Idempotency |
| `API-WH-xx` | Webhooks |
| `API-EXT-xx` | External failure |
| `API-PAG-xx` | Pagination |
| `API-VER-xx` | Versioning |
| `API-JOB-xx` | Async jobs |
| `API-TIMEOUT-xx` | Timeout |
| `API-RETRY-xx` | Retry |

---

# 47. Controlled Test Matrix

| Test ID | API / Rule | Role | Preconditions | Request/action | Expected result | Actual result | Evidence | Result |
|---|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 48. Authentication Tests

Test relevant cases:

- valid token/session.
- missing token.
- expired token.
- malformed token.
- revoked/deactivated user.
- wrong auth scheme.
- service token misuse.

---

# 49. Authorization Tests

For critical resources:

- allowed role succeeds.
- disallowed role denied.
- user A cannot access user B's resource.
- admin access behaves as intended.
- ownership change edge cases.
- deleted/deactivated ownership behavior.

---

# 50. Validation Tests

For each critical endpoint:

- missing required field.
- invalid type.
- invalid enum.
- overlong string.
- out-of-range number.
- null.
- unknown field.
- malformed date.
- duplicate.
- immutable field update.
- invalid nested object.

Verify no invalid state persists.

---

# 51. Status / Error Tests

Verify actual codes and envelopes for:

- success.
- validation error.
- unauthenticated.
- unauthorized.
- not found.
- conflict.
- rate/limit error.
- provider failure.
- unexpected backend error.

---

# 52. Idempotency Tests

Repeat the same logical high-impact request.

Verify:

- one logical effect.
- no duplicate financial or persistent action.
- stable duplicate response.
- event/key storage.

---

# 53. Webhook Tests

Using provider sandbox or controlled fixtures:

- valid signature.
- invalid signature.
- duplicate event.
- unknown event.
- delayed event.
- out-of-order event where relevant.
- handler failure and retry.

---

# 54. Timeout / Retry Tests

Where safe:

- provider timeout.
- provider 500.
- provider 429.
- network failure.
- delayed callback.

Verify backend:

- does not hang indefinitely.
- retries only when safe.
- reports accurate client state.
- preserves data consistency.

---

# 55. Pagination Tests

Test:

- default size.
- max size.
- over-max request.
- invalid cursor/page.
- stable sort.
- no duplicate/missing records across controlled pages.

---

# 56. Version Compatibility Tests

Where multiple clients/versions exist:

- old request against new backend.
- old client response parsing.
- deprecated field behavior.
- new optional field behavior.
- enum expansion behavior.

---

# 57. Background Job Tests

Where safe:

- successful job.
- retryable failure.
- permanent failure.
- duplicate delivery.
- timeout.
- dead-letter/failed state.
- idempotent rerun.

---

# 58. Controlled Validation Summary

| Metric | Count |
|---|---:|
| Tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| BLOCKED | `{}` |
| AB0 findings | `{}` |
| AB1 findings | `{}` |
| AB2 findings | `{}` |

---

# 59. Controlled Validation Exit Gate

Phase 2B passes only when:

- [ ] Critical auth/authz tests executed.
- [ ] Critical validation tests executed.
- [ ] Critical business rules executed.
- [ ] Critical error contracts executed.
- [ ] Idempotency tested where applicable.
- [ ] Webhooks tested where applicable.
- [ ] External failure behavior tested where applicable.
- [ ] Pagination/versioning tested where applicable.
- [ ] Every FAIL has finding ID.
- [ ] No critical API is marked PASS based only on UI behavior.

---

# 60. Finding Register

| Finding ID | Category | Severity | API / Job | Summary | Evidence | Root-cause status | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `AB-001` | `{CATEGORY}` | `{AB0-AB4}` | `{API}` | `{SUMMARY}` | `{EVIDENCE}` | `{UNKNOWN/LIKELY/CONFIRMED}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 61. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** It requires technical review and a separate implementation decision. Nothing below should be described as fixed until code changes are completed and controlled validation is rerun.

---

# 62. Objective

Design fixes around root causes, not endpoint-by-endpoint patches.

Prefer:

- centralized validation,
- centralized auth middleware,
- explicit domain services,
- consistent error contracts,
- idempotent workflows,
- bounded retry,
- explicit timeout,
- clear API versioning,
- stable schemas.

---

# 63. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `AB-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 64. Remediation Principles

| Principle | Application |
|---|---|
| Server is authoritative | Never trust client enforcement for critical rules |
| Explicit contracts | Requests/responses are schema-defined |
| Fail accurately | Errors are not returned as success |
| Idempotent retries | Repeatable high-impact actions produce one logical effect |
| Bounded external calls | Timeouts and retry policy are explicit |
| Auth at resource boundary | Object-level checks where required |
| One error envelope | Clients can respond consistently |
| Compatibility before cleanup | Avoid breaking deployed clients |
| Test the contract | Retest actual requests after remediation |

---

# 65. Remediation Phase Table

| # | Action | Findings closed | Routes/services | Contract impact | DB impact | Client impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 66. Backward-Compatibility Requirements

For breaking API changes:

- [ ] Existing client versions identified.
- [ ] Compatibility window defined.
- [ ] Old field/route behavior documented.
- [ ] Deprecation plan exists.
- [ ] Migration sequencing defined.
- [ ] Client rollout sequencing defined.
- [ ] Rollback documented.
- [ ] Monitoring exists for old/new usage.

---

# 67. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root causes identified.
- [ ] Contract changes explicit.
- [ ] Client impact known.
- [ ] DB impact known.
- [ ] Retry/idempotency behavior defined.
- [ ] Rollback exists where needed.
- [ ] Regression tests defined.
- [ ] Security/data-integrity cross-references included.
- [ ] No unnecessary API rewrite proposed.

---

# FINAL — API & BACKEND PRODUCTION READINESS REPORT

# 68. Objective

Produce one release decision for the exact audited backend version.

---

# 69. Executive Summary

### System
`{SYSTEM_NAME}`

### Backend version / commit
`{VERSION}`

### API surface reviewed
`{SUMMARY + LIMITATIONS}`

### Critical endpoints tested
`{PASS}/{EXECUTED}`

### Open findings
- AB0: `{COUNT}`
- AB1: `{COUNT}`
- AB2: `{COUNT}`
- AB3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 70. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open AB0.
- Zero open AB1.
- Critical auth/authz verified.
- Critical validation server-side.
- Critical business rules server-enforced.
- Critical errors return accurate status/contracts.
- High-impact retries are idempotent.
- Critical webhooks duplicate-safe.
- External calls have safe timeout/failure behavior.
- No unbounded critical pagination.
- No critical frontend/backend contract drift.
- No production mock/test/debug endpoint behavior.
- No critical unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero AB0.
- Zero launch-blocking AB1.
- Core contracts and auth are verified.
- Remaining issues are bounded and non-critical.
- No financial/data-integrity uncertainty.
- Release owner accepts residual AB2 risks.

## 🔴 NO-GO

Use if any of the following is true:

- Any AB0 remains open.
- Critical endpoint lacks authorization.
- Critical rule is client-only.
- Backend returns success after critical failure.
- Duplicate payment/order/refund/etc. can occur.
- Webhook processing is not duplicate-safe.
- Critical external call can hang/fail without safe handling.
- Core API/client contracts materially disagree.
- Production exposes mock/debug/test behavior.
- Critical API behavior remains unknown.

---

# 71. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-AB-01` | Zero open AB0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-AB-02` | Zero launch-blocking AB1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-AB-03` | Critical auth/authz verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AB-04` | Critical validation server-side | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AB-05` | Critical business rules server-enforced | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AB-06` | Error/status contract verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AB-07` | Critical idempotency verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AB-08` | Webhook safety verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AB-09` | Timeout/retry behavior verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AB-10` | Pagination/versioning safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AB-11` | No critical client/server contract drift | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-AB-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 72. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-AB-001` | `{REF}` | `{AB}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 73. Out-of-Scope / Not Verified

Explicitly list:

- Endpoints not accessible.
- Admin APIs not tested.
- Production-only callbacks not executed.
- Third-party sandbox unavailable.
- Realtime/WebSocket behavior excluded.
- Legacy API version unavailable.
- Internal service unavailable.
- Background worker not runnable.
- Closed-source integration internals.
- Load/performance behavior.
- Anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 74. Final One-Sentence Recommendation

### GO example

> API & Backend recommendation: **GO for production** for `{VERSION}` because all mandatory backend launch gates passed and no unresolved critical contract, authorization, idempotency, integration, or failure-handling risk remains.

### CONDITIONAL GO example

> API & Backend recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented AB2 residual risks; all critical backend guarantees are verified.

### NO-GO example

> API & Backend recommendation: **NO-GO** for `{VERSION}` until findings `{AB-xxx...}` are remediated and the associated API, authorization, idempotency, integration, and regression tests pass.

---

# 75. Required Deliverables

A complete audit should produce:

1. `01_API_BACKEND_DISCOVERY_REPORT.md`
2. `02_API_BACKEND_STATIC_VERIFICATION_REPORT.md`
3. `03_API_BACKEND_TEST_EXECUTION_REPORT.md`
4. `04_API_BACKEND_REMEDIATION_PLAN.md`
5. `05_API_BACKEND_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `API_ENDPOINT_INVENTORY.md`
- `AUTHORIZATION_MATRIX.md`
- `ERROR_CONTRACT_MATRIX.md`
- `WEBHOOK_INVENTORY.md`
- `BACKGROUND_JOB_INVENTORY.md`
- `API_FINDINGS.csv`
- `CLIENT_SERVER_CONTRACT_DIFF.md`

---

# 76. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not modify backend code during Discovery or Verification.
3. Do not replay production webhooks.
4. Do not invoke real payment/refund endpoints without explicit authorization.
5. Do not expose credentials, tokens, secrets, or raw signed webhook payloads.
6. Cite exact route/controller/service/schema paths.
7. Do not assume UI restrictions equal backend authorization.
8. Do not assume request DTOs are actually enforced.
9. Do not assume response types equal runtime responses.
10. Do not assume POST is idempotent.
11. Do not assume webhook events arrive once or in order.
12. Do not assume retries are safe.
13. Do not assume external calls have timeouts.
14. Do not treat 200 responses as proof of success.
15. Do not invent intended status codes where product/API contract is undefined.
16. Compare backend contracts to actual client usage.
17. Inspect for duplicated/legacy routes.
18. Inspect for mock/stub/debug behavior.
19. Validate framework/SDK methods against installed versions when suspicious.
20. Preserve stable finding IDs.
21. Cross-reference Security, Data Integrity, Functional QA, and Code Quality where relevant.
22. Retest before marking findings Verified Closed.
23. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 77. Completion Standard

This audit is complete only when an independent reviewer could answer:

- What API/backend surface exists?
- Which endpoints are critical?
- How are requests authenticated?
- How is authorization enforced?
- Where is validation enforced?
- Are business rules server-authoritative?
- Are status/error contracts consistent?
- Are retries and timeouts safe?
- Are high-impact operations idempotent?
- Are webhooks duplicate-safe?
- Are background jobs safe to retry?
- Are pagination/versioning bounded?
- Do clients and backend agree on contracts?
- What was runtime-tested?
- What remains unknown?
- What remediation is proposed versus verified?
- Can this exact backend version be safely exposed in production?

If those questions cannot be answered from the audit outputs, the audit is not complete.
