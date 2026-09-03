# Privacy & Compliance Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for evaluating whether an application handles personal data responsibly, transparently, and consistently with its stated privacy obligations before launch.
>
> This template is designed for applications built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark privacy/compliance PASS because a privacy policy exists, consent checkboxes are present, or encryption is enabled. Technical behavior, user-facing disclosures, data flows, retention, deletion, and third-party processing must be verified against the actual system.**
>
> **Important legal boundary:** This audit can identify technical and operational privacy/compliance gaps. It must not claim definitive legal compliance with any jurisdiction unless the applicable laws, regulatory requirements, contracts, and legal interpretation have been explicitly reviewed by qualified counsel or an authorized compliance owner.

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current application is privacy-ready for production by verifying:

- Personal data collected by the application is inventoried.
- Collection has a documented purpose.
- Data minimization is applied.
- Sensitive/special-category data is identified.
- Consent or other lawful processing basis is documented where required.
- User-facing privacy disclosures match actual behavior.
- Data is not collected invisibly or unnecessarily.
- Retention periods are defined and technically enforceable where appropriate.
- Deletion/deactivation behavior matches stated promises.
- Account deletion does not leave unexplained personal data behind.
- Data exports/access requests can be supported where required.
- Third-party processors/subprocessors are inventoried.
- Analytics/advertising/telemetry behavior is documented.
- Cookies/local storage/device identifiers are inventoried.
- Cross-border processing is identified.
- Production logs do not contain inappropriate personal/sensitive data.
- Test/dev environments do not unnecessarily contain real personal data.
- File uploads and user-generated content have clear retention/deletion ownership.
- Children's/minors' data risks are identified where applicable.
- AI/ML providers receiving user data are explicitly inventoried.
- Data used for model training or external AI processing is documented.
- Privacy settings/consent state are persisted and respected.
- AI-generated code has not added tracking, telemetry, user profiling, or data transmission without explicit product awareness.

## 0.2 Non-goals

This audit does **not** replace:

- Legal advice.
- Formal regulatory certification.
- Security penetration testing.
- Security audit.
- Contract/legal-document review.
- Data Protection Impact Assessment performed by authorized legal/compliance personnel.
- Accessibility audit.
- Incident-response planning.

Where legal interpretation is required, mark the item:

**LEGAL / COMPLIANCE OWNER REVIEW REQUIRED**

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Map personal data, purposes, actors, storage, transfers, cookies, vendors, retention, and user rights | Privacy data map |
| 2A | **Static Verification** | Compare actual implementation, disclosures, configs, and data flows against documented privacy rules | Privacy evidence matrix |
| 2B | **Controlled Validation** | Execute safe tests for consent, deletion, export, preferences, tracking, and retention behavior | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design privacy fixes — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate technical privacy evidence and issue launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**Policy text is not proof of privacy behavior.**

Always compare:

`What the product says → What the UI asks → What the code collects → What the backend stores → What vendors receive → What deletion/retention actually does`

