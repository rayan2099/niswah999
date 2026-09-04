# Observability Audit — Phase 1: Discovery

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app + Supabase backend) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | main |
| Commit | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | Discovery |
| Audit date | 2026-09-04 |
| Environment | Local (static repo inspection only — no live Supabase dashboard/project access) |
| Logging platform | None (see §7) |
| Error tracking | None |
| Metrics/APM | None |
| Alerting | None |
| Restrictions | No live/production access authorized; no code changes made; no synthetic traffic sent to the live `dr-niswah-chat` function or live Supabase project (Phase 2B signal tests are therefore static/inferential only — see limitation note in `OB_production_readiness_report.md`) |
| Report created | `OB_discovery.md` |

---

## 1. Prior-wave findings this audit builds on

- Repo-wide search for `Sentry`, `Crashlytics`, `firebase_crashlytics`, `FlutterError.onError`, `PlatformDispatcher.instance.onError` across `lib/` and `pubspec.yaml` — zero matches (independently reconfirmed below, including native iOS/Android layers which prior waves did not check).
- **RR-002**: `lib/main.dart`'s `runZonedGuarded` handler is the app-lifetime catch-all for uncaught async errors; does only `debugPrint`.
- **CQ-009**: No logging framework; 14 `print()` sites in `cycle_log_repository.dart` / `user_profile_repository.dart` swallow Supabase errors.
- **DI-002**: Cycle/pregnancy/community repositories silently swallow remote write/read failures — confirmed root cause of a real, documented past production data-loss incident (haid/cycle logging), discovered by the team through means *other than* their own logging.
- **AB-007**: `dr-niswah-chat` generic catch-all leaks raw exception text to the client.

This audit extends these with: the native (iOS/Android) crash-capture layer, the edge function's *specific* silent-failure branches (not just AB-007's leak), client-side AI call sites, structured-logging readiness, analytics/telemetry, alerting, dashboards, health/readiness signals, version/feature-flag visibility, and RLS-bug detectability.

---

## 2. Observability Stack Inventory

| Component | Tool | Purpose | Environment(s) | Actually active? | Evidence |
|---|---|---|---|---|---|
| Application logger (mobile) | None — raw `print()` / `debugPrint()` only | Ad hoc diagnostic text | Debug builds only | **NO** (stripped/inert in release) | `pubspec.yaml` has no `logging`/`logger` package; grep for `print(`/`debugPrint(` across `lib/` returns only 18 call sites total (see §26) |
| Central log platform | None | — | — | NO | No log-shipping dependency (no `sentry_flutter`, no HTTP log sink, no `firebase_core`) in `pubspec.yaml` |
| Error tracking (mobile, Dart) | None | — | — | NO | No `sentry_flutter`, `firebase_crashlytics`, or equivalent in `pubspec.yaml`; `lib/main.dart`'s `runZonedGuarded` (line 39–61) is the only global handler and only `debugPrint`s |
| Error tracking (mobile, native) | None | — | — | NO | `ios/Runner/AppDelegate.swift` and `android/app/src/main/kotlin/com/niswah/niswah/MainActivity.kt` are unmodified Flutter templates — no Crashlytics/Sentry native SDK, no `FIRCrashlytics`/`Bugsnag` init calls |
| APM / performance monitoring | None | — | — | NO | No APM dependency; no custom trace/span code found |
| Metrics backend | None (app-level) | — | — | NO | No metrics client library |
| Tracing / correlation | None | — | — | NO | No request-ID generation/propagation mechanism found anywhere in `lib/` or `supabase/functions/` |
| Dashboard platform | None (app-level) | — | — | NO | No dashboard config in repo |
| Alerting platform | None | — | — | NO | No alert-rule config, no webhook/PagerDuty/Slack integration code found |
| Uptime / synthetic monitoring | None | — | — | NO | No synthetic-check config found |
| Queue monitoring | N/A | System has no message queue/worker | — | N/A | No queue infra in architecture |
| Database monitoring (app-level) | None in repo | — | — | NO (repo scope) | No DB-monitoring config tracked in repo |
| Cloud/provider logs | **Supabase platform logs (Postgres + Edge Function request logs)** | Default platform-level logging Supabase provides for every project | Production (implied) | **UNKNOWN — not app code, exists by default on the platform, but whether anyone watches it is an operational question outside this repo's scope** | Not inspectable from this repo; treated per master audit rules as partial, non-app-level mitigating factor, marked UNKNOWN/NOT VERIFIED (see §4) |
| Release tracking | None | — | — | NO | No version/build tag attached to any log, error, or exception anywhere; no `package_info_plus` dependency; `pubspec.yaml` version `1.0.0+1` is build metadata only, never read at runtime (`grep -rn "PackageInfo" lib/` → 0 matches) |
| Audit logging (DB) | None | — | — | NO | `grep -rli "audit_log\|audit_trail" supabase/` → 0 matches across all 12 migrations |
| Analytics / business-event telemetry | None | — | — | NO | No `firebase_analytics`, `mixpanel_flutter`, `amplitude_flutter`, `posthog_flutter`, or Segment dependency; no analytics call sites anywhere in `lib/` |
| Feature flags / remote config | None | — | — | NO | No `firebase_remote_config`, LaunchDarkly, GrowthBook, or custom remote-config mechanism; cross-references master baseline's independent finding of the same |

