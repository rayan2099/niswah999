# Performance Audit — Discovery & Findings

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app |
| Commit | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f, branch main |
| Phase | 2A — Static Verification only |
| Audit date | 2026-09-04 |
| Note on methodology | Performed directly by the lead auditor after the delegated Wave-2 sub-agent hit a session-wide rate limit before writing output. **No live device/emulator/profiler was available** — every finding here is code-pattern-level risk assessment (Static/Documentation tier), not a measured performance number. Do not read any finding below as a benchmark result. |

Evidence key: 🟧 Confirmed by code · 🟨 Likely · 🟦 Requires live profiling · ⬜ N/A

---

## PF-001 — Ten sequential, unparallelized `await` calls block the first frame at startup

- **Severity:** PF2 (Medium) — a real, code-confirmed cold-start latency risk, bounded by the fact that none of the awaited operations appear to make a blocking network round-trip to a third party (see caveats below).
- **Location:** `lib/main.dart:39-53` (inside `runZonedGuarded`, before `runApp()`).
- **Evidence:** 🟧 The startup sequence is fully sequential:
  ```dart
  await dotenv.load();
  await AppEnvironment.load();
  await NiswahSupabase.initialize();
  AuthController.instance.init();
  await AppLocaleController.instance.load();
  await AppThemeController.instance.load();
  await MaritalStatusController.instance.load();
  await MadhhabController.instance.load();
  await PrayerLocationController.instance.load();
  await NotificationLogController.instance.load();
  await NotificationService.instance.initialize();
  runApp(const NiswahApp());
  ```
  Six of these (`AppLocaleController`, `AppThemeController`, `MaritalStatusController`, `MadhhabController`, `PrayerLocationController`, `NotificationLogController`) are independent `SharedPreferences`-backed loads with no dependency on each other — each is individually cheap (a handful of key reads), but awaiting them one-by-one rather than via `Future.wait([...])` means their latencies sum instead of overlapping. `NotificationService.instance.initialize()` (see PF-002) is the most expensive single step and runs *last*, after everything else has already completed sequentially.
- **Production impact:** Slower cold start than necessary; the app shows its native splash screen for the sum of all ten steps' latency rather than the maximum of the parallelizable ones. Individually each step is likely small (tens of milliseconds for a `SharedPreferences` read), so the cumulative effect is probably noticeable-but-not-severe on a mid-range device — this is an inference (🟨), not a measurement.
- **Confidence:** 🟧 Sequencing confirmed by code; actual wall-clock cost is 🟦 UNKNOWN (requires live profiling — not possible in this audit).
- **Launch-blocker status:** NO — PF2, explicit-acceptance-eligible.
- **Remediation category:** Parallelize the six independent `SharedPreferences`-backed loads via `Future.wait`; consider deferring `NotificationService.initialize()`'s Android-channel-creation platform-channel round-trip to after first frame (`WidgetsBinding.instance.addPostFrameCallback`) since it has no bearing on what the first frame renders.

---

## PF-002 — Full IANA timezone database loaded synchronously on the startup critical path

