# Reliability & Resilience — Production Readiness Report

**Verdict: 🔴 NO-GO**

## Basis

Two RR1 (High) findings were confirmed by direct code review:

- **RR-001:** No systematic retry/backoff strategy and no connectivity-awareness exist anywhere in the app — a single transient network failure (the normal case for a mobile app, not an edge case) is terminal for that attempt, with no automatic recovery.
- **RR-002:** The app's single uncaught-async-error handler (`runZonedGuarded` in `main.dart`) silently discards every error for the app's entire lifetime via `debugPrint` only, with no crash-reporting or `FlutterError.onError` safety net to compensate — meaning a real production defect, anywhere in the app, at any time, produces zero operational signal.

Per this template's own severity model (§4), unresolved RR1 findings are explicitly defined as **Pre-Launch Blockers**. Per master §45 (Master NO-GO Rules), this also satisfies the cross-cutting criterion "critical production failure would be invisible" independently.

## Relationship to Prior-Wave Findings — This Is Not a New, Isolated Problem

RR-001 and RR-002 are this audit's domain-specific confirmation of `ROOT-005` in the master finding register (the app-wide silent-failure pattern), which is independently corroborated by:
- **DI-002** (Database): confirmed, with real production-incident evidence in migration comments, that DB write/read failures on core health-tracking data were silently swallowed and masked as success.
- **AB-010** (API/Backend): four repositories use four different, non-shared, non-retrying error-handling strategies.
- **CQ-009** (Code Quality): no logging framework exists; errors are swallowed via bare `print()`.
- **DC-004** (Dependencies/Config): the narrower, startup-only framing of the same `runZonedGuarded` mechanism this audit found to be app-wide.

**Five independent audits, working from different evidence, converged on the same underlying defect.** This is the strongest-corroborated systemic issue in the entire audit to date and should be treated as a single root-cause remediation effort (introduce one shared, structured error-handling/logging/retry strategy and a real crash-reporting integration), not five separate patches.

## What Was and Was Not Tested

- **Tested (code-level review):** Full retry/backoff pattern search, `runZonedGuarded` control-flow trace, notification-service guard-and-return pattern, per-feature offline-behavior inventory.
- **NOT tested:** Any live fault-injection (simulated network loss, simulated Supabase outage, simulated platform-permission revocation) — this audit had no device/emulator/network-chaos tooling available. All conclusions above are code-confirmed structural absence (🟧), not observed runtime behavior under fault conditions (🟦, would require controlled testing).

## Conditions for reversing this NO-GO

| Requirement | Owner |
|---|---|
| Introduce a shared, bounded retry/backoff utility for at least the core health-data write paths (cycle tracking, pregnancy tracking) and wire it into the repositories DI-002/AB-010 already flagged | Backend/mobile engineer |
| Replace or supplement the silent `runZonedGuarded` handler with a real crash-reporting integration (Sentry, Firebase Crashlytics, or equivalent) and a `FlutterError.onError` override, so unhandled errors produce at least one operational signal | Mobile engineer |
| Re-test: confirm a simulated transient network failure on a core write path is retried and/or clearly surfaced, not silently dropped | QA / release owner |

## Remediation Plan — **PROPOSED, NOT IMPLEMENTED**

No code was modified during this audit.

- **R1 (RR-001):** Add a small, shared retry-with-backoff helper (e.g., 2–3 attempts, short exponential backoff, jittered) and apply it at minimum to the Supabase write paths already identified as silently swallowing failures (DI-002's `cycle_tracking_repository_impl.dart`, `pregnancy_tracking_repository_impl.dart`, `community_repository_impl.dart`).
- **R2 (RR-002):** Integrate a crash-reporting SDK; add a `FlutterError.onError` override; change the `runZonedGuarded` handler to report (not just `debugPrint`) while preserving its original intent of not crashing the app on the known deep-link edge case.
- **R3 (RR-003):** Have `NotificationService`'s scheduling methods report (via the same new logging/crash-reporting integration) when they no-op due to failed initialization, and wrap `_plugin.*` calls in try/catch that also reports rather than propagates silently.
- **R4 (RR-004):** Make an explicit, documented product decision on offline/degraded-network behavior per feature (which features are local-first, which show a clear "you're offline" state, which queue-and-retry) rather than leaving it as an emergent property of each repository's independent implementation choices.

This remediation plan should be executed as one coordinated effort alongside the Database, API/Backend, and Code Quality audits' overlapping remediation items for `ROOT-005` — see the master finding register's root-cause consolidation.
