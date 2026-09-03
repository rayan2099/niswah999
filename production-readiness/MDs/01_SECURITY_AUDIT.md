# 01 — Security Audit — Production Readiness Master Template

> **Purpose:** A reusable production-readiness security audit for applications built manually or with AI coding agents.
>
> **Core rule:** Security readiness must be based on evidence, not assumptions. A code path, framework default, cloud-provider feature, or installed security library is not proof that a control is actually effective in the release candidate.
>
> This audit is designed to feed directly into `00_PRODUCTION_READINESS_MASTER.md`.

---

# 0. Audit Objective

Determine whether the exact release candidate can be safely exposed to production users by verifying:

- Authentication is implemented correctly.
- Authorization is enforced server-side.
- Sessions/tokens are handled safely.
- Sensitive actions require appropriate controls.
- Inputs are validated and normalized.
- Output handling avoids injection.
- Secrets are not exposed or committed.
- Sensitive data is protected.
- File uploads are controlled.
- APIs do not expose excessive or unauthorized data.
- Rate limiting/abuse controls exist where required.
- Error handling does not leak sensitive internals.
- Security-relevant events are observable.
- Third-party integrations are configured safely.
- Dependency and package risks are understood.
- Production configuration does not enable unsafe debug/test behavior.
- Common AI-generated security mistakes are explicitly checked.
- Critical unknowns are surfaced instead of silently passed.
- Every critical/high security finding is retested after remediation.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | Required work | Output |
|---|---|---|---|
| 1 | **Discovery** | Map attack surface, roles, auth, data, APIs, integrations, secrets, storage, and trust boundaries | Security architecture map |
| 2A | **Static Verification** | Inspect code/config for control implementation and unsafe patterns | Security verification report |
| 2B | **Controlled Security Validation** | Execute safe, authorized tests in staging/pre-production | Security test report |
| 3 | **Remediation Design** | Design fixes — **do not implement unless separately authorized** | Remediation plan |
| Final | **Production Readiness** | Consolidate evidence and issue one verdict | GO / CONDITIONAL GO / NO-GO |

### Golden rule

For every material security control, distinguish:

`Declared → Implemented → Configured → Enforced → Tested`

---

# 2. Safety Rules

During audit:

- Prefer read-only inspection first.
- Do not attack production.
- Do not exfiltrate real sensitive data.
- Do not brute force live accounts.
- Do not send destructive payloads to production.
- Do not rotate live secrets.
- Do not disable security controls.
- Do not use real customer credentials.
- Use synthetic accounts and staging where possible.
- Do not print secret values into reports.
- Do not mark a control PASS solely because a framework/library claims to support it.

---

# 3. Report Header

| Field | Value |
|---|---|
| System | `{SYSTEM_NAME}` |
| Repository | `{REPOSITORY}` |
| Branch | `{BRANCH}` |
| Commit / Version | `{VERSION}` |
| Environment | `{LOCAL / DEV / STAGING / PROD}` |
| Audit date | `{DATE}` |
| Platforms | `{WEB / IOS / ANDROID / API / etc.}` |
| Auth provider | `{PROVIDER}` |
| Primary database | `{DB}` |
| Major integrations | `{INTEGRATIONS}` |
| Restrictions | `{WHAT_WAS_NOT_TESTED}` |

---

# 4. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Controlled Security Test** | Runtime behavior directly verified |
| 🟧 **Confirmed by Code / Config** | Exact implementation/config evidence |
| 🟨 **Likely** | Strong inference, incomplete runtime proof |
| 🟦 **Requires Controlled Validation** | Must be tested before conclusion |
| ⬜ **N/A / False Positive** | Not applicable or disproven |

Every finding must include:

- Finding ID.
- Affected component.
- Attack path / control.
- Expected behavior.
- Actual behavior.
- Evidence.
- Severity.
- Exploitability.
- Production impact.
- Launch-blocker status.
- Confidence.

---

# 5. Severity Model

| Level | Meaning | Launch treatment |
|---|---|---|
| **SEC0 — Critical** | Direct compromise, privilege escalation, sensitive-data exposure, payment/account takeover, or catastrophic authorization failure | **Mandatory NO-GO** |
| **SEC1 — High** | Serious exploitable weakness affecting core trust boundary or sensitive operations | **Pre-launch blocker** |
| **SEC2 — Medium** | Material weakness with bounded impact or harder exploitation path | Explicit acceptance required |
| **SEC3 — Low** | Limited-impact hardening issue | Backlog |
| **SEC4 — Observation** | Improvement opportunity | Backlog |