Any mismatch must be documented.

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
| Jurisdiction(s) identified | `{COUNTRIES / REGIONS / UNKNOWN}` |
| Privacy owner | `{OWNER / UNKNOWN}` |
| Legal review available? | `{YES / NO / PARTIAL}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Runtime / Configuration** | Proven by direct system behavior, vendor config, or controlled test |
| 🟧 **Confirmed by Code / Documentation** | Proven by implementation, schema, policy text, or configuration files |
| 🟨 **Likely** | Strong inference but direct evidence incomplete |
| 🟦 **Requires Controlled Test / Owner Confirmation** | Must be tested or confirmed before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was disproven |

For every material finding include:

- Finding ID.
- Data category.
- Processing purpose.
- User/role affected.
- Collection point.
- Storage location.
- Third-party recipient if any.
- Evidence.
- Severity.
- Legal-review requirement.
- Launch-blocker status.
- Confidence.

---

# 4. Severity Model

| Level | Classification | Privacy meaning | Launch treatment |
|---|---|---|---|
| **PC0** | Critical | Severe undisclosed/sensitive processing, inability to honor critical deletion rights, exposed regulated data behavior, or major mismatch likely to create serious legal/user harm | **Mandatory NO-GO** |
| **PC1** | High | Material privacy obligation is missing, misleading, unenforced, or inconsistent with actual processing | **Pre-launch blocker** |
| **PC2** | Medium | Important privacy gap with bounded impact and documented remediation/acceptance | Explicit acceptance required |
| **PC3** | Low | Minor disclosure/data-handling inconsistency | Backlog acceptable |
| **PC4** | Observation | Improvement opportunity / legal review note | Backlog |

## 4.1 Severity factors

Evaluate:

- Sensitivity of data.
- Number of users affected.
- Whether processing is hidden.
- Whether data leaves the organization.
- Whether minors may be involved.
- Whether financial/identity/health/biometric data is involved.
- Whether deletion is impossible.
- Whether user choice is ignored.
- Whether processing is irreversible.
- Whether violation can continue silently.
- Whether third-party retention is involved.
- Whether legal/contractual obligation appears implicated.

---

# 5. Legal Boundary Classification

Every compliance-related item must be classified as one of:

| Classification | Meaning |
|---|---|
| **TECHNICAL REQUIREMENT** | Can be evaluated from implementation/system behavior |
| **PRODUCT/POLICY REQUIREMENT** | Requires product-owner decision or policy confirmation |
| **LEGAL INTERPRETATION REQUIRED** | Cannot be conclusively resolved by technical audit |
| **CONTRACTUAL REQUIREMENT** | Depends on vendor/customer/data-processing contracts |
| **REGULATORY OWNER REVIEW REQUIRED** | Requires compliance/DPO/legal owner |

Never invent a lawful basis, retention period, statutory requirement, age threshold, or jurisdictional obligation.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Build a complete map of personal-data processing before judging compliance.

### Mandatory restrictions

During discovery:

- Prefer read-only inspection.
- Do not export production personal data.
- Do not download full customer tables.
- Do not inspect unnecessary individual user records.
- Do not create new tracking.
- Do not modify consent settings.
- Do not invoke deletion against real users.
- Do not send personal data to external tools for analysis.
- Do not copy secrets or sensitive records into audit reports.

---

# 7. Personal Data Inventory

Use stable IDs:

- `PD-001`, `PD-002`, ...

Possible categories:

- name,
- email,
- phone,
- address,
- location,
- date of birth,
- profile photo,
- user-generated content,
- device identifier,
- IP address,
- cookies,
- analytics identifiers,
- employment/education data,
- payment metadata,
- financial data,
- government identifiers,
- health information,
- biometric data,
- behavioral data,
- inferred preferences,
- communications,
- support tickets.

| Data ID | Data element | Category | Source | Required? | Purpose | Storage | Sensitivity |
|---|---|---|---|---|---|---|---|
| `PD-001` | `{DATA}` | `{CATEGORY}` | `{USER/SYSTEM/THIRD PARTY}` | `{YES/NO}` | `{PURPOSE}` | `{LOCATION}` | `{Normal/Sensitive/Unknown}` |

---

# 8. Data Flow Map

For every important data element map:

`Collection → API → Database → Analytics/Provider → Backup → Deletion`

| Data ID | Collected at | Processed by | Stored in | Shared with | Retention | Deletion path |
|---|---|---|---|---|---|---|
| `{PD}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 9. Purpose Inventory

For each collected data element identify purpose.

| Data | Purpose | Necessary? | Product owner confirmed? | Legal basis required? |
|---|---|---|---|---|
| `{}` | `{}` | `{YES/NO/UNKNOWN}` | `{YES/NO}` | `{YES/NO/UNKNOWN}` |

Flag data with no identifiable purpose.

---

# 10. Data Minimization Inventory

Ask:

- Is each field needed?
- Is precision higher than necessary?
- Is historical retention necessary?
- Is the app collecting fields “for future use” without defined purpose?
- Is raw data retained where an aggregate would suffice?
- Is exact location collected when approximate location is enough?

---

# 11. Sensitive Data Inventory

Identify potential sensitive/high-risk data.

Examples:

- government ID,
- health,
- biometric,
- precise location,
- financial account data,
- minors' data,
- authentication secrets,
- private communications.

For each:

| Data | Why sensitive | Collected? | Stored? | Shared? | Required controls / legal review |
|---|---|---|---|---|---|

---

# 12. User / Data Subject Inventory

Document affected groups:

