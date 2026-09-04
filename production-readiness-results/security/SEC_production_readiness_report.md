# 05 — Security Production Readiness Report — Niswah

## 70. Executive Summary

### System
Niswah — Flutter mobile app (women's health: menstrual/fiqh cycle tracking, pregnancy tracking, prayer tracking, community, private messaging, AI chat, dream interpretation, PDF reports), backed by Supabase (Postgres + RLS + Edge Functions).

### Version / Commit
`1.0.0+1`, commit `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f`, branch `main`.

### Security tests
0/0 — **Phase 2B (Controlled Security Validation) was not performed.** No staging/runtime access was available; all findings below are static-evidence (🟧 Confirmed by Code/Config) unless explicitly marked UNKNOWN. This is itself a gate-relevant gap, not a clean bill of health — see §74.

### Open findings

| Severity | Count | IDs |
|---|---:|---|
| SEC0 — Critical | 1 | SEC-001 |
| SEC1 — High | 2 | SEC-003, SEC-004 |
| SEC2 — Medium | 3 | SEC-002, SEC-005, SEC-006 |
| SEC3 — Low | 2 | SEC-007, SEC-009 |
| SEC4 — Observation | 1 | SEC-008 |

### Critical unknowns
2 (SEC-010: live migration-application state on the production Supabase project; SEC-011: live Supabase dashboard configuration — Auth rate limits, redirect-URL allow-list, Realtime RLS toggle, service-role key scoping).

### Final recommendation
🔴 **NO-GO**

---

## 71. Launch Decision Rationale

Per the template's Launch Decision Rules (§71):

- 🔴 **NO-GO** is mandatory if "Any SEC0 remains," "Sensitive secret is exposed," or "Critical security behavior remains unknown." **All three conditions are currently true:**
  1. **SEC-001 (SEC0 — Critical)** is open: the live `GEMINI_API_KEY` is bundled directly into the compiled app binary via `pubspec.yaml`'s `flutter: assets: - .env`, and three of the app's four AI features call Google's Generative Language API directly from the client with this key and no server-side authorization/rate-limit gate. This is a direct, currently-open secret exposure — the exact condition the template names as an automatic NO-GO trigger, independent of any other finding.
  2. Two **SEC1 — High** findings are also open and independently qualify as pre-launch blockers: **SEC-003** (Android release build signed with the debug keystore — a release-integrity/store-submission blocker) and **SEC-004** (the `private_messages` "mark as read" RLS policy is not column-scoped, letting a message recipient rewrite another party's message content/sender within their own conversation).
  3. **SEC-010** and **SEC-011** are unresolved critical unknowns — this audit had no access to the live Supabase project or dashboard, so whether the declared RLS/migration state is actually the *enforced* live state, and whether dashboard-only Auth protections (rate limiting, redirect allow-list, leaked-password protection) are correctly configured, could not be confirmed. The template is explicit: "Do not convert missing access into PASS."

No combination of the Medium/Low findings changes this outcome — the SEC0 alone is sufficient for NO-GO per the template's rules, and would remain so even if every other finding were already remediated.

---

## 72. Security Launch Gates

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-SEC-01` | Zero open SEC0 | SEC-001 open | **FAIL** |
| `LG-SEC-02` | Zero launch-blocking SEC1 | SEC-003, SEC-004 open | **FAIL** |
| `LG-SEC-03` | Authentication verified | Delegated to Supabase Auth (`supabase_flutter`); code-level flow reviewed and sound; live dashboard config unverified (SEC-011) | PASS (code-level) / gated by SEC-011 for full confidence |
| `LG-SEC-04` | Authorization verified | RLS declared/implemented correctly on every reviewed table except `private_messages` UPDATE (SEC-004); direct-Gemini paths (SEC-001) have no Niswah-side authorization boundary at all | **FAIL** (SEC-001, SEC-004) |
| `LG-SEC-05` | Object/tenant isolation verified | Per-user `auth.uid()` scoping confirmed via static RLS review across all user-data tables; live enforcement unverified (SEC-010) | PASS (code-level) / gated by SEC-010 |
| `LG-SEC-06` | Session/token handling verified | Delegated entirely to `supabase_flutter` defaults; no custom session logic found (positive) | PASS (code-level) |
| `LG-SEC-07` | Secrets handled safely | `GEMINI_API_KEY` bundled client-side (SEC-001); `SUPABASE_SERVICE_ROLE_KEY` correctly server-only per static review; no hardcoded secrets found in source | **FAIL** (SEC-001) |
| `LG-SEC-08` | Input/injection controls verified | Structured query builder used throughout; DB-level CHECK constraints present; one low-severity raw-filter pattern noted (SEC-009, RLS-backstopped) | PASS |
| `LG-SEC-09` | Upload controls safe | No upload surface exists in the audited app (PDFs generated/shared locally only) | N/A / PASS |
| `LG-SEC-10` | Webhook/payment trust verified | No webhook or payment surface found in-scope | N/A |
| `LG-SEC-11` | Production config has no security bypass | Android release signed with debug key (SEC-003); no minification/ProGuard found | **FAIL** (SEC-003) |
| `LG-SEC-12` | No critical unknowns | SEC-010, SEC-011 open | **FAIL** |

**Any mandatory FAIL prevents GO.** Six of twelve gates fail outright (`LG-SEC-01`, `02`, `04`, `07`, `11`, `12`). This is a decisive NO-GO, not a borderline case.

---

## 73. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Accepted? |
|---|---|---|---|---|---|---|---|
| RISK-SEC-001 | SEC-001 | SEC0 | High (deterministic — any app-package extraction reveals the key) | Unbounded Gemini API cost/quota abuse; feature outage if key is suspended | R1.1 (route all AI calls server-side) | Release owner | **NO — must be remediated pre-launch, not accepted** |
| RISK-SEC-002 | SEC-003 | SEC1 | High (already the current build config) | Release/update-integrity compromise; likely store-submission blocker | R1.2 (proper release signing) | Release owner | **NO — must be remediated pre-launch, not accepted** |
| RISK-SEC-003 | SEC-004 | SEC1 | Medium (requires a participant to act maliciously within their own conversation) | Private-message content tampering | R1.3 (column-scope the RLS policy) | Release owner | **NO — must be remediated pre-launch, not accepted** |
| RISK-SEC-004 | SEC-002 | SEC2 | Low direct risk; contributes to SEC-001 going unnoticed | False assurance in future reviews | R1.1 (cleanup alongside) | Release owner | Pending owner decision |
| RISK-SEC-005 | SEC-005 | SEC2 | Medium | Elevated AI cost from a single abusive authenticated user | R2.1 | Release owner | Pending owner decision |
| RISK-SEC-006 | SEC-006 | SEC2 | Low (narrow trigger condition today) | Health-context leak to third party on fallback path; audit-log gap | Closes automatically with R1.1 | Release owner | Pending owner decision |
| RISK-SEC-007 | SEC-007 | SEC3 | Low (requires local device compromise) | Local health-data-at-rest exposure | R2.2 | Release owner | Pending owner decision |
| RISK-SEC-008 | SEC-009 | SEC3 | Very low (RLS-backstopped) | Fragile query pattern | R2.3 | Release owner | Pending owner decision |
| RISK-SEC-009 | SEC-010, SEC-011 | Unknown (treat as high until verified) | N/A | Cannot confirm declared controls are actually enforced live | R0 verification actions | Release owner | **NO — must be verified pre-launch, not accepted as unknown** |

> An AI auditor cannot accept security risk on behalf of the release owner. Every "Accepted?" decision above requires an explicit, named human sign-off before this app proceeds to production, regardless of this report's own NO-GO recommendation.

---

## 74. Out-of-Scope / Not Verified

- **Production penetration testing** was not performed (no live environment access).
- **Phase 2B Controlled Security Validation** (§46-§62 of the template) was not performed — no synthetic-user IDOR tests, no live rate-limit bursts, no live auth negative tests were executed. All findings are static-evidence only.
- **Live Supabase dashboard/project internals** were not accessible (see SEC-010, SEC-011) — Auth provider configuration, actual applied migration state, Realtime RLS toggle, and live secret scoping are unverified.
- **APK/IPA build and extraction** was not performed — SEC-001's exploitability is assessed from the deterministic, well-documented behavior of `flutter: assets:` bundling, not from a physically extracted binary (per the audit's "do not perform destructive actions" / read-only constraint; building and extracting a release artifact was judged unnecessary to establish this finding with high confidence, since the mechanism is unambiguous).
- **`src/` (React/Vite web reference app)** was reviewed only for shared-credential overlap with the mobile app (confirmed: shares the same root `.env`, including `GEMINI_API_KEY`, and independently calls Gemini directly from `DreamInterpreter.tsx`/`NiswahAI.tsx`) — per prior project instruction it is a design reference, not the audited production surface, and is not scored or remediated here.
- **Native binary / compiled-app static analysis** (e.g., MobSF-style APK scanning, string-extraction from an actual build artifact) was not performed.
- **Dependency/package vulnerability scanning** (`pub outdated`, CVE database cross-check) was not independently performed as part of this security audit — cross-reference the dedicated Dependencies audit per the template's §40 instruction.
- **Formal compliance certification** (HIPAA, GDPR, or regional health-data-specific regulatory review) is excluded — note that this app processes health data (menstrual cycle, pregnancy status) for what appears to be an international/Arabic-speaking user base; a dedicated privacy/compliance audit is strongly recommended given the sensitivity of the data categories involved, separate from this technical security audit.
- **Social-engineering and denial-of-service testing** were excluded per the template's mandatory safety rules.
- **Supabase Auth provider internals** (Google OAuth app configuration, phone/SMS OTP provider configuration) were not independently reviewed beyond the client-side integration code.

Do not convert any of the above into a PASS. Each remains an open item requiring either dashboard access, a build artifact, or a dedicated follow-up audit before it can be marked verified.

---

## 75. Final One-Sentence Recommendation

> Security recommendation: **NO-GO** for `1.0.0+1` until findings `SEC-001, SEC-003, SEC-004` are remediated (per `SEC_remediation_plan.md`, action items R1.1–R1.3) and the associated controlled security regression tests pass, and until the critical unknowns `SEC-010, SEC-011` are resolved through live Supabase project/dashboard verification.

---

## Answering the Completion Standard (§78)

- **Attack surface:** Mapped in `SEC_discovery.md` §6-§15 — Flutter client, Supabase (Postgres/Auth/Realtime/Edge Functions), and direct client→Google Gemini calls (the latter being the core problem).
- **Trust boundaries:** Client↔Supabase is RLS-enforced and, with the exception of SEC-004, sound. Client↔Google (direct path) has **no trust boundary at all** — this is the central finding of this audit.
- **Authentication:** Fully delegated to Supabase Auth via `supabase_flutter`; no custom logic found; sound at the code level, unverified at the live-config level (SEC-011).
- **Authorization:** Enforced via Postgres RLS, `auth.uid()`-scoped, verified table-by-table across every migration; one column-scoping gap found (SEC-004).
- **Ownership/tenant boundaries:** Single-tenant consumer app; per-row user ownership is the isolation unit, and it is RLS-enforced everywhere except the SEC-004 gap.
- **Sessions/tokens:** Standard `supabase_flutter` session persistence/refresh; no custom, and therefore no custom risk, found.
- **Secrets:** `SUPABASE_SERVICE_ROLE_KEY` correctly server-side only (static review); `GEMINI_API_KEY` is **not** safely handled (SEC-001) — this is the report's headline finding.
- **Critical inputs:** Validated via DB CHECK constraints and structured query builders; no injection surface found.
- **Injection/XSS/CSRF/CORS/SSRF:** Reviewed; N/A or PASS across the board except a low-severity, RLS-backstopped raw-filter pattern (SEC-009) and an acceptable wildcard-CORS observation (SEC-008).
- **Uploads:** No upload surface exists in this release candidate.
- **Sensitive APIs:** PostgREST tables are RLS-gated; the `dr-niswah-chat` edge function correctly validates JWTs; the direct-Gemini paths have no Niswah-side gate whatsoever.
- **Abuse-protected endpoints:** The edge function lacks rate limiting (SEC-005); the direct-Gemini paths are entirely unprotected by definition (SEC-001).
- **Webhooks/payment callbacks:** None exist in-scope.
- **Debug/test bypass in production:** Yes — the Android release build is debug-signed (SEC-003).
- **Security tests actually executed:** None (Phase 2B not performed) — all findings are static/code evidence.
- **What remains unknown:** Live Supabase project migration/config state (SEC-010, SEC-011), full extent of exploitability without a physically extracted release artifact.
- **Remediation proposed vs. verified:** A full remediation plan is proposed in `SEC_remediation_plan.md`; **nothing has been implemented or verified** as part of this audit.
- **Critical/high blockers open:** Yes — SEC-001 (Critical), SEC-003 and SEC-004 (High).
- **Can this release proceed to production from a security standpoint:** **No.**
