# Privacy & Compliance — Production Readiness Report

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app, `com.niswah.niswah`, iOS + Android, Supabase backend) |
| Repository | Niswah |
| Branch | main |
| Commit / Version | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f (app version 1.0.0+1) |
| Phase | Final — Production Readiness |
| Audit date | 2026-09-04 |
| Environment | Local static source review (no staging/production runtime access) |
| Jurisdiction(s) identified | UNKNOWN — bilingual EN/AR, GCC/MENA-leaning UI signals; not confirmed by product/legal owner |
| Privacy owner | UNKNOWN |
| Legal review available? | NO |
| Restrictions | Static source review only (Phase 1 + 2A complete). Phase 2B (controlled validation with a synthetic account) **was not executed** — no staging environment or explicit authorization was available. No production Supabase/Google console access. |
| Report created | `PC_production_readiness_report.md` |

---

## 73. Executive Summary

### System
Niswah — a bilingual (EN/AR) menstrual-cycle, pregnancy, and Islamic-fiqh tracking app with AI chat (Google Gemini), private messaging, and a community feature, on a Supabase backend.

### Personal data categories identified
13 (see `PC_discovery.md` §7), including three special-category classes: health data (cycle/pregnancy), religious-practice data (madhhab, fiqh state), and precise geolocation.

### Third-party processors identified
2 confirmed (Supabase — full backend; Google Gemini — AI inference on health/religious/personal content), plus Google Sign-In (OAuth only).

### Critical privacy tests
0 / 0 executed (Phase 2B not run — see restrictions above). All findings below are static-evidence only.

### Open findings
- PC0: **2**
- PC1: **2**
- PC2: **5**
- PC3: **3**
- PC4 (observation): 2 (one closed as no-finding)

### Legal/compliance review items
**8 items** require a named legal/compliance owner before they can be closed: PC-001 (consent adequacy), PC-002 (deletion semantics), PC-003 (AI disclosure wording), PC-004 (policy authorship), PC-006 (export-rights scope), PC-008 (vendor DPAs), PC-009 (age-gate requirement), PC-010 (cross-border transfer mechanism). None of these have been resolved by this audit — they are routed, not answered.

### Final technical privacy recommendation
**🔴 NO-GO**

### Legal compliance status
**NOT ASSESSED** — no legal/compliance owner review has occurred on any item in this report. Nothing in this document should be read as a compliance opinion.

---

## Why NO-GO

Per the launch decision rules (template §74), NO-GO applies when any PC0 remains, when material collection is undisclosed, when critical optional consent is ignored, or when account deletion materially misrepresents actual deletion capability. All four conditions are met simultaneously here:

1. **PC-002 (PC0) — No account-deletion capability exists anywhere in the app.** A user who wants her menstrual, pregnancy, religious-practice, location, message, and AI-chat data deleted has no in-app mechanism to request it, and no support/contact channel was found either. The database schema is correctly built for cascade deletion, but nothing in the client ever triggers it. This is not a degraded deletion experience — it is the complete absence of a fundamental data-subject capability for one of the most sensitive data profiles a consumer app can hold.

2. **PC-001 (PC0) — The only consent mechanism in the app does not function.** The "I agree to Privacy Policy and Terms of Use" checkbox on the sign-in screen is not wired to the sign-up action in any way — a user can create an account and immediately have cycle, pregnancy, religious, and location data collected regardless of whether she checked the box. Combined with the already-confirmed RD-007 (the linked policy text is not tappable and no policy document exists to link to), this app currently has **no functioning consent gate of any kind** in front of special-category data collection.

3. **PC-003 (PC1) — Undisclosed sharing of health/pregnancy context with Google.** Confirmed via two live code paths (server-side edge function and a direct client-to-Gemini fallback, corroborating SEC-001/SEC-006) that pregnancy week/trimester/risk-flag context reaches Google's Gemini API. No screen or document discloses this anywhere in the product.

4. **PC-004 (PC1) — No privacy policy exists at all**, so the audit's required comparison of "what the product says vs. what it does" cannot be performed — there is nothing to compare against. This is the root cause underlying both PC-001 and PC-003 and is the same defect already confirmed cross-domain as RD-007.