- customers,
- employees,
- students,
- drivers,
- vendors,
- admins,
- guests,
- minors,
- job applicants,
- business contacts.

Different groups may require different notices/retention.

---

# 13. Collection Point Inventory

Document all collection locations:

- registration,
- profile,
- checkout,
- support,
- contact form,
- uploads,
- mobile permissions,
- background location,
- analytics,
- cookies,
- SDKs,
- crash reports,
- social login,
- imported data.

---

# 14. Permission Inventory

For device/app permissions:

- location,
- camera,
- microphone,
- photos/files,
- contacts,
- notifications,
- Bluetooth,
- motion/activity.

| Permission | Feature | Required? | Just-in-time explanation? | Decline behavior | Persisted consent? |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 15. Consent / Preference Inventory

Identify all consent/preference mechanisms:

- terms acceptance,
- privacy acknowledgement,
- marketing consent,
- cookies,
- analytics consent,
- personalized ads,
- location,
- communication channels,
- AI processing consent where product/legal owner requires.

Document:

- default state,
- timestamp,
- policy version,
- withdrawal mechanism,
- propagation.

---

# 16. Privacy Notice / Disclosure Inventory

Identify:

- privacy policy,
- in-app notices,
- cookie notice,
- permission explanations,
- signup disclosures,
- marketing consent text,
- deletion explanation.

Record version/date and where surfaced.

---

# 17. Third-Party Processor Inventory

Use stable IDs:

- `TP-001`, `TP-002`, ...