Severity should consider:

- exploitability,
- privileges required,
- user interaction required,
- blast radius,
- sensitivity of data,
- financial impact,
- persistence,
- detectability,
- ease of abuse,
- internet exposure.

---

# PHASE 1 — DISCOVERY

# 6. Architecture / Trust Boundary Inventory

Map:

- frontend(s),
- backend(s),
- API gateway,
- auth provider,
- DB,
- object storage,
- queues/workers,
- admin interfaces,
- payment provider,
- external APIs,
- analytics,
- AI providers,
- email/SMS/push,
- internal tools.

Use IDs:

- `SYS-001`
- `TRUST-001`

| Component | Trust level | Inputs received from | Outputs sent to | Sensitive? | Internet exposed? |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `{YES/NO}` |

---

# 7. User / Role Inventory

| Role ID | Role | Authentication method | Privileges | Sensitive actions |
|---|---|---|---|---|
| `ROLE-001` | `{}` | `{}` | `{}` | `{}` |

Include:

- guest,
- user/customer,
- staff,
- admin,
- super-admin,
- service account,
- operator,
- provider/driver,
- organization owner.

---

# 8. Authentication Inventory

Document:

- email/password,
- passwordless,
- OAuth,
- SSO,
- social login,
- phone OTP,
- API keys,
- service tokens.

For each method:

- enrollment,
- verification,
- login,
- logout,
- recovery/reset,
- lockout/abuse control,
- session creation.

---

# 9. Authorization Inventory

Map protected actions:

| Action ID | Action | Allowed roles | Server-side check? | Ownership check? | Criticality |
|---|---|---|---|---|---|
| `AUTHZ-001` | `{}` | `{}` | `{YES/NO}` | `{YES/NO}` | `{}` |

Do not rely on UI hiding as authorization.

---

# 10. Sensitive Data Inventory

Identify:

- passwords,
- password hashes,
- auth tokens,
- PII,
- financial/payment identifiers,
- location,
- uploaded documents,
- health/legal data if any,
- private messages,
- API secrets,
- internal admin data.

| Data | Sensitivity | Stored where | Transmitted to | Retention | Encryption |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 11. Secret Inventory

Without printing values, inventory:

- DB credentials,
- API keys,
- JWT secrets/private keys,
- OAuth secrets,
- SMTP credentials,
- payment secrets,
- webhook secrets,
- AI provider keys,
- storage credentials.

| Secret ID | Name | Used by | Storage location | Client exposed? | Rotatable? |
|---|---|---|---|---|---|
| `SECRET-001` | `{NAME}` | `{}` | `{}` | `{YES/NO}` | `{YES/NO}` |

---

# 12. API Surface Inventory

| Endpoint / Route | Method | Auth required? | Role restriction | Sensitive data? | Rate limit? |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Include:

- REST,
- GraphQL,
- RPC,
- websocket,
- webhooks,
- internal admin endpoints.

---

# 13. File Upload Inventory

For each upload path:

- allowed types,
- max size,
- server-side validation,
- malware scanning if required,
- storage destination,
- public/private access,
- filename handling,
- content-type handling.

---

# 14. External Integration Inventory

| Integration | Purpose | Auth method | Sensitive data sent? | Webhook? | Critical? |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 15. Security-Control Inventory

Identify presence/absence of:

- rate limiting,
- brute-force protection,
- CSRF protection,
- CORS policy,
- CSP,
- secure cookies,
- token expiry,
- refresh-token rotation,
- input validation,
- output encoding,
- DB parameterization,
- SSRF prevention,
- webhook verification,
- upload restrictions,
- audit logging.

---

# 16. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Architecture mapped.
- [ ] Trust boundaries identified.
- [ ] Roles identified.
- [ ] Auth methods identified.
- [ ] Authorization-sensitive actions mapped.
- [ ] Sensitive data identified.
- [ ] Secrets inventoried.
- [ ] API surface mapped.
- [ ] Upload surfaces mapped.
- [ ] External integrations mapped.
- [ ] Critical unknowns listed.

