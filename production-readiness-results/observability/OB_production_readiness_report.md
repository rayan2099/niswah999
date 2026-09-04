# Observability — Production Readiness Report

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app + Supabase backend + `dr-niswah-chat` Edge Function) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | main |
| Commit / Version | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | Final — Production Readiness Report |
| Audit date | 2026-09-04 |
| Environment | Local static/code-level audit; no live production or staging access authorized |
| Logging platform | None (app-level) |
| Error tracking | None |
| Metrics/APM | None |
| Alerting | None |
| Restrictions | Read-only inspection only; no live network calls to Gemini or the deployed `dr-niswah-chat` function; no Supabase dashboard access; no configuration/code changes made |
| Report created | `OB_production_readiness_report.md` |

---

## 69. Executive Summary

### System
Niswah — a Flutter mobile app (cycle/pregnancy tracking, community, private messaging, AI-assisted chat/fiqh-advisor/dream-interpreter features) backed by Supabase (Postgres + RLS) and one Supabase Edge Function (`dr-niswah-chat`).

### Version / Commit
`13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` (branch `main`)

### Critical events covered
0 / 8 (see `OB_discovery.md` §3 — every one of the 8 catalogued critical events currently has no reliable detection path)

### Controlled signal tests
0 PASS / 9 executed (static/inferential — no live environment authorized; see `OB_findings.md` Phase 2B scope note)

### Open findings
- OB0: **4**
- OB1: **4**
- OB2: **4**
- OB3: **0**

### Critical unknowns
**3**, summarized:
1. Whether Supabase's own default platform-level dashboard logs/metrics (Postgres + Edge Function) are actually watched by anyone on the team — an operational/process question this repo cannot answer, but material because it is the *only* even-partial mitigating factor identified anywhere in this audit.
2. Whether Apple's/Google's own store-level native-crash collection (App Store Connect / Play Console) is checked by anyone — the only fallback for `OB-001`'s native-crash gap.
3. Whether `ROOT-001` (the Gemini endpoint/request-shape mismatch flagged by Code Quality and API/Backend audits) is actually live-broken right now — if it is, `OB-003` means the team has **zero way of knowing**, which is itself the strongest possible illustration of this audit's core finding.

### Final recommendation
🔴 **NO-GO**

---

## 70. Launch Decision Rationale

Per the template's mandatory rule set (§70): **any open OB0 finding makes GO and CONDITIONAL GO both unavailable.** This audit found four open OB0 findings (`OB-001` through `OB-004`), each independently sufficient to trigger NO-GO on its own:

- `OB-001`: no crash/error-tracking tool exists at any layer (Dart, native iOS, native Android).
- `OB-002`: the app-wide uncaught-async-error handler discards everything via `debugPrint` for the app's entire runtime lifetime.
- `OB-003`: the server-side Gemini-call failure path is completely unlogged and returns HTTP 200, meaning a 100%-AI-failure scenario (the exact scenario `ROOT-001` raises as a live possibility) would produce **zero anomalous signal anywhere in the system**.
- `OB-004`: the same edge function's outer error handler is also unlogged, and — more seriously — an unrelated database write failure on the urgent pregnancy red-flag safety path can silently cancel delivery of the safety banner to a user reporting a genuine medical emergency symptom, with no trace of what happened.

This is not a marginal or borderline call. This audit did not find "logging that's a bit thin" — it found that **every app-level observability channel described in the template (logging, error tracking, metrics, tracing, alerting, dashboards) is completely absent**, confirmed by direct inspection of `pubspec.yaml`, both native platform entry points, the one server-side integration point, and a representative sample covering 100+ of the app's 129 exception-handling sites.

---