| Vendor | Purpose | Data received | Data location known? | Retention known? | Contract/DPA known? | Criticality |
|---|---|---|---|---|---|---|
| `{VENDOR}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Include:

- cloud provider,
- authentication,
- analytics,
- crash reporting,
- email,
- SMS,
- payment,
- maps,
- AI providers,
- support tools,
- CRM,
- advertising.

---

# 18. AI Provider Inventory

For each AI/LLM/ML integration:

| Provider | User data sent? | Data fields | Purpose | Training use known? | Retention known? | User disclosure exists? |
|---|---|---|---|---|---|---|
| `{}` | `{YES/NO}` | `{}` | `{}` | `{YES/NO/UNKNOWN}` | `{}` | `{}` |

Flag unknown vendor training/retention behavior for owner/legal review.

---

# 19. Cookie / Local Storage Inventory

Document:

- cookies,
- localStorage,
- IndexedDB,
- mobile secure storage,
- device IDs,
- advertising IDs,
- analytics identifiers.

| Storage item | Purpose | Personal identifier? | Essential? | Expiry | Consent dependency |
|---|---|---|---|---|---|

---

# 20. Analytics / Tracking Inventory

Identify:

- page views,
- events,
- session recording,
- heatmaps,
- attribution,
- ad pixels,
- device fingerprinting,
- crash analytics,
- product analytics.

Flag tracking added implicitly by SDK defaults.

---

# 21. Retention Inventory

For each personal data category:

| Data | Active retention | Post-account retention | Backup retention | Reason | Technically enforced? | Owner confirmed? |
|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Unknown retention is a finding.

Do not invent retention periods.

---

# 22. Deletion / Deactivation Inventory

Document exact behavior when:

- user deletes account,
- admin deletes user,
- user is deactivated,
- subscription ends,
- retention expires.

Determine:

- hard delete,
- soft delete,
- anonymization,
- archive,
- legal hold,
- third-party deletion request,
- backup expiry.

---

# 23. Data Access / Export Inventory

Document whether system can produce:

- profile data,
- transaction history,
- uploaded content,
- consent history,
- account activity.

Do not claim a legal right applies unless jurisdiction is confirmed.

---

# 24. Correction / Update Inventory

Determine whether users/admins can correct inaccurate personal data and whether corrections propagate to downstream systems.

---

# 25. Cross-Border / Region Inventory

Document:

- hosting region,
- DB region,
- storage region,
- analytics region,
- AI provider region,
- support-tool region,
- backup region.

If unknown, mark **CONTRACTUAL / LEGAL REVIEW REQUIRED**.

---

# 26. Environment Data Inventory

For:

- local,
- development,
- staging,
- QA,
- support tools.

Verify whether real personal data is copied outside production.

Flag production dumps used casually in lower environments.

---

# 27. Logging Data Inventory

Identify personal/sensitive data that may appear in:

- application logs,
- error tracking,
- traces,
- analytics,
- provider logs.

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

- [ ] Personal data inventory exists.
- [ ] Data flows mapped.
- [ ] Purposes identified.
- [ ] Sensitive data identified.
- [ ] Collection points identified.
- [ ] Permissions identified.
- [ ] Consent/preferences identified.
- [ ] Third-party processors identified.
- [ ] AI providers identified where applicable.
- [ ] Cookies/tracking identified.
- [ ] Retention/deletion behavior understood.
- [ ] Environment/logging data exposure identified.
- [ ] Unknown legal/compliance assumptions listed.

---

# PHASE 2A — STATIC VERIFICATION

# 30. Objective

Compare actual product behavior and implementation against privacy expectations.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `COLL-xx` | Collection |
| `MIN-xx` | Minimization |
| `PURP-xx` | Purpose |
| `CONS-xx` | Consent |
| `PREF-xx` | Preferences |
| `DISC-xx` | Disclosure |
| `RET-xx` | Retention |
| `DEL-xx` | Deletion |
| `EXP-xx` | Export/access |
| `CORR-xx` | Correction |
| `TP-xx` | Third parties |
| `AI-xx` | AI processing |
| `COOKIE-xx` | Cookies/storage |
| `TRACK-xx` | Analytics/tracking |
| `LOG-xx` | Logging/privacy |
| `ENV-xx` | Lower environments |
| `CHILD-xx` | Minors |
| `REGION-xx` | Cross-border/region |
| `POLICY-xx` | Privacy-policy mismatch |
| `DARK-xx` | Manipulative consent patterns |

---

# 31. Collection Verification

For each data field verify:

- actual collection point,
- whether required/optional,
- whether purpose exists,
- whether server stores it,
- whether third parties receive it.

Flag fields collected but unused.

---

# 32. Minimization Verification

Inspect:

- unnecessary fields,
- excessive location precision,
- excessive history,
- duplicate storage,
- raw payload storage,
- complete provider response retention where only ID/status needed.

---

# 33. Consent Verification

Where consent is required by product/legal owner, verify:

- not preselected unless explicitly allowed,
- explicit action captured,
- version/timestamp retained where needed,
- withdrawal available,
- withdrawal takes effect,
- downstream use respects preference.

---

# 34. Preference Enforcement Audit

If user disables:

- marketing,
- analytics,
- tracking,
- notifications,
- location,
- personalization,

verify code paths actually stop or change behavior as expected.

---

# 35. Privacy Policy Reality Check

Compare privacy/disclosure text against actual system behavior.

For each statement:

| Statement | Actual behavior | Match? | Evidence | Finding |
|---|---|---|---|---|
| `{CLAIM}` | `{OBSERVED}` | `{YES/NO/UNKNOWN}` | `{}` | `{}` |

Flag:

- policy says data not shared but vendor receives it,
- policy says deletion but data remains indefinitely,
- policy omits analytics/AI processing,
- policy describes outdated provider.

---

# 36. Retention Verification

Determine whether retention is:

- technically enforced,
- manual,
- undefined,
- inconsistent across systems.

Flag “retain only as needed” with no operational rule where actual deletion never occurs.

---

# 37. Deletion Verification

Trace deletion across:

- primary DB,
- secondary tables,
- file storage,
- cache,
- analytics,
- search index,
- external vendors,
- backups.

Separate:

- immediate deletion,
- scheduled deletion,
- backup expiry,
- legally/contractually retained data.

Unknown residual data must be documented.

---

# 38. Third-Party Sharing Verification

For each vendor verify actual data transmitted.

Inspect SDK initialization and event payloads.

Flag:

- sending full user object unnecessarily,
- PII in analytics event properties,
- provider receiving data not documented internally.

---

# 39. AI Processing Verification

Inspect:

- prompts,
- attachments,
- conversation history,
- profile context,
- identifiers,
- metadata sent to AI provider.

Verify product knows exactly what leaves system boundary.

Flag raw personal data sent when anonymized/minimized data would suffice.

---

# 40. Cookie / Tracking Verification

Inspect actual browser/app behavior:

- trackers before consent,
- analytics after opt-out,
- third-party cookies,
- session replay,
- ad pixels,
- persistent device identifiers.

Legal interpretation depends on jurisdiction.

---

# 41. Logging Privacy Verification

Inspect whether logs/errors include:

- passwords,
- tokens,
- full authorization headers,
- payment data,
- private messages,
- full addresses,
- precise location,
- uploaded document content,
- sensitive IDs.

Escalate technical secret exposure to Security Audit.

---

# 42. Lower-Environment Data Verification

Verify:

- production data not copied casually,
- anonymization if copied,
- access limited,
- old dumps removed,
- screenshots/debug exports controlled.

---

# 43. Minors / Age-Related Verification

If product may serve minors:

- identify age assumptions,
- onboarding representation,
- guardian/consent requirement if product/legal owner establishes one,
- data minimization,
- tracking/advertising behavior.

Do not invent legal age thresholds.

---

# 44. Dark Pattern / Consent UX Audit

Inspect for:

- misleading button hierarchy,
- hidden decline option,
- bundled unrelated consent,
- forced marketing consent for core service,
- confusing withdrawal,
- repeated nagging after decline.

Classify legal significance as requiring owner/legal review.

---

# 45. AI-Agent-Specific Privacy Audit

Mandatory when AI agents were used.

Actively search for:

## 45.1 Unplanned telemetry

- new analytics SDK,
- automatic page tracking,
- session replay,
- crash SDK collecting user fields.

## 45.2 Excessive debug payloads

- full request/response logged,
- user profile dumped,
- prompt content logged.

## 45.3 AI provider data leakage

- full user records inserted into prompts,
- uploaded files sent wholesale,
- unnecessary conversation history attached.

## 45.4 Fake deletion

- UI says deleted but only hides row,
- soft delete with no retention rule,
- files left in storage.

## 45.5 Preference ignored

- consent flag stored but never checked,
- opt-out changes UI only.

## 45.6 New fields without disclosure

- AI agent adds DOB, phone, location, device ID without product/privacy review.

## 45.7 Test data copied into production

- seeded demo users,
- copied real customer records used for testing.

---

# 46. Static Verification Matrix

| Check ID | Category | Data / Flow | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 47. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Data collection reviewed.
- [ ] Minimization reviewed.
- [ ] Consent/preference enforcement reviewed.
- [ ] Policy behavior compared.
- [ ] Retention reviewed.
- [ ] Deletion path reviewed.
- [ ] Third-party sharing reviewed.
- [ ] AI processing reviewed where applicable.
- [ ] Tracking/cookies reviewed.
- [ ] Logging privacy reviewed.
- [ ] Lower-environment data reviewed.
- [ ] AI-agent-specific privacy risks reviewed.
- [ ] PC0/PC1 candidates have evidence.
- [ ] Legal interpretation items are clearly separated.

---

# PHASE 2B — CONTROLLED VALIDATION

# 48. Objective

Prove critical privacy behavior using synthetic accounts/data.

### Mandatory restrictions

- Prefer staging/test.
- Use synthetic identities.
- Do not export real user datasets.
- Do not delete real accounts.
- Do not send synthetic sensitive data to vendors unless approved.
- Clearly label test data.

---

# 49. Privacy Test Categories

| Prefix | Category |
|---|---|
| `PR-CONS-xx` | Consent |
| `PR-PREF-xx` | Preferences |
| `PR-DEL-xx` | Deletion |
| `PR-EXP-xx` | Export/access |
| `PR-CORR-xx` | Correction |
| `PR-TRACK-xx` | Tracking |
| `PR-PERM-xx` | Permissions |
| `PR-TP-xx` | Third-party transfer |
| `PR-AI-xx` | AI processing |
| `PR-RET-xx` | Retention |
| `PR-LOG-xx` | Logging |

---

# 50. Controlled Privacy Test Matrix

| Test ID | Privacy behavior | Preconditions | Action | Expected result | Actual result | Evidence | Result |
|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 51. Consent Test

Where applicable:

1. New synthetic user.
2. Decline optional consent.
3. Continue product flow.
4. Verify feature accessibility as intended.
5. Verify optional tracking/processing does not occur.
6. Change preference.
7. Verify change propagates.

---

# 52. Account Deletion Test

Using synthetic account:

1. Create account.
2. Populate representative data.
3. Upload test file if applicable.
4. Trigger deletion.
5. Inspect primary DB.
6. Inspect related tables.
7. Inspect storage.
8. Inspect search/cache.
9. Inspect third-party deletion behavior if supported.
10. Document backup handling separately.

---

# 53. Data Export / Access Test

Where product/legal requirement exists:

- request export,
- verify identity/auth process,
- verify expected data categories,
- verify no unrelated users' data,
- verify format usability,
- verify timing/process ownership.

---

# 54. Preference Withdrawal Test

Disable marketing/analytics/etc.

Verify:

- new events stop,
- communication stops where intended,
- preference persists across device/session,
- preference applies server-side where relevant.

---

# 55. Permission Denial Test

For location/camera/microphone/etc.:

- deny permission,
- verify graceful behavior,
- verify no hidden repeated collection,
- verify user can continue where feature is optional.

---

# 56. Third-Party Transfer Test

Use synthetic account.

Inspect actual outgoing request/event payload where authorized.

Verify only intended fields are transmitted.

---

# 57. AI Data Transfer Test

For AI-powered feature:

- use synthetic profile/content,
- inspect constructed prompt/request,
- identify exact user data sent,
- verify minimization,
- verify no unrelated profile/history included.

---

# 58. Tracking Opt-Out Test

Where applicable:

- start with optional tracking disabled,
- inspect network/storage,
- enable,
- inspect,
- disable again,
- verify stopped behavior.

---

# 59. Retention Test

Where retention jobs can safely be tested:

- create expired synthetic record,
- run/observe scheduled cleanup in approved environment,
- verify deletion/anonymization.

Do not run destructive retention jobs against production without authorization.

---

# 60. Logging Test

Trigger representative actions/errors using synthetic data.

Inspect telemetry for unnecessary personal data.

---

# 61. Controlled Validation Summary

| Metric | Count |
|---|---:|
| Privacy tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| PC0 findings | `{}` |
| PC1 findings | `{}` |
| PC2 findings | `{}` |
| Legal-review items | `{}` |

---

# 62. Controlled Validation Exit Gate

Phase 2B passes only when:

- [ ] Critical consent/preference behavior tested where applicable.
- [ ] Account deletion tested.
- [ ] Critical third-party transfer behavior verified.
- [ ] AI processing verified where applicable.
- [ ] Optional tracking behavior tested where applicable.
- [ ] Permission-denial behavior tested where applicable.
- [ ] Logging/privacy behavior sampled.
- [ ] Every FAIL has finding ID.
- [ ] Legal-review items remain explicitly separate.
- [ ] No critical privacy claim is inferred only from policy text.

---

# 63. Finding Register

| Finding ID | Category | Severity | Data / Feature | Summary | Evidence | Legal review? | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `PC-001` | `{}` | `{PC0-PC4}` | `{}` | `{}` | `{}` | `{YES/NO}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 64. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** It requires technical/product review and, where applicable, legal/compliance approval before execution. Nothing below should be described as compliant or fixed until the implementation and relevant validation are completed.