These four findings alone are each independently sufficient for NO-GO under the template's rules; together they describe an app that collects and processes some of the most sensitive personal-data categories possible (health, religious belief-adjacent, precise location) with no working consent gate, no disclosed third-party AI sharing, no privacy policy, and no way for a user to get her data deleted.

---

## 75. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| LG-PC-01 | Zero open PC0 | PC-001, PC-002 open | **FAIL** |
| LG-PC-02 | Zero launch-blocking PC1 | PC-003, PC-004 open | **FAIL** |
| LG-PC-03 | Personal data inventory complete enough | `PC_discovery.md` §7 — 13 categories mapped from static review | PASS |
| LG-PC-04 | Critical data flows mapped | `PC_discovery.md` §8 — mapped for all sensitive categories; edge-function server-side forwarding to Gemini not independently verifiable (source not in repo) | PASS (with noted limitation) |
| LG-PC-05 | Consent/preferences enforced | PC-001 | **FAIL** |
| LG-PC-06 | Deletion behavior verified | PC-002 (not verified — because it does not exist) | **FAIL** |
| LG-PC-07 | Third-party sharing known | Supabase + Google Gemini identified; DPA status unknown (PC-008) | PASS for identification / **FAIL** for contractual basis confirmation |
| LG-PC-08 | AI data flow known | PC_discovery.md §18 — flow mapped, but undisclosed to users (PC-003) | PASS for technical mapping / **FAIL** for disclosure |
| LG-PC-09 | Tracking/storage behavior known | No analytics/tracking SDK found; local storage inventoried (§19) | PASS |
| LG-PC-10 | No critical sensitive logging | No logging/crash SDK present to leak data (informational) | PASS |
| LG-PC-11 | Policy materially matches reality | No policy exists (PC-004) — cannot be evaluated as "matching" | **FAIL** |
| LG-PC-12 | No critical technical privacy unknowns | Retention undefined (PC-007), DPA/region unconfirmed (PC-008/PC-010), Phase 2B unexecuted | **FAIL** |

**7 of 12 mandatory gates fail.** Any single mandatory FAIL prevents a technical privacy GO; this many failures, concentrated in consent, deletion, and disclosure, place this build well outside CONDITIONAL GO territory as well — those gaps are not "bounded PC2 items with documented acceptance," they are exactly the launch-blocking PC0/PC1 categories the template reserves for NO-GO.

---

## 76. Legal / Compliance Review Register

| Item ID | Topic | Why legal review required | Technical evidence available | Owner | Status |
|---|---|---|---|---|---|
| LEGAL-001 | Lawful basis / adequacy of consent mechanism for health + religious data | GDPR Art. 9-style regimes (and equivalents) typically require explicit, informed consent for special-category data; whether the fix in R1-2 (remediation plan) is sufficient is a legal question | Consent checkbox does not gate flow (PC-001); no heightened consent step exists | UNKNOWN | OPEN |
| LEGAL-002 | Account-deletion / erasure-right scope and mechanics | Whether hard-delete, grace period, or partial retention (e.g. legal hold) is required, and what must happen to the other participant's shared messages (cross-ref DI-012) | No deletion mechanism exists to evaluate (PC-002) | UNKNOWN | OPEN |
| LEGAL-003 | AI/Gemini sub-processor disclosure and DPA | Sending health/pregnancy context to a third-party LLM provider is a data-sharing arrangement that may require a documented legal basis, DPA, and user disclosure | Data flow confirmed technically (PC-003); no DPA evidence found; no disclosure exists | UNKNOWN | OPEN |
| LEGAL-004 | Supabase subprocessor DPA and hosting region | Primary backend for all personal data categories | No DPA/region evidence found in repo (PC-008, PC-010) | UNKNOWN | OPEN |
| LEGAL-005 | Data export / access-request right scope | Whether a full personal-data export capability is legally required (vs. the current curated-PDF feature) | Current export is partial (PC-006) | UNKNOWN | OPEN |
| LEGAL-006 | Minimum-age requirement | Whether any market this app targets requires an age floor or parental-consent mechanism for a health-tracking app | No age-gate exists (PC-009); no jurisdiction confirmed | UNKNOWN | OPEN |
| LEGAL-007 | Retention periods per data category | No statutory or contractual retention period has been defined for any category, including health/religious data | None defined in product (PC-007) | UNKNOWN | OPEN |
| LEGAL-008 | Cross-border transfer mechanism | If EU/UK/GCC users' data is processed on non-local infrastructure, a transfer mechanism may be required | Region unconfirmed (PC-010) | UNKNOWN | OPEN |