## 71. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-OB-01` | Zero open OB0 | 4 open OB0 findings (`OB-001`–`OB-004`) | **FAIL** |
| `LG-OB-02` | Zero launch-blocking OB1 | 4 open OB1 findings (`OB-005`, `OB-006`, `OB-009`, `OB-010`), all marked launch-blocking | **FAIL** |
| `LG-OB-03` | Critical errors captured | No error tracker exists at any layer | **FAIL** |
| `LG-OB-04` | Critical provider failures observable | Gemini failures are silently swallowed on both client and server paths | **FAIL** |
| `LG-OB-05` | Critical jobs/queues observable | N/A — no queue infrastructure in this architecture | **N/A (not a blocker on its own)** |
| `LG-OB-06` | Correlation IDs verified | No correlation-ID mechanism exists anywhere | **FAIL** |
| `LG-OB-07` | Release/environment tagging verified | Never attached to any signal; no runtime version visibility at all | **FAIL** |
| `LG-OB-08` | Critical metrics available | None exist | **FAIL** |
| `LG-OB-09` | Critical alerts actionable | No alerts exist to evaluate | **FAIL** |
| `LG-OB-10` | Health/readiness accurate | No health/readiness concept exists; not fully applicable to a mobile client, but the one server component (`dr-niswah-chat`) has no dedicated health signal either | **FAIL** |
| `LG-OB-11` | No critical silent failures | 4 confirmed critical silent-failure paths (`OB-002`, `OB-003`, `OB-004`, and the RLS-blindness described in `OB-010`) | **FAIL** |
| `LG-OB-12` | No critical unknowns | 3 open critical unknowns (§69 above) | **FAIL** |

**11 of 12 mandatory gates FAIL. Any single mandatory FAIL prevents GO or CONDITIONAL GO per template §70.**

---