- **Severity:** PF2 (Medium)
- **Location:** `lib/core/services/notification_service.dart:29` (`tz_data.initializeTimeZones()`), called from `initialize()`, which is the last of the ten sequential startup awaits in `main.dart`.
- **Evidence:** 🟧 `tz_data.initializeTimeZones()` (the `timezone` package's "load every zone" entry point, as opposed to a lazier subset) is called unconditionally at every app launch, followed by a plugin `initialize()` platform-channel call and an Android notification-channel-creation platform-channel call — three non-trivial operations, all awaited sequentially, all before `runApp()`.
- **Production impact:** Adds startup latency that has no bearing on the first rendered frame (notification scheduling is not needed until the home shell is reached and `_refreshNotifications()` runs — see `main.dart`'s `NiswahHomeShell.initState`, which already re-triggers scheduling on a post-frame callback separately). This work is currently front-loaded before the user sees anything, rather than deferred to after first paint.
- **Confidence:** 🟧 code-confirmed sequencing; wall-clock cost 🟦 UNKNOWN.
- **Launch-blocker status:** NO.
- **Remediation category:** Move `NotificationService.instance.initialize()` to a post-first-frame callback (the app already re-derives what to schedule on resume via `NotificationRefreshCoordinator`, so a brief delay before notification scheduling is "warm" is low-risk).

---

## PF-003 — PDF report generation is not offloaded from the UI isolate

- **Severity:** PF2 (Medium)
- **Location:** `lib/features/doctor_report/presentation/pdf/doctor_report_pdf_builder.dart`, `husband_report_pdf_builder.dart`, `fiqh_report_pdf_builder.dart`, `wellbeing_report_pdf_builder.dart` (~500-630 lines each).
- **Evidence:** 🟧 Repo-wide search for `compute(` / `Isolate.` across all four PDF-builder files and their calling screens returns **zero matches** — PDF construction (layout, font shaping/embedding for 3 custom font families across multiple weights, page composition) runs entirely on the main/UI isolate. All four screens use the `printing` package's `PdfPreview(build: (format) => _generate(...), ...)` pattern, which invokes the synchronous builder function directly rather than via an isolate boundary.
- **Production impact:** For a multi-page report with embedded custom fonts, PDF construction is CPU-bound work that, if it takes more than ~16ms, will cause dropped frames / visible jank on the triggering screen while the document is built — `printing`'s `PdfPreview` does show its own `loadingWidget` during this window (confirmed present in all four screens per a positive-control note below), which mitigates the *user-facing* symptom (a loading indicator is shown, not a frozen UI with no feedback) but does not eliminate the underlying main-isolate blocking.
- **Confidence:** 🟧 (absence of isolate offloading is code-confirmed); actual jank severity 🟦 UNKNOWN (device- and report-size-dependent, requires live profiling).
- **Launch-blocker status:** NO.
- **Remediation category:** Offload PDF generation via `compute()` (the `pdf` package's `Document.build()` output is a `Uint8List`, which is isolate-transferable) if report sizes grow or user complaints arise; not urgent given the existing loading-state mitigation.

---

## Positive controls confirmed (not findings)

- **LIST-01 PASS:** The main community feed (`community_board_screen.dart:288-483`) uses `CustomScrollView` + `SliverList.separated`/`SliverList.list` — properly virtualized, not a bare unbounded `ListView(children:[...])`. The one bare `ListView(...)` found in the codebase (`community_category_chip_bar.dart:25`) is a small, bounded-length horizontal category-chip bar, not a performance risk. Chat and private-messaging screens (`dr_niswah_chat_screen.dart`, `conversations_screen.dart`, `chat_detail_screen.dart`) all confirmed using `ListView.builder`/`.separated`.
- **IMG-01 PASS:** Repo-wide search for `Image.network(` across `lib/` returns **zero matches** — no remote-image-without-caching anti-pattern exists, because the app currently has no remote-image content surface at all (bundled assets only: logo, fonts). Note this as an N/A-by-absence rather than a verified-good caching strategy — if a future feature adds user-uploaded images (e.g. to community posts), this should be re-audited then.
- **HTTP-01 PASS:** Only one `http.Client()` instantiation exists in the entire codebase (`gemini_service.dart:35`, held as a singleton), avoiding the "new client per request" connection-reuse anti-pattern. All Supabase network calls go through the `supabase_flutter` package's own internally-managed client.

---

## Findings Summary

| Finding ID | Severity | Launch blocker? | Status |
|---|---|---|---|
| PF-001 | PF2 | NO | OPEN |
| PF-002 | PF2 | NO | OPEN |
| PF-003 | PF2 | NO | OPEN |

No PF0/PF1 finding was identified. **This verdict is bounded by the complete absence of live profiling in this audit** — see the production readiness report for the explicit unknown this creates.
