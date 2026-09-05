# Observability Audit — Phase 2A/2B Findings & Finding Register

> **Status update (2026-09-05):** This document is the frozen original audit (2026-09-04), preserved as-is for historical reference. `OB-006` is now **VERIFIED_CLOSED** — a full Sentry (`sentry_flutter`) integration is live against a real, owner-provided Sentry project, verified via one controlled real event that reached Sentry's servers with a confirmed event id. Full evidence: `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §16–§18. `OB-003`/`OB-004` (the `dr-niswah-chat` silent-failure paths this document describes) were also fixed as part of `PJ-004`'s remediation — see the same sections.

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app + Supabase backend) |
| Commit | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | 2A Static Verification + 2B Controlled Signal Validation |
| Audit date | 2026-09-04 |
| Report created | `OB_findings.md` |

> **Phase 2B scope note:** No live/staging Supabase project or live Gemini credentials were authorized for this audit (consistent with the master engagement's existing `UNK-001`/`ROOT-001` restriction — resolving that requires "one live smoke-test call" not yet authorized for any Wave). Controlled Signal Validation below is therefore **static/inferential**: each row traces the exact code path a real trigger would execute and reports what signal that code path *would* produce, based on direct code reading rather than an observed live signal. Per template §57/§58, this is marked **INCONCLUSIVE (static-only)** rather than a false PASS, and is listed as a residual unknown in the final report.

---

## Phase 2A — Static Verification Matrix

| Check ID | Category | Scope | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `LOG-01` | Logging | App-wide | Centralized structured logger in use | No `logger`/`logging` package in `pubspec.yaml`; 18 raw `print`/`debugPrint` sites only | **FAIL** |
| `LOG-02` | Logging | App-wide | No critical reliance on console-only output | `main.dart:59` global handler, all repository error logs, all edge-function catches are console-only or nothing | **FAIL** |
| `LOG-03` | Logging | App-wide | Stack trace preserved through catch/rethrow chain | `lib/features/auth/data/repositories/auth_repository_impl.dart` (21 sites) and most other repositories replace the caught exception with `Failure(message)`, discarding the original object/stack | **FAIL** |
| `SILENT-01` | Silent failure | `lib/features/ai_advisor/ai_advisor_service.dart:30` | Catch blocks that swallow errors should at minimum log | `catch (_) { return const GeminiResult(text: '...'); }` — zero logging, zero context | **FAIL** |
| `SILENT-02` | Silent failure | `supabase/functions/dr-niswah-chat/index.ts:269-275` | Provider-call failure should be logged server-side | `catch (_error) { reply = ... }` — no `console.error`, returns HTTP 200 | **FAIL** |
| `SILENT-03` | Silent failure | `supabase/functions/dr-niswah-chat/index.ts:303-308` | Outer exception handler should log before responding | No `console.error`/`console.log` call; exception text goes straight into the HTTP response body only | **FAIL** |
| `SILENT-04` | Silent failure | `lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart:70-81,118-126` | Remote write/read failures on health-tracking data (DI-002 pattern) should be centrally logged, not just `debugPrint`-ed | `debugPrint` only, then silently degrades to local-only data | **FAIL** (confirms DI-002/RR-002 unchanged) |
| `CTX-01` | Context/correlation | App-wide | Critical logs carry a correlation/request ID | None found anywhere in `lib/` or `supabase/functions/` | **FAIL** |
| `CTX-02` | Context/correlation | App-wide | Critical logs carry a user/account identifier | Absent from all repository `print`/`debugPrint` sites (e.g. `cycle_log_repository.dart`) | **FAIL** |
| `REL-01` | Release/version | App-wide | Logs/errors carry release/version/commit | No `package_info_plus` dependency; version never read at runtime | **FAIL** |
| `ERR-01` | Error tracking | App-wide (Dart) | Unhandled exceptions captured to a tool | `runZonedGuarded` → `debugPrint` only, no SDK | **FAIL** |
| `ERR-02` | Error tracking | Native iOS | Native crash capture configured | `ios/Runner/AppDelegate.swift` is an unmodified Flutter template, no Crashlytics/Sentry native init | **FAIL** |
| `ERR-03` | Error tracking | Native Android | Native crash capture configured | `android/app/src/main/kotlin/com/niswah/niswah/MainActivity.kt` is an unmodified Flutter template | **FAIL** |
| `MET-01` | Metrics | App-wide | Golden signals (latency/traffic/errors/saturation) measurable for any critical path | No metrics client anywhere | **FAIL** |
| `ALT-01` | Alerting | App-wide | Any alert exists for a critical condition | No alert-rule config found | **FAIL** |
| `DASH-01` | Dashboards | App-wide | Any application-health dashboard exists | None at app level | **FAIL** |
| `HEALTH-01` | Health checks | `dr-niswah-chat` | Dedicated health/readiness signal independent of real invocations | None — only signal is a real user's own request outcome | **FAIL** (N/A-adjacent, see discovery §13) |
| `INT-01` | Integrations | Gemini (client + server) | Provider request/event ID stored for diagnosis | Not stored on either path | **FAIL** |
| `AUDIT-01` | Audit trail | DB-wide | Durable audit log for business-critical state changes | `grep -rli "audit_log\|audit_trail" supabase/` → 0 matches | **FAIL** |
| `AI-01` | AI-agent-specific §42.1 | App-wide | No console-only diagnostics as sole visibility | Confirmed present (console-only is the *only* mechanism that exists at all) | **FAIL** |
| `AI-02` | AI-agent-specific §42.4 | App-wide | Consistent logging library/style | Three different, inconsistent styles found: `print()` (2 files), `debugPrint()` (3 files), and pure silence (majority of 129 catch sites) — no shared logger | **FAIL** |
| `AI-03` | AI-agent-specific §42.5 | Repository layer | Logged errors include IDs/endpoint/operation context | The 18 existing log lines carry only a static string prefix + raw exception text — no user ID, no record ID, no operation ID | **FAIL** |
| `AI-04` | AI-agent-specific §42.9 | App-wide | No mocked/placeholder monitoring (fake health endpoint, TODO alert config) | Grep for `TODO.*(log\|monitor\|sentry\|crash\|alert)` → 0 matches; no fake instrumentation found — the gap is a genuine absence, not a misleading placeholder | **PASS** (no false-assurance risk from mocked monitoring specifically) |

**Static Verification summary: 22 of 23 checks FAIL.** The single PASS (`AI-04`) is a narrow negative check confirming the team did not create *misleading* placeholder monitoring — it does not offset the near-total absence of real monitoring.

---

## Phase 2B — Controlled Signal Matrix (static/inferential — see scope note above)

| Test ID | Trigger | Expected signal | Required context | Destination | Actual result (traced from code) | Alert? | Evidence | Result |
|---|---|---|---|---|---|---|---|---|
| `OBS-ERR-01` | Uncaught Dart exception anywhere in the app after launch | Crash report with stack, device, OS version | Stack trace, device info, release | Crash dashboard | `runZonedGuarded` catches it, `debugPrint('Unhandled error: $error\n$stack')` — visible only in a locally-attached debug console, invisible in a release build in the field | NO | `lib/main.dart:39-61` | **INCONCLUSIVE (static) → effectively FAIL in production** |
| `OBS-ERR-02` | Native crash (e.g. plugin native code) on a subset of devices | Native crash report | Stack, device model, OS build | Crash dashboard | No native crash SDK; only mitigating factor is Apple/Google's own automatic platform-level crash collection (App Store Connect / Play Console), which exists independent of app code but is unverified as to whether it is reviewed | NO | `ios/Runner/AppDelegate.swift`, `MainActivity.kt` | **INCONCLUSIVE (static) — platform-level fallback unverified** |
| `OBS-INT-01` | Gemini endpoint returns error/wrong shape for `askFiqh()` | Logged provider failure with status/model/latency | Provider name, status code, model | Error tracker / log | `ai_advisor_service.dart:30` `catch (_)` — returns a generic Arabic "couldn't reach sources" string with **zero logging of any kind**, not even `debugPrint` | NO | `lib/features/ai_advisor/ai_advisor_service.dart:14-34` | **FAIL** |
| `OBS-INT-02` | Gemini endpoint returns error/wrong shape for `dr-niswah-chat` (server-side) | Logged provider failure, distinguishable from internal failure | Status code, model attempted, retry count | Supabase function logs | `index.ts:269-275` `catch (_error)` — no `console.error`; response is **HTTP 200** with a generic fallback message; Supabase's own default request-log view would show a normal-looking successful request | NO | `supabase/functions/dr-niswah-chat/index.ts:268-275` | **FAIL** |
| `OBS-INT-03` | `flagged_conversations` insert fails during a red-flag (urgent) message | Logged failure; user still receives the safety banner | Thread ID, user ID, matched categories | Supabase function logs + error tracker | Insert (line 246-254) is inside the *outer* try, not its own guarded block — a failure here is caught only by the generic outer `catch` (line 303-308), which has **no `console.error`** and returns a raw 500 to the client instead of the urgent safety banner. The urgent-banner logic (line 277-281) never executes. | NO | `supabase/functions/dr-niswah-chat/index.ts:246-254, 303-308` | **FAIL — safety-relevant** |
| `OBS-LOG-01` | Remote write fails on `cycle_entries` (DI-002 recurrence) | Logged failure distinguishable from a successful save | User ID, record ID, error category | Log/error tracker | `cycle_tracking_repository_impl.dart:118-126` — `debugPrint` only (stripped/inert in release), then silently falls back to "local save is authoritative" | NO | `lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart:114-127` | **FAIL** |
| `OBS-LOG-02` | Supabase Auth call fails (sign-in/sign-up/reset) | Logged failure with original exception preserved | Original exception type, message, stack | Log/error tracker | `auth_repository_impl.dart` — original `AuthException`/generic exception is converted to a message-only `AuthFailure` and **never logged**; only shown to the user as UI text | NO | `lib/features/auth/data/repositories/auth_repository_impl.dart` (21 catch sites) | **FAIL** |
| `OBS-HEALTH-01` | Supabase becomes unreachable while app is running | Some in-app signal distinguishing "no network" from "backend down" from "app bug" | Dependency-health state | N/A (no dashboard) | No dependency-health concept exists; each feature degrades differently and inconsistently (cross-ref RR-004), none of it logged centrally | NO | Cross-referenced from Reliability audit RR-004 | **FAIL** |
| `OBS-AUDIT-01` | An RLS policy bug (e.g. SEC-004-class) allows cross-user data access | Any anomaly signal (access pattern, unexpected row count, security alert) | User ID, table, policy | Security/audit log | RLS bugs manifest as a **successful** query returning unintended rows — no exception is thrown, so none of the (already largely absent) error-handling paths above are even reachable. No DB-level access/audit logging exists to catch this by any other means. | NO | `supabase/migrations/` (no audit-log tables); architecture review | **FAIL** |

**Controlled Signal Validation summary:**

| Metric | Count |
|---|---:|
| Signal tests planned | 9 |
| Executed (static/inferential — no live triggers) | 9 |
| PASS | 0 |
| FAIL | 8 |
| INCONCLUSIVE (static-only, platform fallback unverified) | 2 (`OBS-ERR-01`, `OBS-ERR-02` — treated as FAIL for launch-decision purposes per template §5 environment-warning rule: "unresolved OB0/OB1 findings are Pre-Launch Blockers" regardless of environment) |
| OB0 findings | 4 |
| OB1 findings | 4 |
| OB2 findings | 4 |

---

## Finding Register

| Finding ID | Category | Severity | Signal / Area | Summary | Evidence | Diagnostic impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `OB-001` | Error tracking | **OB0** | Crash/error capture (Dart + native) | No crash-reporting or error-tracking tool exists at any layer of the app — not in Dart (`pubspec.yaml` has no Sentry/Crashlytics dependency), not in native iOS (`AppDelegate.swift` is a stock template), not in native Android (`MainActivity.kt` is a stock template). A crash on launch for a subset of devices (native or Dart) produces **no team-visible signal whatsoever** beyond whatever Apple/Google's own store-level crash collection happens to surface, if anyone checks it. | `pubspec.yaml`; `ios/Runner/AppDelegate.swift`; `android/app/src/main/kotlin/com/niswah/niswah/MainActivity.kt`; repo-wide grep for Sentry/Crashlytics/FlutterError.onError/PlatformDispatcher = 0 matches | Cannot detect, cannot diagnose | YES | OPEN |
| `OB-002` | Silent failure / Error tracking | **OB0** | App-wide uncaught async errors | `runZonedGuarded`'s handler (`lib/main.dart:59`) is the sole catch-all for every uncaught async exception for the app's entire runtime lifetime (not just startup) and does only `debugPrint`, which is stripped/invisible in release builds. Builds directly on RR-002; from the observability angle this is the single largest blind spot in the app: any bug that manifests as an uncaught async exception anywhere, at any time, produces zero durable signal. | `lib/main.dart:39-61` | Cannot detect, cannot diagnose | YES | OPEN |
| `OB-003` | Silent failure / Integration observability | **OB0** | `dr-niswah-chat` Gemini-call failure path | When the Gemini call fails for any reason (wrong endpoint/shape per `ROOT-001`, network error, rate limit, auth failure), `index.ts:269-275` catches it with **no logging of any kind** and returns **HTTP 200** with a generic Arabic fallback message ("couldn't get a reply, try again"). If `ROOT-001` is real and 100% of AI calls are failing in production right now, this produces **zero anomalous signal anywhere** — not in app logs, not in Supabase's own default request-status logs (which would show a stream of normal 200s), not in any error tracker (none exists). The only way this is discovered is a user complaining that the AI feature "never works." | `supabase/functions/dr-niswah-chat/index.ts:268-275` | Cannot detect at all (not "poorly," literally zero signal) | YES | OPEN |
| `OB-004` | Silent failure / Safety-relevant | **OB0** | `dr-niswah-chat` outer exception handler + urgent red-flag path | The function's outer `catch` (`index.ts:303-308`) never calls `console.error`/`console.log` before returning the exception text as an HTTP 500 body — so even Supabase's platform request logs would show only a bare status code, no diagnostic content, unless the platform separately captures response bodies (unverified). Worse: the `flagged_conversations` insert for **urgent pregnancy red-flag messages** (bleeding, severe pain, reduced fetal movement, etc.) sits inside this same unguarded outer block (`index.ts:246-254`) — if that single insert fails for any reason, the entire request fails, the user receives a raw error instead of the urgent safety banner (`URGENT_BANNER_AR`, lines 59-60, 277-281 never execute), and there is no log trace of what happened or that a safety-critical message went unanswered. | `supabase/functions/dr-niswah-chat/index.ts:246-254, 303-308` | Cannot detect a safety-relevant failure mode at all | YES | OPEN |
| `OB-005` | Silent failure / Integration observability | **OB1** | Client-side AI call sites | `ai_advisor_service.dart:30` (`catch (_) { return const GeminiResult(text: '...'); }`) and multiple `chat_view_model.dart`/`dream_interpreter_view_model.dart` catch blocks convert AI-call failures into either a silent generic fallback string or `errorMessage = error.toString()` shown only in the UI, with no logging at any of these sites. Compounds `OB-003`: even the *client's own* independent Gemini call path (used by the Fiqh Advisor) has no diagnostic trail. | `lib/features/ai_advisor/ai_advisor_service.dart:14-34`; `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` (multiple sites) | Diagnosable only via direct user report + code reading after the fact, not from any log | YES | OPEN |
| `OB-006` | Logging | **OB1** | App-wide logging infrastructure | No logging framework exists (confirms/extends CQ-009). The 18 total `print`/`debugPrint` call sites across 4 files are: (a) invisible in release builds, (b) plain unstructured text with no level/context/correlation ID, (c) inconsistent between `print()` and `debugPrint()` with no shared abstraction. A production incident on `cycle_entries` (the exact DI-002 pattern) produces the same class of non-signal today as it did during the original documented incident — nothing has changed. | `lib/core/services/cycle_log_repository.dart`, `lib/core/services/user_profile_repository.dart`, `lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart`, `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart`, `lib/main.dart` | Severely limited — a recurrence of DI-002 is not detectable in the field | YES | OPEN |
| `OB-007` | Structured logging readiness | **OB2** | Exception-handling architecture (`lib/core/errors/failures.dart`) | The `Failure` exception hierarchy is message-only (`abstract class Failure implements Exception { final String message; }`) with no `code`, `category`, or `context` field. At the large majority of the 129 catch sites across `lib/` (all 21 in `auth_repository_impl.dart` alone), the original exception object and stack trace are discarded and replaced with `throw AuthFailure(error.message)` or equivalent — a plain string. A future logging/error-tracking integration would need to touch nearly every one of these 129 sites to recover diagnosable errors; it cannot simply hook into an existing shape. | `lib/core/errors/failures.dart`; `lib/features/auth/data/repositories/auth_repository_impl.dart` (21 sites, sampled) | Adds significant remediation cost, not itself a launch blocker | NO | OPEN |
| `OB-008` | Metrics / business-event signal | **OB2** | Analytics/telemetry as secondary observability signal | No analytics or telemetry SDK exists anywhere (`firebase_analytics`, `mixpanel_flutter`, `amplitude_flutter`, `posthog_flutter`, Segment — none present). This removes even the weakest possible secondary signal (e.g., "AI messages sent" event volume dropping to zero as an indirect proxy for `OB-003`/`ROOT-001`). | `pubspec.yaml`; repo-wide grep for analytics keywords = 0 matches | No secondary/proxy detection path exists for any critical event | NO (pre-launch), but closes an otherwise-cheap mitigating layer | OPEN |
| `OB-009` | Release/version tagging + kill-switch | **OB1** | Field version visibility, remote disable capability | No `package_info_plus` (or equivalent) dependency exists; the running app version/build is never read or surfaced at runtime anywhere in `lib/`. Combined with the master baseline's confirmed absence of any feature-flag/remote-config system and DC-006's confirmed absence of CI/CD, a broken release (e.g., `ROOT-001`) can only be fixed via a full app-store re-release, cannot be disabled remotely, and — because no version is ever logged anywhere — cannot even be correlated to "did this start after the last release" once any logging *is* eventually added. | Repo-wide grep for `PackageInfo`/`package_info` = 0 matches; grep for feature-flag/remote-config keywords = 0 matches; cross-ref DC-006 | Regressions cannot be isolated to a release; no mitigation without a full re-release | YES | OPEN |
| `OB-010` | Silent failure / Audit trail | **OB1** | RLS policy bugs (cross-references SEC-004) | An RLS policy defect (like the confirmed `SEC-004` `private_messages` issue) manifests as a **successful** query that simply returns or mutates the wrong rows — it throws no exception, so it is invisible to every error-handling and logging path documented in this audit even if all of them worked perfectly. No database-level audit/access logging exists anywhere in `supabase/migrations/` (0 matches for `audit_log`/`audit_trail`) that could independently catch this class of failure. | `supabase/migrations/` (12 files, no audit tables); cross-ref Security audit `SEC-004` | This class of failure is undetectable by any mechanism currently in the system, by design, not by omission | YES | OPEN |
| `OB-011` | Dashboards | **OB2** | Application health visibility | No application-level dashboard of any kind exists. Supabase's own default dashboard-level logs/metrics exist outside this repo but whether they are watched by anyone is explicitly UNKNOWN/NOT VERIFIED — an operational/process question, not a code question, and is not converted into either a PASS or a FAIL per audit rules. | Repo-wide search for dashboard config = 0 matches; §4 of `OB_discovery.md` | No way to visually assess "is the system healthy right now" | NO (pending resolution of the UNKNOWN) | OPEN |
| `OB-012` | AI-agent-specific observability defects | **OB2** | Cross-cutting §42 checklist | Confirmed: (§42.1) console-only diagnostics are the sole visibility mechanism that exists at all; (§42.4) inconsistent logging style across the 18 sites that do log (`print()` in 2 files, `debugPrint()` in 3 files, no shared abstraction); (§42.5) the logs that do exist carry no IDs/endpoint/operation context, just a static string prefix; (§42.9) — checked and *not* found: no misleading placeholder/mocked monitoring exists (a narrow positive). | See Static Verification `AI-01`–`AI-04` above | Adds inconsistency cost on top of the base absence | NO | OPEN |

---

## Phase 2A Static Verification Exit Gate

- [x] Logging quality reviewed — FAIL (no framework, no structure, no context).
- [x] Silent failures reviewed — 4 concrete instances documented at OB0/OB1 severity.
- [x] Correlation reviewed — FAIL, no mechanism exists.
- [x] Release/version tagging reviewed — FAIL, never present.
- [x] Error tracking reviewed — FAIL, absent at every layer (Dart + native iOS + native Android).
- [x] Critical metrics reviewed — FAIL, none exist.
- [x] Alert coverage/quality reviewed — FAIL, no alerts exist to evaluate.
- [x] Dashboards reviewed — FAIL at app level; Supabase default marked UNKNOWN.
- [x] Health checks reviewed — not directly applicable to a mobile client; edge function has no dedicated signal, documented.
- [x] Job/integration observability reviewed — no job infra; integration observability FAIL across all 5 integrations assessed.
- [x] AI-generated observability risks reviewed — §42 checklist run, 4 confirmed defects (`OB-012`) plus one clean check.
- [x] OB0/OB1 candidates have evidence — all 8 OB0/OB1 findings cite exact file/line evidence.

Phase 2A: **COMPLETE.**

## Phase 2B Controlled Signal Exit Gate

- [ ] Critical app/backend errors produce signals — **FAIL**, confirmed statically; not confirmed live (no authorization).
- [ ] Critical provider failures produce signals — **FAIL**, confirmed statically.
- [x] Critical queue/job failures produce signals where applicable — N/A, no queue infrastructure exists.
- [ ] Correlation verified — **FAIL**, no mechanism to verify.
- [ ] Health checks verified — not applicable in the traditional sense; documented as a gap.
- [ ] Critical alerts tested or explicitly blocked — **explicitly blocked**: no alerts exist to test.
- [ ] Release/environment tagging verified — **FAIL**, confirmed absent.
- [x] Every FAIL has a finding ID — yes, all mapped in the Finding Register above.
- [x] No critical observability claim is based only on SDK installation — no SDK exists to make that mistake with; every claim here is based on direct code-path tracing.

Phase 2B is **not fully closeable** in the traditional PASS sense because there is no live environment to validate against — this itself is evidence of a gap, not a neutral outcome, and is carried into the final report as a residual unknown alongside the substantive FAIL findings above.