**Conclusion of stack inventory: every app-level observability component is absent.** The only observability surface that exists at all is the Supabase platform's own default logs/metrics, which are outside this repo and outside this audit's ability to verify are being watched.

---

## 3. Critical Event Inventory

| Event ID | Event | Severity | Expected signal | Expected destination | Alert required? | Actually observable today? |
|---|---|---|---|---|---|---|
| `EVT-001` | Gemini API endpoint broken / all AI calls fail | Critical | ERROR + METRIC | Error tracker + alert | YES | **NO** — see OB-003, OB-005 |
| `EVT-002` | RLS policy bug exposes cross-user private data | Critical | AUDIT/ERROR (data-access anomaly) | Security alert | YES | **NO** — no exception is thrown by a leaky-but-successful query; see OB-010 |
| `EVT-003` | Silent DB write failure on `cycle_entries` (DI-002 recurrence) | Critical | ERROR/LOG | Error tracker | YES | **NO** — same code path as the original incident is unchanged; see OB-006 |
| `EVT-004` | App crash on launch (subset of devices) | Critical | Crash report | Crash dashboard | YES | **NO** — no Dart or native crash capture; see OB-001 |
| `EVT-005` | `flagged_conversations` insert fails during a red-flag (urgent pregnancy symptom) message | Critical | ERROR + user-facing safety banner still delivered | Error tracker + alert | YES | **NO** — an unrelated write failure here silently cancels the entire request including the safety banner, with zero server log; see OB-004 |
| `EVT-006` | `dr-niswah-chat` Edge Function 5xx/crash rate spike | High | METRIC + LOG | Supabase function logs (platform-level only) | YES (if platform logs are watched) | **PARTIAL / UNKNOWN** — platform captures status codes by default, but the two failure branches that matter most (OB-003, OB-004) never call `console.error`, and whether anyone watches the dashboard is UNKNOWN |
| `EVT-007` | Startup config load failure (`AppEnvironment.load()`) | Critical | ERROR, visible to user or team | Error tracker | YES | **NO** — caught by `runZonedGuarded`, `debugPrint` only, produces an infinite splash hang (cross-ref DC-004) |
| `EVT-008` | Notification-service init failure | Medium | ERROR/WARN | Log | Desirable | **NO** — cross-ref RR-003; unguarded, would surface via `runZonedGuarded` at best |

---

## 4. Supabase-Platform-Level Observability (assessed separately, per task instructions)

Supabase provides default dashboard-level logs for Postgres query activity and Edge Function invocations (status code, latency, and any `console.log`/`console.error` output) outside of anything tracked in this repository. This is a **real, partial, non-app-level mitigating factor** — but two things limit its usefulness here, both confirmed from code:

1. **The Edge Function's two most important failure branches never call `console.error`/`console.log` at all** (`supabase/functions/dr-niswah-chat/index.ts` lines 269–275 and 303–308 — see OB-003/OB-004). Even a team actively watching the Supabase Logs dashboard would see, at best, a request's status code and latency — not *why* it failed, and in the Gemini-failure case (line 269–275) not even an anomalous status code, since that branch returns **HTTP 200** with a generic fallback message.
2. **Whether anyone on the team actually watches the Supabase dashboard is an operational/process question this repo cannot answer.** Per the task's instruction, this is marked **UNKNOWN / NOT VERIFIED** rather than assumed either PASS or FAIL. No on-call process, runbook, or alert-routing configuration was found anywhere in the repo to suggest it is watched systematically.

---

## 5. Log Inventory

| Attribute | Finding |
|---|---|
| Logger abstraction | None — raw `print()`/`debugPrint()` calls, no wrapper |
| Structured vs plain text | 100% plain text string interpolation, no JSON, no key-value fields |
| Levels (DEBUG/INFO/WARN/ERROR) | None — no level concept exists at all; every call site is an undifferentiated string |
| Timestamps | Not attached by the app (only whatever the OS console/Supabase platform stamps externally) |
| Environment tag | Never attached |
| Service name | Never attached |
| Request/correlation ID | Never generated or attached anywhere in `lib/` |
| User/account ID policy | Inconsistent — some `print()` sites include no identifiers at all (e.g. `cycle_log_repository.dart`), so a specific user's failure cannot be isolated from the sparse logs that do exist |
| Transaction/thread ID | Absent from `lib/` print sites; present only implicitly in the edge function's already-known DB rows (`chat_messages.thread_id`), not in any log statement |
| Source file/module | Only present as an ad hoc string prefix in 3 of 18 call sites (`'[CycleTracking] ...'`, `'[DreamInterpreter] ...'`) — inconsistent, not derived automatically |
| Exception object / stack trace | **Discarded at the majority of the 129 catch sites in `lib/`** — see OB-007. Only `main.dart`'s top-level handler and `cycle_tracking_repository_impl.dart` preserve `$stack`/full error object in the printed string; everywhere else (all 21 `auth_repository_impl.dart` catches, `ai_advisor_service.dart`, `chat_view_model.dart`, etc.) the original exception is replaced by a short string message and the stack trace is lost entirely |
| Release/version | Never attached to any log line anywhere |

---

## 6. Log Level Model

No level model exists (DEBUG/INFO/WARN/ERROR/FATAL are all undifferentiated `print`/`debugPrint`). Notable anti-pattern found: in `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` and `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart`, caught exceptions are converted to `errorMessage = error.toString()` and shown directly in the UI with **no log emitted at all** — the only "signal" is what the user sees on screen, which is lost the moment they navigate away or dismiss it.

---

## 7. Structured Context Inventory

None of the following are present at any of the 18 print/debugPrint call sites or the 129 catch sites: correlation ID, trace ID, service name, environment, version/release, endpoint/job identifier, pseudonymous user ID, order/booking/payment-equivalent ID (e.g. `thread_id`/`cycle_entries.id`), provider event ID (Gemini has none captured either), retry attempt number, or error category/code. The `Failure` class hierarchy (`lib/core/errors/failures.dart`) provides only a `message: String` field — no `code`, no `category`, no `context` map.

---

## 8. Error Tracking Inventory

No SDK exists at any layer (Dart, iOS native, Android native). There is therefore no environment tagging, release tagging, source-map/dSYM symbolication, breadcrumbs, or handled/unhandled exception capture to evaluate — the entire category is a blank.

---

## 9. Metrics Inventory

No technical metrics (request rate, error rate, latency, CPU/memory, DB connections) and no business/operational metrics (cycle-log save success/failure, AI-message success/failure, booking-equivalent creation failure) are instrumented anywhere in `lib/` or `supabase/functions/`.