---

# PHASE 2A — STATIC VERIFICATION

# 17. Stable Finding Prefixes

| Prefix | Category |
|---|---|
| `AUTHN-xx` | Authentication |
| `AUTHZ-xx` | Authorization |
| `SESS-xx` | Sessions/tokens |
| `PASS-xx` | Password handling |
| `INPUT-xx` | Input validation |
| `INJ-xx` | Injection |
| `XSS-xx` | XSS/output handling |
| `CSRF-xx` | CSRF |
| `CORS-xx` | CORS |
| `SSRF-xx` | SSRF |
| `FILE-xx` | File upload |
| `SECRET-xx` | Secret management |
| `DATA-xx` | Sensitive data |
| `API-xx` | API exposure |
| `RATE-xx` | Rate limiting/abuse |
| `WEBHOOK-xx` | Webhooks |
| `ERR-xx` | Error leakage |
| `LOG-xx` | Security logging |
| `DEP-xx` | Dependency security |
| `CFG-xx` | Production config |
| `ADMIN-xx` | Admin/security operations |
| `AI-xx` | AI-generated security defects |

---

# 18. Authentication Audit

Verify:

- authentication enforced where required,
- verified identity required where product expects it,
- disabled/deactivated accounts cannot authenticate,
- account recovery is safe,
- auth responses do not unnecessarily reveal account existence,
- login flow does not trust client-only state.

---

# 19. Password Audit

Where passwords are used:

- hashing handled by trusted library/provider,
- no plaintext storage,
- password reset tokens expire,
- reset token cannot be reused,
- password change invalidates sessions where appropriate,
- weak custom crypto absent.

Do not invent password complexity rules unless required by project/provider policy.

---

# 20. Authorization Audit

Mandatory checks:

- role enforcement server-side,
- object ownership enforcement,
- tenant boundary enforcement,
- admin endpoints protected,
- hidden UI not treated as access control,
- direct API requests cannot bypass role logic.

High-risk patterns:

- `user_id` accepted from client and trusted,
- role accepted from request body,
- ownership only checked in frontend.

---

# 21. IDOR / Object-Level Authorization Audit

For object endpoints verify a user cannot:

- fetch another user's object,
- edit another user's object,
- delete another user's object,
- download another user's file,
- enumerate sequential IDs to access data.

---

# 22. Session / Token Audit

Inspect:

- token expiry,
- refresh behavior,
- revocation/logout,
- rotation where applicable,
- cookie flags,
- storage location,
- bearer token leakage,
- token in URL/query string,
- long-lived tokens.

For browser cookies inspect where applicable:

- `HttpOnly`
- `Secure`
- `SameSite`

---

# 23. Client Storage Audit

Review use of:

- localStorage,
- sessionStorage,
- IndexedDB,
- mobile secure storage.

Flag sensitive long-lived secrets stored insecurely.

---

# 24. Input Validation Audit

Verify validation exists on authoritative backend boundary for:

- body,
- query,
- path,
- headers,
- uploaded files,
- webhook payloads.

Check:

- type,
- length,
- range,
- enum,
- format,
- normalization.

---

# 25. Injection Audit

Inspect for:

- SQL injection,
- NoSQL injection,
- command injection,
- template injection,
- LDAP/query injection where relevant.

Preferred patterns:

- parameterized queries,
- ORM safe APIs,
- no raw concatenated user input.

---

# 26. XSS / Output Handling Audit

For web apps inspect:

- raw HTML rendering,
- dangerously-set HTML,
- untrusted markdown,
- stored user content,
- rich text,
- URL handling,
- DOM injection.

Flag dangerous bypasses/sanitization assumptions.

---

# 27. CSRF Audit

Where cookie-based authentication is used, assess whether state-changing requests need CSRF protection.

Do not mark N/A without understanding auth model.

---

# 28. CORS Audit

Verify:

- allowed origins explicit where appropriate,
- credentials mode intentional,
- wildcard origin not used unsafely with credentials,
- dev origins not left in production unnecessarily.

---

# 29. SSRF Audit

Inspect any server behavior that fetches user-controlled URLs:

- image proxy,
- webhook tester,
- import by URL,
- metadata fetch,
- PDF/image processor,
- URL preview.

