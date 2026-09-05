# Reliability & Resilience Audit — Discovery & Findings

> **Status update (2026-09-05):** This document is the frozen original audit (2026-09-04), preserved as-is for historical reference. `RR-001`'s live remediation status has since progressed materially and is tracked in `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §15–§17 (current status: `PARTIALLY_REMEDIATED`, one remaining gap) — check there, not this file, for current status.

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app |
| Commit | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f, branch main |
| Phase | 2A — Static Verification only |
| Audit date | 2026-09-04 |
| Note on methodology | Performed directly by the lead auditor after the delegated Wave-2 sub-agent hit a session-wide rate limit before writing output. No live fault-injection, no device, no network-chaos testing — all findings are code-level resilience-pattern review (Static/Documentation tier). |

Evidence key: 🟧 Confirmed by code · 🟨 Likely · 🟦 Requires controlled/live fault-injection test · ⬜ N/A

---

## RR-001 — No systematic retry/backoff strategy anywhere in the app; a single transient network failure is terminal for that attempt

- **Severity:** RR1 (High)
- **Location:** App-wide. Repo-wide search for `backoff`/`maxRetries`/`retryCount`/`exponential` across all of `lib/` returns **zero matches** outside `GeminiService`'s narrow two-model fallback loop (which retries a *different model*, not the same request, and only on 429/500/503 — not a general-purpose retry utility). No shared retry/backoff helper exists; no repository reviewed in this or prior audits implements one independently either (cross-reference AB-010, which found four different, none-retrying error-handling strategies across the data layer).
- **Also confirmed:** No connectivity-awareness package (`connectivity_plus` or equivalent) is present in `pubspec.yaml` — the app has no proactive way to distinguish "the device is offline" from "the request failed for some other reason," so every screen's error handling is reactive-only (catch the exception after the fact), never predictive (warn before attempting, or queue until connectivity returns).
- **Production impact:** Any transient failure — a brief cell-network handoff, a momentary Supabase blip, a DNS hiccup — is treated identically to a permanent failure: the operation fails once, and (per the pattern documented across DI-002, AB-010, and this audit's own findings below) either silently degrades to cached/local/fake data or surfaces a raw error to the user, with no automatic second attempt. For a mobile app, where transient connectivity loss is the *normal*, expected case (not an edge case), this is a materially higher-than-typical reliability gap.
- **Confidence:** 🟧 Confirmed by exhaustive grep (absence).
- **Launch-blocker status:** **YES** — per this template's RR1 definition ("core workflow fails unsafely, cannot recover predictably"), the combination of no retry logic anywhere plus (per DI-002) silent failure absorption on core health-tracking writes means a common, everyday network hiccup can result in **permanently unrecorded health data with no automatic recovery attempt and no visible indication to the user that recovery is even needed.**
- **Status:** OPEN

---

## RR-002 — App-wide uncaught-async-error handler silently discards every error, for the app's entire lifetime, not just at startup

- **Severity:** RR1 (High) — escalated from the Dependencies/Config audit's DC-004 (which scoped this to "startup config failure only") after re-reading `main.dart`'s own code comment, which confirms the mechanism's actual scope is app-wide.
- **Location:** `lib/main.dart:34-61` (`runZonedGuarded`).
- **Evidence:** 🟧 The handler is:
  ```dart
  (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
  }
  ```
  and the surrounding comment explicitly states its purpose is to catch *"a deep link with a stale/reused/invalid Supabase auth code ... [that] throws an uncaught AuthApiException from inside supabase_flutter's own internal deeplink handling"* — a runtime event that can occur **at any point in the app's life**, not only during the ten startup `await` calls. Because `runZonedGuarded` wraps the entire `main()` execution including `runApp(const NiswahApp())`, this single handler is the catch-all for **every** uncaught asynchronous exception anywhere in the app, for its entire session lifetime — not a startup-scoped guard.
- **Compounding factor — no crash reporting exists to compensate:** Repo-wide search for `Sentry`, `Crashlytics`, `firebase_crashlytics`, `FlutterError.onError`, and `PlatformDispatcher.instance.onError` across `lib/` and `pubspec.yaml` returns **zero matches**. There is no secondary safety net (crash-reporting SDK, custom `FlutterError.onError` override for framework/widget-build errors) that would otherwise partially compensate for the zone handler's silence. `debugPrint` is stripped/no-op in release builds by Flutter tooling convention and is not connected to any log-aggregation system.
- **Production impact:** A genuine, unanticipated bug anywhere in the app — not just the one deep-link scenario the guard was written for — surfaces to the development team as **nothing at all**: no crash report, no log entry visible in production, no analytics event. The only signal is a user complaint, if one occurs and is actually escalated. This directly undermines the ability to detect regressions post-launch (cross-reference Observability audit, Wave 3) and materially weakens confidence in every other audit's "no defect found" conclusions, since a real defect occurring only under conditions this audit didn't trace (a race, a platform-specific edge case, a data shape this audit didn't consider) would be invisible in production even if it started happening on day one.
- **Confidence:** 🟧 Confirmed by code + explicit comment.
- **Launch-blocker status:** **YES** — matches this template's RR1 definition directly ("cannot recover predictably" combined with total operational blindness to failure).
- **Status:** OPEN
- **Cross-reference:** DC-004 (Dependencies/Config, narrower framing of the same code), FQ-002 (Functional QA, same finding from a different angle), Observability audit (Wave 3, primary owner of the "is failure detectable" question).

---

## RR-003 — Notification scheduling silently no-ops if initialization failed, and underlying plugin calls are unguarded

- **Severity:** RR2 (Medium)
- **Location:** `lib/core/services/notification_service.dart` — `showNow`, `scheduleAt`, `scheduleDaily`, `cancel` (all four public scheduling methods).
- **Evidence:** 🟧 Every method begins `if (!_initialized) return;` — if `initialize()` (itself awaited during startup, and itself capable of throwing from its platform-channel calls) did not complete successfully, every later call to schedule or cancel a cycle/pregnancy/wellbeing/chat-safety reminder becomes a **silent no-op**: no exception, no log, no return value indicating failure. Additionally, none of the four methods wrap their `_plugin.*` call in a `try`/`catch` — if the underlying `flutter_local_notifications` platform call throws at runtime (e.g., a notification-permission revocation mid-session on Android 13+, or a platform-imposed scheduling-count limit), that exception propagates uncaught to whatever call site invoked it, which — per RR-002 — likely terminates in the silent app-wide zone handler if invoked from a fire-and-forget context (several call sites, e.g. `NotificationRefreshCoordinator.refresh(...)` in `main.dart`'s post-frame callback, are not awaited/error-handled by their caller either).
- **Production impact:** A user could have every cycle/prayer/wellbeing reminder silently stop firing — for the specific, narrow case of `initialize()` having failed (itself only plausible if a preceding failure in the same silently-swallowed startup chain occurred), or a platform-level permission/limit issue — with zero indication anywhere in the app that this happened. For a health-reminder feature, silent total failure is a meaningful trust/functionality gap.
- **Confidence:** 🟧 Confirmed by code (both the guard-and-return pattern and the absence of internal try/catch).
- **Launch-blocker status:** NO independently — RR2, bounded to the specific precondition of a prior initialization failure or platform-level denial; but compounds RR-002's severity assessment.
- **Status:** OPEN

---

## RR-004 — No offline/degraded-network product experience beyond what individual repositories happen to implement ad hoc

- **Severity:** RR2 (Medium)
- **Assessment:** Offline behavior is **inconsistent by accident, not by design**, because no app-wide offline/connectivity strategy exists (see RR-001). Specifically:
  - **Cycle tracking (`CycleTrackingRepositoryImpl`)** is confirmed local-first by deliberate design (per DI-002/Code-Quality evidence) — this is a genuine positive for offline usability of the app's core feature, though the silent-failure aspect of that same design is RR-001/DI-002's concern, not repeated here.
  - **Pregnancy tracking** similarly local-first (same DI-002 evidence).
  - **Community, private messaging, AI chat, dream interpreter** have **no offline mode at all** — they are network-dependent by nature (server-stored UGC, real-time messaging, a remote LLM), and this audit found no queued-write/offline-draft mechanism for any of them (e.g., no "your message will send when you're back online" affordance; a failed send in these features is just an error, full stop, per the `errorMessage = error.toString()` pattern confirmed across `community_feed_view_model.dart`, `chat_view_model.dart`, `private_messaging_repository.dart` call sites).
  - **Private messaging demo-mode fallback (CQ-007, cross-referenced):** already flagged by Code Quality as a distinct, more severe issue (fabricated conversations shown on any null-auth state) — not re-scored here, but noted as the most severe manifestation of "no coherent offline/degraded-auth strategy" in the app.
- **Production impact:** A user losing connectivity mid-session gets a materially different (and undocumented-as-intentional) experience depending on which screen they're on — some features keep working via local-first data, others show a raw error, one (private messaging) can show fabricated content. This inconsistency is itself a reliability/UX-coherence risk, independent of any single feature's individual behavior being "acceptable" in isolation.
- **Confidence:** 🟧 (per-feature evidence, several already independently confirmed by prior audits); the "is this experienced as jarring/inconsistent by real users" conclusion is 🟨 inference.
- **Launch-blocker status:** NO independently — RR2, explicit-acceptance-eligible, but strongly recommend a single documented offline/degraded-network product decision rather than three-plus different ad hoc behaviors.
- **Status:** OPEN

---

## Positive controls confirmed (not findings)

- **GEO-01 PASS:** `PrayerLocationController` (`lib/core/preferences/prayer_location_controller.dart`) is a genuine, well-designed resilience pattern: `useDeviceLocation()` throws distinct typed exceptions (`LocationServiceDisabled`, `LocationPermissionDenied`) specifically so callers can show real, distinguishable messages, and `resolved` always returns a sensible non-null default (Mecca) rather than crashing or leaving prayer times uncomputed when no location has ever been chosen. The code's own comment explicitly documents this as a deliberate fix for a prior "old flat hardcoded clock times" bug — a genuine example of the team correctly hardening a previously-fragile path.
- **RETRY-01 PASS (narrow, already noted by API/Backend audit):** `GeminiService.generateText` does implement bounded, status-code-gated retry across a two-model fallback list (retries only on 429/500/503, gives up after both models tried) — the one place in the app with any retry logic at all, though it does not use backoff/jitter and is scoped to just this one service.
- **RED-FLAG-01 PASS (already noted by API/Backend audit):** Red-flag/urgent-symptom detection in the Dr. Niswah chat path (`DrNiswahRedFlags.matches`) runs and displays its banner independently of whether the underlying Gemini call succeeds or fails, on both the backend-proxied and direct-model code paths (confirmed in `chat_view_model.dart:_sendViaDrNiswahBackend` and `_sendViaDirectModel`) — a genuinely safety-conscious design where the most clinically important signal is not gated behind the least reliable dependency.

---

## Findings Summary

| Finding ID | Severity | Launch blocker? | Status |
|---|---|---|---|
| RR-001 | RR1 | **YES** | OPEN |
| RR-002 | RR1 | **YES** | OPEN |
| RR-003 | RR2 | NO | OPEN |
| RR-004 | RR2 | NO | OPEN |

Two RR1 (High, pre-launch-blocker-class per this template's own severity model) findings were confirmed by code. Both are systemic (app-wide), not confined to one feature, and both compound findings already raised by other Wave 1/2 audits (DI-002, AB-010, DC-004, FQ-002, CQ-009) rather than introducing an unrelated concern — they are best understood as this audit's domain-specific view of `ROOT-005` in the master finding register (the app-wide silent-failure pattern), not a new root cause.
