# API & Backend Production Readiness Report — Niswah

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app + Supabase backend) |
| Repository | Niswah (local repo) |
| Branch | main |
| Commit / Version | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
| Backend framework | Supabase (Postgres + PostgREST + RLS) + 1 Deno Edge Function (`dr-niswah-chat`) |
| API style | REST (auto-generated) + RPC-style Edge Function |
| Phase | Final — Production Readiness Report |
| Audit date | 2026-09-04 |
| Environment | Local static review only — no live/staging Supabase project, no deployed Edge Function, no real Gemini credentials available to this audit |
| Environment status | 🧪 Controlled (static only) — **Phase 2B Controlled Validation was not performed** |
| Restrictions | Auditor-only mandate: no code modified, no live invocation, no credentials used, no destructive or mutating action taken |
| Report created | `AB_production_readiness_report.md` |

---

## Executive Summary

### System
Niswah — a Flutter mobile app (women's health/pregnancy companion, Arabic-first) backed by Supabase (Postgres + RLS-scoped PostgREST) with one custom Edge Function (`dr-niswah-chat`) that proxies Google's Gemini API server-side for the "طبيبة" pregnancy chat persona.

### Backend version / commit
`13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` (main)

### API surface reviewed
The full `dr-niswah-chat` Edge Function (request handling, auth, validation, red-flag detection, Gemini call, error handling, CORS) and its pure helper (`pregnancy_status.ts`) and test file; the Supabase client bootstrap; and four representative feature data layers (AI-assistant chat, cycle tracking, private messaging, community) plus the client-side direct-to-Gemini integration (`gemini_service.dart`) used by AI Advisor and Dream Interpreter. RLS policies for every table touched by these repositories were read directly from migrations. **Limitation:** no live Supabase project or Gemini credentials were available, so nothing was runtime-executed — every finding below is code-evidenced, not runtime-proven, except where explicitly marked otherwise.

### Critical endpoints tested
0/1 runtime-tested (Phase 2B not performed — no environment). 1/1 critical endpoint (`dr-niswah-chat`) fully statically reviewed.

### Open findings
- AB0: 0
- AB1: 2 (AB-001, AB-002)
- AB2: 6 (AB-003, AB-004, AB-006, AB-007, AB-008, AB-010)
- AB3: 4 (AB-005, AB-009, AB-011, AB-012)
- AB4: 1 (AB-013, observation only)

### Critical unknowns
1. **Whether the Gemini endpoint/shape used throughout the codebase actually works** (AB-001) — this is the single most consequential unknown. If the endpoint is genuinely non-existent as coded, the app's three AI features (Dr. Niswah chat, AI Advisor, Dream Interpreter) are all silently broken in production today, always returning their canned fallback text. This cannot be resolved without one live call against the real Gemini API.
2. Supabase Edge Function platform-level timeout, project-level rate limiting/WAF configuration, and JWT expiry/revocation settings — these are dashboard/project configuration, not repo code, and were not accessible to this audit.
3. `postgrest`/`gotrue`/`http` package (`supabase_flutter: ^2.8.1`) default network-timeout behavior — not independently verified from package source this pass.
4. Actual production usage/cost exposure from the client-embedded Gemini key (AB-002) — technically confirmed extractable, but real-world exploitation likelihood/cost impact was not measured (cross-reference Security audit).

### Final recommendation
🔴 **NO-GO**

---

## Launch Decision Rules Applied

Per the template's rules: NO-GO is required when "Critical API behavior remains unknown." AB-001 is exactly that — a critical unknown with a high-confidence-but-unverified suspicion of total feature failure across all three AI-driven features in the app, and it cannot be downgraded to a PASS or a bounded AB2/AB3 without a single live verification step this audit was not able to perform. Independently, AB-002 (unbounded, uncappable third-party billing exposure from a trivially extractable client-embedded API key, with zero backend mediation for two of three AI features) is itself an AB1 with no safe workaround — it is not a "bounded impact with a safe workaround" issue eligible for CONDITIONAL GO acceptance, because there is no user-facing or operational mitigation available short of the code change proposed in the remediation plan.

Zero AB0s were found — no data corruption, financial duplication (beyond uncapped third-party billing risk, which is AB1 not AB0 in the audit's judgment since it's not a "duplication" mechanism), privilege breach, or catastrophic inconsistency was identified in the reviewed surface. Authentication, authorization, and RLS enforcement were all found sound on static review (see Launch Gate Table). The NO-GO here is driven specifically by AB-001 and AB-002, not by a broad pattern of backend defects.

---

## Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| LG-AB-01 | Zero open AB0 | Finding Register, `AB_findings.md` | PASS |
| LG-AB-02 | Zero launch-blocking AB1 | AB-001, AB-002 both open and both judged launch-blocking | **FAIL** |
| LG-AB-03 | Critical auth/authz verified | AUTHN-01, AUTHZ-01, AUTHZ-02 all PASS by code evidence (JWT re-verification, thread-ownership RLS, service-role-only flagged-conversations table) | PASS (static evidence only — no runtime test performed) |
| LG-AB-04 | Critical validation server-side | RLS/Postgres constraints enforce persistence-layer validation everywhere reviewed; `dr-niswah-chat`'s own request validation is present but under-bounded (AB-006) | PASS with noted gap (AB-006, AB2 — not itself launch-blocking) |
| LG-AB-05 | Critical business rules server-enforced | BR-001 (red-flag detection) PASS; BR-003 (fiqh source-trust filter) is client-only (AB-012), tied to the same root cause as AB-002 | **FAIL** (via AB-002/AB-012) |
| LG-AB-06 | Error/status contract verified | Status codes used correctly (401/400/500) but error envelope can leak internal exception text (AB-007, AB2) | PASS with noted gap |
| LG-AB-07 | Critical idempotency verified | No idempotency key on chat send (AB-003, AB2 — bounded impact: duplicate chat history rows, not financial/security) | PASS with noted gap |
| LG-AB-08 | Webhook safety verified | No webhooks exist in this system | N/A → PASS |
| LG-AB-09 | Timeout/retry behavior verified | Client-side Gemini call has explicit timeouts; server-side Gemini call and all PostgREST calls do not (AB-004, AB-011, both AB2/AB3) | PASS with noted gap |
| LG-AB-10 | Pagination/versioning safe | No server-enforced max page size anywhere, but RLS bounds blast radius to the caller's own data (AB-013, AB4) | PASS with noted gap |
| LG-AB-11 | No critical client/server contract drift | `dr-niswah-chat` request/response envelope matches client expectations exactly; however both server and client independently encode what is likely a **non-existent Gemini provider contract** (AB-001) | **FAIL** |
| LG-AB-12 | No critical unknowns | AB-001 (Gemini endpoint validity) is an unresolved critical unknown by definition — cannot be verified without live access | **FAIL** |

Any mandatory FAIL prevents GO. Four gates FAIL (LG-AB-02, LG-AB-05, LG-AB-11, LG-AB-12), all traceable to AB-001 and AB-002.

---

## Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| RISK-AB-001 | AB-001 | AB1 | Assessed HIGH by this audit (structural hallucination signature), but formally UNKNOWN pending live test | If confirmed: all three AI features (Dr. Niswah chat, AI Advisor, Dream Interpreter) are non-functional in production, always returning fallback text — the app's core differentiator would not work at all | One controlled live call against the real Gemini API to confirm/deny; if confirmed broken, apply remediation R1-a/R1-b before any release | Backend/mobile engineering | **YES** |
| RISK-AB-002 | AB-002 | AB1 | HIGH — the `.env` asset-bundling mechanism confirmed by code; extraction requires only unzipping a shipped app package, no special access | Unbounded third-party (Google Gemini) billing exposure tied to a key any installed-app user can extract; also removes all server-side content-moderation/abuse-prevention capability for 2 of 3 AI features | Move AI Advisor + Dream Interpreter behind a server-side proxy (R1-c); remove `GEMINI_API_KEY` from the client asset bundle | Backend/mobile engineering | **YES** |
| RISK-AB-003 | AB-003 | AB2 | MEDIUM (any client retry on a slow/dropped connection) | Duplicate chat_messages rows — a UX/data-quality issue, not financial/security | Add idempotency key (R2-a) | Backend engineering | Recommended before scale, not launch-blocking on its own |
| RISK-AB-004 / AB-011 | AB-004, AB-011 | AB2/AB3 | MEDIUM | Unbounded hang time on slow network/provider conditions, degraded UX under poor connectivity | Add explicit timeouts (R2-b, R3-a) | Backend/mobile engineering | Recommended before scale |
| RISK-AB-006 | AB-006 | AB2 | LOW-MEDIUM | Unbounded chat message size → storage/cost creep, unclear error UX on malformed input | Add length/shape validation (R2-c) | Backend engineering | Recommended before scale |
| RISK-AB-007 | AB-007 | AB2 | LOW | Minor internal-detail disclosure on error paths | Sanitize error envelope (R2-d) | Backend engineering | Recommended, not launch-blocking |
| RISK-AB-008 | AB-008 | AB2 | MEDIUM (any abusive/compromised authenticated account) | Uncapped Gemini spend via the (now server-mediated) `dr-niswah-chat` path | Add per-user rate limit (R3-c) | Backend engineering | Recommended before scale |
| RISK-AB-010 | AB-010 | AB2 | HIGH (already present in shipped code) | Inconsistent error UX across features; Community feature specifically can show fabricated demo content in place of a real outage, which is materially misleading to users | Unify error mapping, stop Community's outage→fake-data substitution (R2-e) | Mobile engineering | Recommended before scale, arguably launch-relevant for the Community feature specifically given the misleading-content angle |
| RISK-AB-005 / 009 / 012 / 013 | AB-005, AB-009, AB-012, AB-013 | AB3/AB4 | LOW | Hardening/coverage/observability gaps, no direct user-facing harm identified | See remediation plan R3 items | Backend engineering | Backlog acceptable |

---

## Out-of-Scope / Not Verified

- **Phase 2B Controlled Validation was not executed** — no live/staging Supabase project, no deployed Edge Function, no real Gemini API key was made available or authorized for this audit. Every finding in this report is a static code-evidence finding unless explicitly marked 🟥/runtime-confirmed (none are).
- Live confirmation of the Gemini API contract (AB-001) — the single most important open item; explicitly not converted to a PASS or a FAIL, held as a critical unknown.
- Admin/backend-only interfaces — none were found in the reviewed client/repo surface, but a Supabase-dashboard-level admin surface (if any) was not in scope.
- Supabase Storage / file upload endpoints — not located in the four reviewed feature areas; not exhaustively searched repository-wide; explicitly flagged as not verified rather than assumed absent.
- Supabase Realtime channel behavior (reconnect, delivery guarantees, ordering) for private messaging — presence confirmed, internal semantics not independently verified.
- Project-level configuration not visible in source control: JWT expiry/refresh policy, RLS as actually deployed (migrations were read, not diffed against a live `pg_policies` dump), any Supabase-platform rate limiting or WAF, Edge Function wall-clock timeout limit, environment variable values actually set in the deployed project.
- `postgrest`/`gotrue`/`http` package internals for default timeout/retry behavior (`supabase_flutter: ^2.8.1` pinned; package source not read this pass).
- Load/performance/concurrency behavior — out of this audit's scope by template definition (§0.2 Non-goals).
- Security-specific exploitability analysis of AB-002's key-extraction path (e.g. actual reverse-engineering difficulty, whether app builds use any obfuscation) — cross-referenced to the Security audit rather than duplicated here.

Lack of access to the above was **not** converted into a PASS or FAIL anywhere in this report; each is recorded as an explicit unknown.

---

## Final One-Sentence Recommendation

> API & Backend recommendation: **NO-GO** for `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` until findings **AB-001** (unverified, high-suspicion non-functional Gemini integration underlying all three AI features) and **AB-002** (client-embedded, unbounded, unmoderated Gemini API key powering two of those features with zero backend mediation) are resolved — AB-001 via a live verification call and correction if needed, AB-002 via server-side proxying per the remediation plan — and the associated tests in `AB_remediation_plan.md` R1 pass before this backend version is exposed to production users.