Flag access to internal/private ranges if unrestricted.

---

# 30. File Upload Audit

Verify:

- server-side type validation,
- size limit,
- dangerous extension handling,
- filename/path sanitization,
- storage outside executable path,
- private files protected,
- signed URLs scoped/expiring where used,
- malicious content risk understood.

---

# 31. Secret Management Audit

Search for:

- hardcoded secrets,
- committed `.env`,
- sample secrets that are actually live,
- API keys in frontend bundles,
- secrets in logs,
- secrets in source comments,
- secrets in test fixtures.

Never print discovered values in report.

Use redaction.

---

# 32. Sensitive Data Exposure Audit

Inspect:

- over-broad API responses,
- unnecessary user fields,
- admin-only fields exposed,
- private metadata in client payloads,
- sensitive query parameters,
- sensitive data in URLs,
- response caching.

---

# 33. Error Leakage Audit

Verify production errors do not expose:

- stack traces,
- SQL,
- filesystem paths,
- secrets,
- internal service names unnecessarily,
- debug payloads.

---

# 34. Logging Audit

Verify logs do not include:

- passwords,
- tokens,
- full payment credentials,
- secret headers,
- sensitive documents,
- unnecessary PII.

Security-relevant events should be detectable:

- failed auth bursts,
- denied access,
- admin actions,
- webhook verification failures.

---

# 35. Rate Limiting / Abuse Audit

Assess need for controls on:

- login,
- OTP,
- password reset,
- signup,
- search/scraping,
- file upload,
- expensive AI calls,
- payment attempts,
- messaging,
- public APIs.

Do not require identical limits everywhere; assess abuse risk.

---

# 36. Webhook Security Audit

Verify:

- signature/token verification,
- replay protection/idempotency where relevant,
- timestamp tolerance where supported,
- payload validation,
- endpoint rate protection,
- secrets server-side.

---

# 37. Payment Security Audit

Where payments exist:

- server trusts provider/backend confirmation,
- client cannot mark payment success,
- amounts/currency validated server-side,
- webhook signatures verified,
- duplicate callbacks idempotent,
- refund/cancel authorization controlled.

Do not handle raw card data unless architecture explicitly requires it.

---

# 38. Admin Surface Audit

Verify:

- admin authentication,
- admin authorization,
- elevated actions protected,
- no hidden unauthenticated admin route,
- sensitive actions auditable,
- production admin/debug tools not exposed publicly.

---

# 39. Multi-Tenant Isolation Audit

Where applicable:

- tenant ID derived safely,
- tenant ownership enforced server-side,
- queries scoped to tenant,
- cross-tenant admin exceptions explicit,
- storage paths segregated appropriately.

---

# 40. Dependency Security Cross-Check

Without duplicating Dependencies Audit:

- identify known critical dependency advisories if tool evidence is available,
- unsupported security-sensitive packages,
- abandoned auth/crypto libraries.

Do not perform mass upgrades during audit.

---

# 41. Production Configuration Security Audit

Check for:

- debug mode,
- verbose errors,
- dev auth bypass,
- mock provider,
- sandbox credentials in production,
- wildcard CORS,
- insecure cookies,
- open admin routes,
- unprotected test endpoints.

---

# 42. Security Headers Audit

For web apps inspect where applicable:

- HSTS,
- CSP,
- frame protections,
- MIME sniffing protections,
- referrer policy.

Treat headers as defense-in-depth, not substitutes for core controls.

---

# 43. AI-Agent-Specific Security Audit

Mandatory when AI coding agents were used.

Actively search for:

## 43.1 Client-side authorization
Agent hides buttons but backend accepts request.

## 43.2 Hardcoded secrets
Agent embeds token/key for convenience.

## 43.3 Placeholder auth
Examples:
- `if (user) allow`
- dev bypass
- temporary admin password
- fake role checks.

## 43.4 Insecure direct object references
Agent trusts IDs from route/body without ownership check.

## 43.5 Broad database rules
Examples:
- allow all reads/writes,
- permissive Firebase/Supabase policies,
- temporary RLS bypass.

## 43.6 Unsafe raw queries
Concatenated SQL/NoSQL input.

## 43.7 Unsafe file upload
No backend type/size/access validation.