---

## 10. Trace Inventory / Correlation ID Inventory

No tracing exists. No request/correlation ID is generated at the client, propagated to the edge function, or returned to the client for later correlation. The Client → Edge Function → Postgres → Gemini path (the system's one genuinely multi-hop critical path) has no shared identifier a reviewer or support engineer could use to stitch together what happened for one specific chat turn beyond the DB's own `thread_id`/message row IDs (which are not surfaced in any log).

---

## 11. Alert Inventory

None. No alert-rule configuration of any kind exists in the repository (no PagerDuty/Opsgenie/Slack webhook config, no Supabase alert-policy config file, no in-app threshold logic that triggers any external notification).

---

## 12. Dashboard Inventory

None at the application level. Supabase's own default dashboards exist at the platform level (see §4) but are outside repo scope and their actual usage is UNKNOWN.

---

## 13. Health Check Inventory

Not applicable in the traditional liveness/readiness-endpoint sense (mobile client, not a long-running server). The nearest equivalent — the `dr-niswah-chat` Edge Function — has no dedicated health/readiness route; its only "health signal" is the outcome of a real user invocation, which per OB-003/OB-004 does not reliably surface failure. There is also no in-app dependency-health surface (e.g., no "Supabase unreachable" banner state that is itself observable/reportable).

---

## 14. Background Job Observability Inventory

Not applicable — the system has no queue/worker infrastructure. The closest analogue, `cycle_tracking_repository_impl.dart`'s `syncPendingLogs()` (an eventual-consistency retry-on-next-load mechanism), has no success/failure/duration signal — it either silently succeeds or throws `NetworkFailure` up to whatever UI code called it, unlogged.

---

## 15. Integration Observability Inventory

| Integration | Success visible? | Failure visible? | Latency metric? | Provider request/event ID stored? | Alert? |
|---|---|---|---|---|---|
| Gemini API (client-side, `gemini_service.dart` / `ai_advisor_service.dart`) | NO | **NO** (silent catches, no logging — OB-005) | NO | NO | NO |
| Gemini API (server-side, `dr-niswah-chat/index.ts`) | NO | **NO** (OB-003) | NO | NO | NO |
| Supabase Postgres (via `supabase_flutter`) | NO | Partial — some repositories `debugPrint`, most don't (OB-006) | NO | N/A | NO |
| Supabase Auth | NO | Exceptions converted to generic `AuthFailure` message, original discarded, never logged (OB-007) | NO | N/A | NO |
| `flutter_local_notifications` (device notification scheduling) | NO | Unguarded — failures propagate to `runZonedGuarded` at best (cross-ref RR-003) | NO | N/A | NO |
| `geolocator` (prayer-location) | Not directly assessed this wave | Not directly assessed this wave | NO | N/A | NO |

---

## 16. Audit Trail Inventory

No durable audit trail exists for any business-critical state change (cycle-log edits, profile changes, private-message content changes, community post moderation actions). `grep -rli "audit_log\|audit_trail" supabase/` returns zero matches across all 12 tracked migrations. The `flagged_conversations` table (urgent pregnancy red-flag log) is the closest thing to an audit trail in the schema, and even it can silently fail to be written with zero signal (OB-004) and has no defined retention policy documented in-repo.

---

## 17. Retention Inventory

Not verifiable from this repo — no app-level log/metric/error retention exists to have a policy for. Supabase's own default retention for platform logs is a dashboard/plan-tier setting outside repo scope; marked UNKNOWN/NOT VERIFIED, not assumed sufficient.

---

## 18. Discovery Execution Log

### Fully reviewed
`lib/main.dart` (startup + global error zone), `pubspec.yaml` (full dependency list), `lib/core/services/gemini_service.dart`, `lib/features/ai_advisor/ai_advisor_service.dart`, `lib/core/config/app_environment.dart`, `lib/core/errors/failures.dart`, `supabase/functions/dr-niswah-chat/index.ts` (full file), `ios/Runner/AppDelegate.swift`, `android/app/src/main/kotlin/com/niswah/niswah/MainActivity.kt`, all 18 `print`/`debugPrint` call sites and their surrounding context, `auth_repository_impl.dart` catch-block pattern (21 sites), `community_repository_impl.dart` fallback pattern, `chat_view_model.dart` and `dream_interpreter_view_model.dart` catch patterns.

### Partially reviewed
Remaining ~25 files containing `catch (` blocks (108 of 129 total catch sites) — sampled representatively across auth, cycle tracking, community, private messaging, wellbeing, prayer tracking, and pregnancy tracking repositories; pattern (typed rethrow with message-only `Failure`, or silent local-fallback) confirmed consistent across the sample and cross-referenced against DI-002/CQ-009/AB-010's own file-level findings for the remainder.

### Structurally scanned only
`android/`, `ios/` build configs beyond AppDelegate/MainActivity; `supabase/migrations/*.sql` (scanned for trigger/audit keywords only, not read line-by-line — DB schema itself is Database audit's domain).

### Could not inspect
Live Supabase project dashboard (logs, metrics, alert config) — no credentials/access authorized for this audit. Live `dr-niswah-chat` invocation behavior — no live network calls made (would constitute a production signal test outside this audit's read-only mandate and the master engagement's no-live-call restriction already established by other Wave 1 audits, e.g. AB-001/ROOT-001 marked "requires one live smoke-test call"). App Store Connect / Google Play Console crash-report dashboards — no access.

### Actions performed
| Action | Purpose | Result |
|---|---|---|
| Repo-wide grep for Sentry/Crashlytics/FlutterError.onError/PlatformDispatcher | Confirm prior-wave finding of zero crash tooling | Reconfirmed, zero matches, now also verified at native iOS/Android layer |
| Grep + manual read of all `print(`/`debugPrint(` call sites | Build complete log inventory | 18 sites across 4 files, cataloged in §5–6 |
| Grep + sampled read of all 129 `catch (` blocks across 36 files | Silent-failure audit, structured-context inventory | Confirmed systemic pattern: message-only rethrow or silent local fallback, near-zero logging |
| Full read of `dr-niswah-chat/index.ts` | Assess edge-function-level signal quality | Found two previously-uncited silent-catch branches (OB-003, OB-004) beyond AB-007's raw-leak framing |
| Grep for analytics/feature-flag/version/health-check keywords | Complete stack inventory | Zero matches in every category |

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|
| Sending a live request to `dr-niswah-chat` or the Gemini endpoint | Would generate a real production signal/cost against a live project without authorization; template §45 restricts to staging/synthetic where available, none is |
| Modifying `runZonedGuarded`, adding instrumentation, or touching alert/dashboard config | Template §6/§45 mandatory restriction — read-only inspection during Discovery/Verification |
| Accessing the live Supabase dashboard | No credentials authorized for this audit |

---

## 19. Discovery Exit Gate

- [x] Observability stack mapped — confirmed empty at every app-level layer.
- [x] Critical events identified — 8 events cataloged (§3).
- [x] Logging architecture understood — no architecture exists; ad hoc `print`/`debugPrint` only.
- [x] Error tracking understood — none exists at any layer.
- [x] Metrics identified — none exist.
- [x] Tracing/correlation identified — none exists.
- [x] Alerts inventoried — none exist.
- [x] Dashboards inventoried — none exist app-level; Supabase default dashboards noted as UNKNOWN-if-watched.
- [x] Health checks understood — not applicable to the mobile client in the traditional sense; edge function has no dedicated health signal.
- [x] Job/integration observability mapped — no job infra; integration observability mapped in §15, uniformly absent.
- [x] Unknown blind spots explicitly listed — see §18 "Could not inspect" and the Critical Unknowns section of `OB_production_readiness_report.md`.

Phase 1 Discovery: **COMPLETE.**