## 72. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-OB-001` | `OB-001` | OB0 | High (any nontrivial user base will hit some crash) | A crash on a subset of devices at launch produces zero team-visible signal; only discoverable via user reviews/support tickets, if at all | Add Sentry (or equivalent) at Dart + native layers per remediation R1-1/R1-2 | Mobile lead | **YES** |
| `RISK-OB-002` | `OB-002` | OB0 | High | Any uncaught async bug anywhere in the app, for the app's entire life, produces zero signal | Wire `FlutterError.onError`/`PlatformDispatcher.instance.onError` to a real reporting sink per R1-1 | Mobile lead | **YES** |
| `RISK-OB-003` | `OB-003` | OB0 | **Confirmed possibly already true today** — `ROOT-001` flags the Gemini endpoint/shape as likely broken right now, unresolved | If true, 100% of AI features are silently dead in production with zero detection | Add server-side logging per R1-3; resolve `ROOT-001` via live smoke test (Code Quality/API-Backend's remit, not this audit's) | Backend lead | **YES** |
| `RISK-OB-004` | `OB-004` | OB0 | Low-to-medium frequency, but **high-severity when it occurs** (safety-critical) | A user in a genuine pregnancy emergency (bleeding, severe pain, etc.) could receive a raw error instead of the urgent safety banner, with zero record of it happening | Decouple urgent-flag insert from the Gemini-reply path and log both independently per R1-3 | Backend lead | **YES** |
| `RISK-OB-005` | `OB-005` | OB1 | High | Fiqh Advisor / Dream Interpreter AI failures are invisible client-side as well as server-side | Structured logging at client AI call sites per R2-1 | Mobile lead | **YES** |
| `RISK-OB-006` | `OB-006` | OB1 | **Confirmed already materialized once** (DI-002's documented past incident) | A recurrence of the exact same silent cycle-data-loss incident would again go undetected by the team's own tooling | Structured logging rollout per R2-1, starting with the exact repositories implicated in DI-002 | Mobile lead | **YES** |
| `RISK-OB-007` | `OB-009` | OB1 | Medium | No way to disable a broken AI feature without a full app-store release cycle; no way to know which app version a user experiencing an issue is running | Add version tagging (R2-3) and a minimal kill-switch (R2-4) | Mobile + backend leads | **YES** |
| `RISK-OB-008` | `OB-010` | OB1 | Depends on whether `SEC-004`-class RLS bugs exist elsewhere (Security audit's remit) | An RLS bug of this class is, by design of the current system, undetectable by any observability mechanism, current or currently-planned, other than a user noticing their own data is wrong | DB-level audit logging on sensitive tables per R3-3 (secondary layer only — does not replace the actual RLS fix) | Backend lead + Security | **YES** (detection layer), coupled to Security's own fix |
| `RISK-OB-009` | `OB-007` | OB2 | N/A (architectural) | Increases cost/time to make R1's error tracker fully useful once installed | Extend `Failure` hierarchy per R2-2 | Mobile lead | Acceptable to defer, but should follow shortly after R1 |
| `RISK-OB-010` | `OB-008`, `OB-011`, `OB-012` | OB2 | N/A | Secondary/defense-in-depth gaps | R3-1, R3-2, remediation-plan-driven consistency cleanup | Mobile + backend leads | Acceptable to defer past initial launch-blocking remediation |

---

## 73. Out-of-Scope / Not Verified

Explicitly not verified by this audit (do not treat as either PASS or FAIL):

- Production Supabase dashboard logs/metrics/alert configuration — no access authorized.
- Whether the Supabase project's default logs are actually reviewed by anyone (process question, not code).
- Whether App Store Connect / Play Console native crash reports are reviewed by anyone (process question, not code).
- Live behavior of the `dr-niswah-chat` function and the Gemini endpoint under a real request — no live call made; this audit traced code paths only. Resolving `ROOT-001` itself (whether the Gemini integration is actually broken) is explicitly the responsibility of the Code Quality/API-Backend audits' flagged live smoke test, not this audit.
- Cloud/infrastructure-level metrics (Supabase's underlying hosting infrastructure) — excluded, outside repo scope.
- Distributed tracing — not available, not assessed beyond confirming its absence.
- SIEM/security monitoring — excluded per template §33 non-goals; cross-reference Security audit.
- Long-term log/metric/audit retention policy — not verifiable, no app-level retention exists to have a policy for; Supabase's own retention settings are a dashboard/plan-tier matter outside this repo.
- Backup/disaster-recovery observability — excluded, cross-reference Backup/Recovery audit.

---

## 74. Answering the Task's Four Production Scenarios

**Would anyone find out, and how fast, if each of these happened in production right now?**

1. **The Gemini API endpoint is broken and 100% of AI-feature calls fail (`ROOT-001`).** No one would find out from any system signal. The server-side call (`dr-niswah-chat/index.ts:269-275`) silently falls back to a generic "try again" message and returns **HTTP 200** — even Supabase's own default request-status logs would show a stream of normal-looking successful requests. The client-side Fiqh Advisor path (`ai_advisor_service.dart:30`) is equally silent. **The only way this is discovered is a user complaining that the AI feature "never works" — and given the graceful, plausible-sounding fallback text on both paths, many users may simply assume the feature is just unhelpful rather than broken, further delaying discovery.**

2. **A new RLS policy bug lets users see each other's private data.** No one would find out from any system signal. This class of bug produces a *successful*, correctly-formed query response — no exception is thrown, so none of the app's error-handling paths (however deficient) are even reachable. No database-level audit or access logging exists anywhere in the schema to independently flag anomalous access patterns. **Discovery is entirely dependent on an affected user noticing and reporting it, or a future manual security audit — there is no automated path at all.**

3. **A silent DB write failure recurs on `cycle_entries` (the exact DI-002 incident repeating).** No one would find out from any system signal, because the code path that caused the original incident is materially unchanged: `cycle_tracking_repository_impl.dart` still only `debugPrint`s (invisible in release builds) before falling back to "local save is authoritative." **This is the most concerning answer of the four, because it is not hypothetical — it is a confirmed repeat of an incident that has already happened once, was not caught by the team's own tooling then, and would not be caught by it now either.**

4. **The app crashes on launch for a subset of devices.** No one on the team would find out from any in-app or in-repo mechanism — there is no crash-reporting SDK at the Dart layer or either native layer. The only possible signal is Apple's/Google's own automatic store-level crash collection (App Store Connect / Play Console), which exists independent of this codebase but whose actual review by the team is an unverified operational question. **Absent someone actively checking those store dashboards, discovery again depends entirely on user reviews/uninstalls/support contact.**

**Common thread across all four:** in every scenario, the honest answer is that discovery depends on a user noticing and reporting the problem (or, for scenario 4, a store dashboard someone may or may not be checking) — not on anything this system does automatically. This is the concrete, scenario-level meaning of the OB0 findings above.

---

## 75. Final One-Sentence Recommendation

> Observability recommendation: **NO-GO** for `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` until findings `OB-001`, `OB-002`, `OB-003`, and `OB-004` are remediated and the associated crash-capture, error-tracking, server-side logging, and safety-path-decoupling changes are implemented and their signals verified against a live/staging environment — because at present, none of the four production failure scenarios the team is most exposed to (a dead AI integration, a data-exposure RLS bug, a recurrence of the already-documented cycle-data silent-loss incident, or a launch crash) would produce any signal the team could act on, and discovery in every case currently depends entirely on a user noticing and reporting it.