## 43.8 Trusting frontend payment state
Client sends `"paid": true`.

## 43.9 Generic webhook endpoint
Accepts payload without signature verification.

## 43.10 Debug/test endpoints
Left enabled after development.

## 43.11 Security library without actual enforcement
Middleware installed but not applied to critical routes.

## 43.12 AI hallucinated framework behavior
Code assumes a security default that framework/version does not provide.

---

# 44. Static Verification Matrix

| Check ID | Category | Component | Expected control | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 45. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Authentication reviewed.
- [ ] Authorization reviewed.
- [ ] Object/tenant isolation reviewed.
- [ ] Session/token handling reviewed.
- [ ] Input/injection reviewed.
- [ ] XSS/CSRF/CORS reviewed where applicable.
- [ ] SSRF reviewed where applicable.
- [ ] File upload reviewed.
- [ ] Secret handling reviewed.
- [ ] Sensitive data exposure reviewed.
- [ ] Rate limiting/abuse reviewed.
- [ ] Webhooks/payment reviewed where applicable.
- [ ] Admin surface reviewed.
- [ ] Production config reviewed.
- [ ] AI-specific risks reviewed.
- [ ] SEC0/SEC1 candidates have evidence.

---

# PHASE 2B — CONTROLLED SECURITY VALIDATION

# 46. Rules

- Prefer staging/pre-production.
- Use synthetic users.
- Do not exploit real users.
- Do not brute force.
- Do not persist destructive payloads.
- Do not bypass safeguards just to prove theoretical impact.
- Use minimum test necessary to verify the control.

---

# 47. Test Prefixes

| Prefix | Category |
|---|---|
| `SEC-AUTHN-xx` | Authentication |
| `SEC-AUTHZ-xx` | Authorization |
| `SEC-IDOR-xx` | Object-level access |
| `SEC-SESS-xx` | Sessions |
| `SEC-INPUT-xx` | Input validation |
| `SEC-INJ-xx` | Injection |
| `SEC-XSS-xx` | XSS |
| `SEC-CSRF-xx` | CSRF |
| `SEC-CORS-xx` | CORS |
| `SEC-FILE-xx` | Uploads |
| `SEC-RATE-xx` | Rate/abuse |
| `SEC-WH-xx` | Webhooks |
| `SEC-PAY-xx` | Payment controls |
| `SEC-TENANT-xx` | Tenant isolation |

---

# 48. Controlled Test Matrix

| Test ID | Control | Role | Preconditions | Expected | Actual | Evidence | Result |
|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 49. Authentication Negative Tests

Test safely:

- invalid password,
- invalid/expired token,
- disabled user,
- malformed token,
- logout then reuse old token if applicable.

---

# 50. Authorization Tests

For each critical role:

- allowed action succeeds,
- disallowed action fails server-side,
- direct endpoint request cannot bypass UI restrictions.

---

# 51. IDOR Tests

Using two synthetic users:

1. create object as user A,
2. authenticate as user B,
3. attempt read/update/delete using A's identifier,
4. verify denial.

---

# 52. Session Tests

Where applicable:

- token expiry,
- logout invalidation,
- refresh token behavior,
- account switching,
- session reuse.

---

# 53. Input / Injection Tests

Use non-destructive payloads to verify rejection/parameterization.

Do not attempt destructive extraction.

---

# 54. XSS Tests

Use benign payloads in isolated test data.

Verify untrusted content is rendered safely.

---

# 55. CORS / CSRF Tests

Where applicable verify unauthorized origins/cross-site requests cannot perform sensitive actions.

---

# 56. File Upload Tests

Using harmless test files:

- disallowed type,
- oversized file,
- renamed extension,
- private-file access from another user.

---

# 57. Rate / Abuse Tests

Use limited controlled bursts only.

Verify throttling/abuse protections exist where required.

Do not conduct denial-of-service testing.

---

# 58. Webhook Validation Test

Where sandbox provider supports it:

- valid signed webhook accepted,
- invalid signature rejected,
- duplicate event handled safely.

---

# 59. Payment Authorization Test

Using sandbox:

- modify client-visible amount/ID where safely testable,
- verify backend/provider authoritative values control result,
- duplicate callback does not duplicate logical financial outcome.

---

# 60. Tenant Isolation Test

Using two synthetic tenants:

- attempt cross-tenant reads/writes,
- verify denial,
- verify admin exceptions only when intended.

---

# 61. Controlled Validation Summary

| Metric | Count |
|---|---:|
| Security tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| SEC0 findings | `{}` |
| SEC1 findings | `{}` |
| SEC2 findings | `{}` |

---

# 62. Controlled Validation Exit Gate

Phase 2B passes only when:

- [ ] Critical auth tests executed.
- [ ] Critical authorization tests executed.
- [ ] IDOR/object-ownership tests executed.
- [ ] Session controls tested where applicable.
- [ ] Critical input handling tested.
- [ ] Upload controls tested where applicable.
- [ ] Webhook/payment security tested where applicable.
- [ ] Tenant isolation tested where applicable.
- [ ] Every FAIL has finding ID.
- [ ] No critical control is marked PASS solely from documentation.

---

# 63. Finding Register

| Finding ID | Category | Severity | Component | Summary | Evidence | Exploitability | Production impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|---|
| `SEC-001` | `{}` | `{SEC0-SEC4}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 64. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** Security fixes can affect authentication, authorization, sessions, APIs, and production behavior. Nothing below should be described as fixed until implementation and controlled security regression tests pass.

---

# 65. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `SEC-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 66. Remediation Principles

| Principle | Application |
|---|---|
| Enforce server-side | Never rely on UI-only restrictions |
| Least privilege | Minimum access required |
| Deny by default | Unknown role/state denied |
| Validate at trust boundary | Do not trust client input |
| Minimize sensitive data | Return/store only what is needed |
| Centralize auth controls | Avoid duplicated ad-hoc checks |
| Use trusted crypto/auth providers | Avoid custom security primitives |
| Fail safely | Missing config/control must not open access |
| Retest exploit path | Fix is incomplete without regression test |

---

# 67. Security Fix Requirements

For each fix document:

- finding,
- root cause,
- exact components,
- auth/session impact,
- data impact,
- compatibility risk,
- migration/config need,
- rollback,
- regression test,
- E2E journeys affected.

---

# 68. Remediation Phase Table

| # | Action | Findings closed | Components | Security impact | Regression risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 69. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root cause identified.
- [ ] Fix enforces authoritative control.
- [ ] Related routes/components identified.
- [ ] Regression risk understood.
- [ ] Rollback defined.
- [ ] Security retest defined.
- [ ] Related E2E journeys identified.
- [ ] No cosmetic/client-only fix proposed for server-side security issue.

---

# FINAL — SECURITY PRODUCTION READINESS REPORT

# 70. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Security tests
`{PASS}/{EXECUTED}`

### Open findings
- SEC0: `{COUNT}`
- SEC1: `{COUNT}`
- SEC2: `{COUNT}`
- SEC3: `{COUNT}`