---

# 65. Objective

Design fixes that align:

- actual collection,
- stated purpose,
- user choice,
- storage,
- sharing,
- retention,
- deletion,
- disclosures.

---

# 66. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Legal dependency | Remediation phase |
|---|---|---|---|---|---|
| `PC-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 67. Remediation Principles

| Principle | Application |
|---|---|
| Collect intentionally | Every data element has purpose |
| Minimize | Do not collect/store more than required |
| Respect choice | Preferences must change real behavior |
| Delete honestly | UI promise must match backend reality |
| Disclose reality | Policy and implementation must agree |
| Limit vendor data | Send only what external service needs |
| Separate legal decisions | Do not encode guessed compliance requirements |
| Protect lower environments | Real user data should not spread unnecessarily |
| Verify end-to-end | Privacy control is incomplete until runtime behavior passes |

---

# 68. Remediation Phase Table

| # | Action | Findings closed | Data affected | Code/config | Policy/disclosure impact | Vendor impact | Legal review | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 69. Deletion Remediation Requirements

For deletion fixes document:

- primary records,
- related records,
- files,
- caches,
- search indexes,
- analytics,
- third-party processors,
- backups,
- audit/legal-retention exceptions,
- verification query/process.

---

# 70. Vendor Remediation Requirements

For new/changed vendor data flow document:

- vendor,
- purpose,
- exact fields,
- configuration,
- retention,
- region,
- contract/DPA owner,
- user disclosure impact,
- opt-out/consent dependency where applicable.

---

# 71. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root cause documented.
- [ ] Technical fix defined.
- [ ] Product/policy impact identified.
- [ ] Legal-review dependency identified.
- [ ] Vendor impact identified.
- [ ] Data migration/deletion impact understood.
- [ ] Retest defined.
- [ ] No compliance conclusion is based on unsupported assumption.

---

# FINAL — PRIVACY & COMPLIANCE PRODUCTION READINESS REPORT

# 72. Objective

Produce one technical/privacy readiness decision for the exact audited version.

This report must explicitly distinguish:

- technical privacy readiness,
- product/policy readiness,
- legal/compliance review status.

---

# 73. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Personal data categories identified
`{COUNT}`

### Third-party processors identified
`{COUNT}`

### Critical privacy tests
`{PASS}/{EXECUTED}`

### Open findings
- PC0: `{COUNT}`
- PC1: `{COUNT}`
- PC2: `{COUNT}`
- PC3: `{COUNT}`

### Legal/compliance review items
`{COUNT + SUMMARY}`

### Final technical privacy recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

### Legal compliance status
`{NOT ASSESSED / PARTIAL REVIEW / OWNER-CONFIRMED / COUNSEL-REVIEWED}`

---

# 74. Launch Decision Rules

## 🟢 GO

Use **GO** for the technical privacy audit only when:

- Zero open PC0.
- Zero open PC1.
- Personal data inventory is materially complete.
- Critical data flows are known.
- Optional consent/preferences are technically respected where applicable.
- Privacy disclosures do not materially contradict actual processing.
- Account deletion behavior is verified.
- Critical third-party sharing is known.
- AI-provider data flow is known where applicable.
- Tracking/cookie behavior is known.
- No critical sensitive data leakage in logs.
- Lower environments do not have uncontrolled real personal data.
- No critical privacy unknown remains.

A GO from this audit does **not** equal formal legal compliance unless legal review is separately documented.

## 🟡 CONDITIONAL GO

Use only when:

- Zero PC0.
- Zero launch-blocking PC1.
- Core privacy controls function.
- Remaining issues are bounded PC2 items.
- Product/privacy owner accepts residual risk.
- Legal-review items are explicitly tracked.
- No critical unknown technical processing remains.

## 🔴 NO-GO

Use if:

- Any PC0 remains.
- Material collection is undisclosed.
- Critical optional consent is ignored.
- Account deletion materially misrepresents actual deletion.
- Sensitive data is unnecessarily exposed to third parties.
- AI provider receives materially unexpected personal data.
- Critical tracking cannot be disabled where product/policy requires it.
- Real personal data is uncontrolled in lower environments.
- Privacy policy materially contradicts system behavior.
- Critical data flows remain unknown.

---

# 75. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-PC-01` | Zero open PC0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-PC-02` | Zero launch-blocking PC1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-PC-03` | Personal data inventory complete enough | `{INVENTORY}` | `{PASS/FAIL}` |
| `LG-PC-04` | Critical data flows mapped | `{MAP}` | `{PASS/FAIL}` |
| `LG-PC-05` | Consent/preferences enforced | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-PC-06` | Deletion behavior verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-PC-07` | Third-party sharing known | `{INVENTORY/TESTS}` | `{PASS/FAIL}` |
| `LG-PC-08` | AI data flow known | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-PC-09` | Tracking/storage behavior known | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-PC-10` | No critical sensitive logging | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-PC-11` | Policy materially matches reality | `{MATRIX}` | `{PASS/FAIL}` |
| `LG-PC-12` | No critical technical privacy unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents technical privacy GO.

---

# 76. Legal / Compliance Review Register

| Item ID | Topic | Why legal review required | Technical evidence available | Owner | Status |
|---|---|---|---|---|---|
| `LEGAL-001` | `{TOPIC}` | `{REASON}` | `{EVIDENCE}` | `{OWNER}` | `{OPEN/CLOSED}` |

Examples:

- lawful basis,
- age threshold,
- international transfer mechanism,
- retention requirement,
- consent wording,
- sector-specific regulation,
- records of processing,
- DPIA requirement.

---

# 77. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-PC-001` | `{REF}` | `{PC}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 78. Out-of-Scope / Not Verified

Explicitly list:

- jurisdiction not confirmed,
- legal counsel review not performed,
- vendor contract/DPA unavailable,
- cross-border transfer mechanism not reviewed,
- retention legal basis not reviewed,
- production vendor dashboard unavailable,
- backup deletion not runtime-tested,
- ad-tech/legal consent interpretation excluded,
- formal DPIA not performed,
- sector-specific regulation not reviewed,
- anything intentionally excluded.

Do not convert missing legal evidence into technical PASS.

---

# 79. Final One-Sentence Recommendation

### GO example

> Privacy & Compliance technical recommendation: **GO for production** for `{VERSION}` because all mandatory technical privacy launch gates passed; this does not constitute a legal opinion, and the legal/compliance review status remains `{STATUS}`.

### CONDITIONAL GO example

> Privacy & Compliance technical recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented PC2 risks and completion of the separately listed legal/compliance-owner review items.

### NO-GO example

> Privacy & Compliance technical recommendation: **NO-GO** for `{VERSION}` until findings `{PC-xxx...}` are remediated and the associated consent, deletion, data-flow, third-party, and privacy validation tests pass.

---

# 80. Required Deliverables

A complete Privacy & Compliance Audit should produce:

1. `01_PRIVACY_DISCOVERY_REPORT.md`
2. `02_PRIVACY_STATIC_VERIFICATION_REPORT.md`
3. `03_PRIVACY_CONTROL_TEST_REPORT.md`
4. `04_PRIVACY_REMEDIATION_PLAN.md`
5. `05_PRIVACY_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `PERSONAL_DATA_INVENTORY.md`
- `DATA_FLOW_MAP.md`
- `THIRD_PARTY_PROCESSOR_INVENTORY.md`
- `AI_DATA_PROCESSING_INVENTORY.md`
- `RETENTION_DELETION_MATRIX.md`
- `POLICY_REALITY_COMPARISON.md`
- `LEGAL_REVIEW_REGISTER.md`
- `PRIVACY_FINDINGS.csv`

