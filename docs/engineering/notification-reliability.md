# Notification reliability review — 2026-10-21

Status: implemented in `fix/notification-reliability`; verification recorded below. Not deployed. This work depends on the prayer-time integrity changes in PR #34. It does not certify OS delivery, medical predictions, or scholarly approval.

Follow-up: [app-wide notifications](app-wide-notifications.md) adds incoming activity, destinations and controls; it supersedes the four-fixed-slot budget below with six fixed slots (61 total). Deployment and verification statuses are recorded separately there.

Navigation: [notifications feature map](../../project-hub/generated/feature-notifications.md), [prayer-time integrity](prayer-time-integrity.md).

## Findings and changes

- Android scheduled notification and reboot receivers were absent from the app manifest. Added both receivers and boot permission, following the installed flutter_local_notifications 22.3.0 integration contract. iOS now assigns the notification center delegate when the implicit Flutter engine initializes.
- Prayer preferences previously had no scheduler. An explicit opt-in now schedules five days of the five daily prayers using the confirmed location, IANA timezone, calculation method, Asr setting and applicable Ramadan adjustment. Missing/unconfirmed/unsupported schedules create no guessed reminder. Newly initialized prayer preferences default off; existing explicit preferences remain respected.
- Non-prayer lead sliders previously did not change actual reminder times. The UI now persists and applies clock-time controls for tracking, cycle, pregnancy/nifas and wellbeing. Prayer retains its real event lead control. Prayer settings are reachable from notification settings.
- Permission checking covers both Android and iOS. Explicit denial blocks scheduling and appears in settings; an unavailable query remains unknown. Returning from phone settings rechecks permission. Enabling persists intent before the permission dialog, and reconciliation waits for its result.
- Serialized native mutations and generation guards stop delayed refreshes, permission results and account changes from restoring disabled reminders. Sign-out clears pending taps and invalidates work immediately. Failed account cleanup prevents new scheduling until cleanup succeeds. Direct authenticated-account replacement also invalidates old work. Delayed urgent-chat replies and failures retain the sending session generation and cannot create alerts/feed entries for a subsequent session.
- Local opt-outs reconcile before network reads. Independent refresh stages prevent a failed data source from suppressing unrelated reminder types. Repository read failures retain previously scheduled tracking reminders rather than inventing a closed episode. Pending reminders from a replaced episode are swept before creating the next window. A failed pending-request read or stale-request cancellation blocks replacement tracking schedules until cleanup can be retried; unrelated reminder types continue. Cancellation audit entries retain the episode that owned the removed request.
- Unknown device timezone refuses wall-clock scheduling. Known named-zone dates preserve calendar arithmetic across DST; daily initial scheduling advances by calendar date rather than 24 hours. Prayer instants use the selected place's zone independently of the device zone. Out-of-order timezone responses cannot overwrite a newer scheduling zone or repopulate the shared device-zone cache with an older result.
- Preference and feed writes capture their account key before awaits, serialize updates, and reject stale loads. Invalid saved preferences fail closed for the affected type; corrupt opt-outs cannot silently become default-on. Audit writes serialize and deduplicate retries.
- Lock-screen titles/bodies are discreet, including urgent chat alerts. Android requests private visibility. Sensitive chat and tracking details remain in the authenticated app. Notification payloads contain routing identifiers rather than health content.
- CI now runs on all pull requests, including stacked branches, so native compile jobs are eligible before the dependency merges.

## Scheduling budget and behavior

The rolling prayer plan owns IDs 200–224 (at most 25 requests). Tracking owns at most 30 daily check-ins. Four fixed cycle, pregnancy, nifas and wellbeing slots bring the conservative planner total to 59, below the iOS 64 pending-request ceiling. Low numeric IDs are reserved away from tracking hashes. Existing urgent chat alerts are immediate, rather than pending scheduled requests.