### Critical unknowns
`{COUNT}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 71. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open SEC0.
- Zero open SEC1.
- Critical authentication controls verified.
- Critical authorization controls verified.
- Object/tenant boundaries verified.
- Session/token handling acceptable.
- No critical secret exposure.
- Critical input/injection risks controlled.
- Critical file-upload risks controlled where applicable.
- Webhook/payment trust boundaries safe where applicable.
- Production debug/test bypass absent.
- No critical security unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero SEC0.
- Zero launch-blocking SEC1.
- Remaining issues are bounded SEC2 findings.
- Core trust boundaries remain protected.
- Explicit owner accepts residual security risk.
- No critical unknown remains.

## 🔴 NO-GO

Use if:

- Any SEC0 remains.
- Any launch-blocking SEC1 remains.
- Authentication can be bypassed.
- Authorization can be bypassed.
- IDOR/cross-tenant access is exploitable.
- Sensitive secret is exposed.
- Client can forge critical payment/account state.
- Production contains an auth/debug bypass.
- Critical file/upload path permits dangerous access/execution.
- Webhook trust can be forged for critical state.
- Critical security behavior remains unknown.

---

# 72. Security Launch Gates

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-SEC-01` | Zero open SEC0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-SEC-02` | Zero launch-blocking SEC1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-SEC-03` | Authentication verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-SEC-04` | Authorization verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-SEC-05` | Object/tenant isolation verified | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-SEC-06` | Session/token handling verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-SEC-07` | Secrets handled safely | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-SEC-08` | Input/injection controls verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-SEC-09` | Upload controls safe | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-SEC-10` | Webhook/payment trust verified | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-SEC-11` | Production config has no security bypass | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-SEC-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 73. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Accepted? |
|---|---|---|---|---|---|---|---|
| `RISK-SEC-001` | `{REF}` | `{SEC}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

An AI auditor cannot accept security risk on behalf of the release owner.

---

# 74. Out-of-Scope / Not Verified

Explicitly list:

- production penetration testing not performed,
- third-party provider internals unavailable,
- source-code area not accessible,
- native binary not tested,
- certain auth method unavailable,
- infrastructure/network layer excluded,
- formal compliance certification excluded,
- social-engineering testing excluded,
- denial-of-service testing excluded,
- anything intentionally excluded.

Do not convert missing access into PASS.

---

# 75. Final One-Sentence Recommendation

### GO

> Security recommendation: **GO for production** for `{VERSION}` because all mandatory security launch gates passed, critical trust boundaries were verified, and no unresolved critical/high security blocker or critical unknown remains.

### CONDITIONAL GO

> Security recommendation: **CONDITIONAL GO** for `{VERSION}`, subject only to explicitly accepted SEC2 residual risks; all critical authentication, authorization, session, data, and integration trust boundaries remain protected.

### NO-GO

> Security recommendation: **NO-GO** for `{VERSION}` until findings `{SEC-xxx...}` are remediated and the associated controlled security regression tests pass.

---

# 76. Required Deliverables

A complete Security Audit should produce:

1. `01_SECURITY_DISCOVERY_REPORT.md`
2. `02_SECURITY_STATIC_VERIFICATION_REPORT.md`
3. `03_SECURITY_CONTROLLED_TEST_REPORT.md`
4. `04_SECURITY_REMEDIATION_PLAN.md`
5. `05_SECURITY_PRODUCTION_READINESS_REPORT.md`

Optional:

- `SECURITY_ATTACK_SURFACE_MAP.md`
- `ROLE_AUTHORIZATION_MATRIX.md`
- `SECRET_INVENTORY.md`
- `API_SECURITY_MATRIX.md`
- `SECURITY_TEST_MATRIX.md`
- `SECURITY_FINDINGS.csv`

---

# 77. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read the entire template before starting.
2. Do not modify code during Discovery/Verification.
3. Do not attack production.
4. Do not expose secret values in reports.
5. Do not assume frontend restrictions equal authorization.
6. Do not assume framework defaults are correctly configured.
7. Inspect server-side role and ownership enforcement.
8. Inspect session/token behavior.
9. Inspect secret handling.
10. Inspect API overexposure.
11. Inspect input validation and injection surfaces.
12. Inspect file uploads.
13. Inspect webhook/payment trust.
14. Inspect rate-limiting/abuse paths.
15. Inspect production debug/test bypasses.
16. Inspect AI-generated broad DB/security rules.
17. Inspect client-trusted financial/account state.
18. Use synthetic users for controlled validation.
19. Preserve stable finding IDs.
20. Cross-reference Database, API, Privacy, Dependencies, Observability, Release, and Final Journey audits.
21. After remediation, rerun both specialist security tests and affected E2E journeys.
22. End with exactly one recommendation:
   - **GO**
   - **CONDITIONAL GO**
   - **NO-GO**

---

# 78. Completion Standard

This security audit is complete only when an independent reviewer can answer:

- What is the attack surface?
- What are the trust boundaries?
- How does authentication work?
- How is authorization enforced?
- Are ownership/tenant boundaries protected?
- Are sessions/tokens safe?
- Are secrets handled safely?
- Are critical inputs validated?
- Are injection/XSS/CSRF/CORS/SSRF risks addressed where applicable?
- Are uploads safe?
- Are sensitive APIs protected?
- Are critical endpoints abuse-protected?
- Are webhooks/payment callbacks trusted correctly?
- Does production contain any debug/test bypass?
- What security tests were actually executed?
- What remains unknown?
- What remediation is proposed versus verified?
- Are any critical/high security blockers still open?
- Can this exact release candidate safely proceed to production from a security standpoint?

If those questions cannot be answered from the audit outputs, the security audit is not complete.