---

# 81. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not claim legal compliance unless explicit qualified review evidence exists.
3. Do not invent lawful bases, retention periods, age thresholds, or jurisdictional obligations.
4. Separate technical findings from legal interpretation.
5. Do not export unnecessary production personal data.
6. Do not place personal data in audit reports unless strictly necessary and safely minimized.
7. Do not test deletion against real users without explicit authorization.
8. Do not send production personal data to external AI/tools for audit analysis.
9. Inventory actual SDK/network data flows.
10. Verify policy statements against implementation.
11. Verify preferences change actual behavior.
12. Trace account deletion beyond the primary user row.
13. Inspect third-party vendors and AI providers.
14. Inspect analytics/tracking SDK defaults.
15. Inspect logs and error telemetry for personal/sensitive data.
16. Inspect staging/dev environments for real-data leakage.
17. Inspect AI-generated fields, trackers, and prompts for unplanned personal data use.
18. Cite exact paths/configs/endpoints for technical findings.
19. Preserve stable finding IDs.
20. Cross-reference Security, Database, Observability, Functional QA, and Legal review where relevant.
21. Retest privacy controls before marking findings Verified Closed.
22. End with exactly one technical recommendation: **GO, CONDITIONAL GO, or NO-GO**.
23. State legal/compliance review status separately.

---

# 82. Completion Standard

This audit is complete only when an independent reviewer could answer:

- What personal data is collected?
- Why is each important data category collected?
- Where is it stored?
- Which third parties receive it?
- Which AI providers receive user data?
- What permissions/tracking mechanisms exist?
- Are user preferences technically respected?
- What happens when an account is deleted?
- What data remains and why?
- How long is data retained?
- Does the privacy policy match actual behavior?
- Are real users' data present in lower environments?
- Do logs expose inappropriate personal data?
- What privacy controls were actually tested?
- What remains unknown?
- Which items require legal interpretation?
- What remediation is proposed versus verified?
- Can this exact version be launched from a **technical privacy** standpoint?

If those questions cannot be answered from the audit outputs, the audit is not complete.