---

## 77. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| RISK-PC-001 | PC-001 | PC0 | Certain (100% of users already affected in current build) | Special-category data collected without a functioning consent gate | R1-1/R1-2 in remediation plan | Product + Legal | **YES** |
| RISK-PC-002 | PC-002 | PC0 | Certain | No user can exercise a right to erasure; regulatory and app-store risk (both major app stores require self-service account deletion) | R1-3 | Engineering + Legal | **YES** |
| RISK-PC-003 | PC-003 | PC1 | Certain | Undisclosed third-party processing of health/pregnancy data | R1-4 (plus R0-1/R0-2) | Product + Legal | **YES** |
| RISK-PC-004 | PC-004 | PC1 | Certain | No policy exists to hold the product accountable to; blocks resolution of PC-001/PC-003 | R0-1 | Legal | **YES** |
| RISK-PC-005 | PC-005 | PC2 | Certain | User expectation mismatch on onboarding step labeled "Privacy" | R2-1 | Product | Recommended, not independently blocking |
| RISK-PC-006 | PC-006 | PC2 | Certain | Partial data-access capability only | R2-2 (pending legal scope) | Product + Legal | Pending legal determination |
| RISK-PC-007 | PC-007 | PC2 | Certain | Indefinite retention of health/religious/location data, including local plaintext caches (cross-ref SEC-007) | R2-3 | Product + Legal | Pending legal determination; location clear-on-logout recommended pre-launch regardless |
| RISK-PC-008 | PC-008 | PC2 | Unknown | Cannot confirm contractual basis for two critical data flows | R0-2 | Legal/Procurement | Recommended before launch |
| RISK-PC-009 | PC-009 | PC2 | Unknown | Possible minors' data risk, unquantified | R3-2 (pending legal) | Legal + Product | Pending legal determination |
| RISK-PC-010 | PC-010 | PC3 | Unknown | Possible unmanaged cross-border transfer | R0-3 | Legal/Infra | Recommended before launch |
| RISK-PC-011 | PC-011 | PC3 | Low | Dormant table, no live exposure confirmed | R3-1 | Product | No |

---

## 78. Out-of-Scope / Not Verified

- Jurisdiction(s) of the user base — not confirmed by product/legal owner.
- Legal counsel review — not performed; nothing in this report is a legal opinion.
- Supabase and Google Gemini vendor contracts/DPAs — unavailable to this audit; existence neither confirmed nor denied.
- Cross-border transfer mechanism — not reviewed (no region data available).
- Statutory/contractual retention basis — not reviewed (no periods defined to review).
- Production Supabase dashboard (region, backup config, storage buckets, auth provider settings) — no access.
- Google Cloud/Gemini API console (data-retention/training-use settings tied to this project's API key) — no access.
- Source of the `dr-niswah-chat` Supabase Edge Function — not present in this repository; its exact data-minimization behavior when forwarding to Gemini could not be independently verified (only the direct-client fallback path was fully inspected).
- Phase 2B controlled validation (consent test, account-deletion test, AI data-transfer test, permission-denial test, retention test, logging test) — **not executed**; no staging environment or synthetic-account authorization was available in this session.
- Backup-retention runtime behavior — not tested (cross-ref BR-006, already flagged in the prior wave as a separate finding).
- Ad-tech/cookie legal interpretation — not applicable (no cookies; mobile app) but also not independently assessed for any web-based marketing surfaces outside this repo's scope.
- Formal DPIA — not performed; not claimed to be unnecessary.
- Sector-specific regulation (e.g., health-data-specific statutes in any particular country) — not reviewed.

Missing legal evidence above is recorded as unresolved, not converted into a technical PASS anywhere in this report.

---

## 79. Final One-Sentence Recommendation

> Privacy & Compliance technical recommendation: **NO-GO** for commit `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` until findings **PC-001** (non-functional consent gate), **PC-002** (no account-deletion capability), **PC-003** (undisclosed AI/Google data sharing), and **PC-004** (no privacy policy exists) are remediated and the associated consent, deletion, and disclosure validation tests pass; legal/compliance review status for this system remains **NOT ASSESSED**, and this report is not a legal-compliance opinion.