Opening/resuming Niswah refreshes the plans. Prayer reminders extend five local calendar days and active tracking extends thirty local days. A device that never reopens Niswah eventually exhausts these windows; this is an explicit product limit, not indefinite background scheduling. Wellbeing repeats daily. Changing prayer configuration or app language refreshes scheduling while the home shell is active.

Android uses `inexactAllowWhileIdle`. The system may delay reminders; these are not guaranteed exact adhan alarms. Acceptance from the plugin means the platform accepted scheduling, not that the user saw or heard the notification. The in-app feed records accepted schedules and makes entries visible when due; it is not a delivery receipt. No prayer obligation, exemption or fiqh ruling is inferred by the reminder scheduler.

## Source and regression evidence

- [Native wrapper](../../lib/core/services/notification_service.dart), [refresh coordinator](../../lib/features/notifications/domain/services/notification_refresh_coordinator.dart), [prayer planner](../../lib/features/notifications/domain/services/prayer_reminder_scheduler.dart), [tracking planners](../../lib/features/notifications/domain/services/notification_scheduler.dart).
- [Settings view model](../../lib/features/notifications/presentation/viewmodels/notification_settings_view_model.dart), [preference repository](../../lib/features/notifications/data/repositories/notification_repository_impl.dart), [feed persistence](../../lib/core/preferences/notification_log_controller.dart), [auth transitions](../../lib/core/auth/auth_controller.dart).
- [Platform/race regression tests](../../test/notification_reliability_test.dart), [real iOS plugin permission path](../../test/notification_ios_permissions_test.dart), [settings races](../../test/notification_settings_race_test.dart), [real account replacement](../../test/notification_account_transition_test.dart), [delayed chat account safety](../../test/notification_chat_account_safety_test.dart), [prayer numerical fixtures](../../test/prayer_reminder_scheduler_test.dart), [platform harness](../../test/support/notification_platform_harness.dart), [timezone response race](../../test/notification_timezone_race_test.dart).
- Numerical prayer reminder fixtures check Makkah Fajr and Raleigh Hanafi Asr/Fajr with a fifteen-minute lead; a New York DST window checks five local dates and unique bounded slots. Platform tests exercise the real plugin Dart channel API with synthetic OS responses; they are not physical-device delivery tests.

## Verification results

Final source verification on 2026-10-21, Flutter 3.47.0 / Dart 3.13.0:

- Full non-golden suite: **1,496 passed, 0 failed, 6 skipped**, across 165 test files. Two skips are pre-existing disabled parity cases; four require a DST host zone.
- The four DST-dependent cases ran under `Europe/London`: **5 passed, 0 skipped** across their two files.
- Notification continuity/repository clock matrix: **213 passed per zone** under UTC, Asia/Riyadh, Asia/Kolkata, Australia/Lord_Howe, Pacific/Kiritimati, America/Los_Angeles and Pacific/Pago_Pago.
- Changed notification/auth/timezone/chat code and new regression tests: **no analyzer issues**. Whole `lib` retains its existing **24 info-level notices**, with no errors or warnings.
- Existing acceptance-tooling Python tests: **13 passed**. App/server pregnancy parity: **21/21 vectors match**.
- Android manifest XML parses; native integration-contract tests pass. Project-vault generation/check and `git diff --check` pass.
- Native Android/iOS compile CI is requested through the draft PR and must be reviewed separately. No physical-device delivery test or signed release was performed here.

Golden image comparisons were excluded using the repository CI policy (`matchesGoldenFile`); these tests do not establish screen-pixel parity. All new tests use synthetic accounts, clocks, preferences and mocked platform/network responses.

## Remaining release verification

Physical Android and iPhone checks remain required: notification permission allowed/denied/regranted; foreground, background and terminated app; Android reboot and package update; timezone travel and DST; Focus/Do Not Disturb and battery restrictions; sign-out/account switch; tap opening and stale-account payload; schedule renewal after the five-day prayer window. Confirm discreet content on locked devices and that app/OS settings tell the same story. Native compile CI is separate from these delivery checks. No claim of 100% delivery or release readiness is made by mocked platform tests.
