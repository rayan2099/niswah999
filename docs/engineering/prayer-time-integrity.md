# Prayer time integrity

Implementation date: 2026-10-22. Status: implemented on `fix/prayer-time-integrity`; verification below must be read separately from release/deployment status.

Feature navigation: [Prayer Tracking](../../project-hub/generated/feature-prayer_tracking.md).

## Findings addressed

The previous `PrayerTimeCalculator.statusFor` inferred completed at the start instant and missed immediately afterward. Neither conclusion follows from the clock. Unrecorded prayers now stay `pending`, displayed as **Not recorded / لم تُسجّل**, regardless of elapsed time. Only an explicit log sets completed/missed/excused. This deliberately avoids introducing unreviewed prayer-window, qadha or menstrual rulings.

The previous view model silently used Mecca, used MWL everywhere, and converted UTC times into the phone's zone. The dashboard also always labeled the place Makkah. Both screens now require a selected location and known IANA timezone; they display the real location, timezone and chosen calculation convention. Missing, invalid, unconfirmed or unavailable settings show no invented times.

## Implementation

- [Location controller](../../lib/core/preferences/prayer_location_controller.dart): known city presets have named zones. Existing preset coordinates migrate to those zones. Legacy GPS without a known zone needs confirmation. Since 2026-10-28 (device-run item A22, PR #56) a fresh GPS fix is reverse-geocoded with the phone's native geocoder (`geocoding` package) into an English and Arabic city name, and its timezone is the phone's IANA zone, marked confirmed: the fix is where the phone is now, and phones set their zone from the network. A phone with a manually set wrong zone is the accepted risk; the user can still pick a zone, which turns off automatic updates for that location. Settings remain user-scoped and reset between accounts.
- [Schedule builder](../../lib/features/prayer_tracking/domain/services/prayer_schedule_builder.dart): Gregorian date comes from the selected zone, not the host date; timezone rules handle DST. UTC instants are retained for comparisons, including starts after midnight. Log keys remain civil dates so offset-bearing midnight cannot deserialize as yesterday. Unsupported polar conditions fail closed rather than displaying placeholder times.
- [Settings sheet](../../lib/features/prayer_tracking/presentation/widgets/prayer_settings_sheet.dart): city/GPS, searchable IANA zones with Arabic city aliases, MWL/Umm al-Qura/Egyptian/Dubai/ISNA/Karachi and standard/Hanafi Asr selection. The prayer Asr option is separate from menstrual madhhab selection. Existing users retain MWL; the app does not guess a local religious convention from coordinates.
- Umm al-Qura Ramadan Isha requires the user's locally confirmed inclusive final Ramadan date; +30 minutes expires after that date. No inferred lunar dates or permanently enabled annual Ramadan switch. Other methods do not receive that adjustment.
- [View model](../../lib/features/prayer_tracking/presentation/viewmodels/prayer_tracking_view_model.dart): entries are filtered by user and the selected city's current day. A late fetch from an older account cannot overwrite a later fetch. Day/location changes refresh logs; disposed view models ignore late completions.
- [Next prayer calculator](../../lib/features/prayer_tracking/domain/controllers/prayer_time_calculator.dart): returns the earliest upcoming absolute instant, including an explicitly supplied next-day schedule. Without tomorrow it returns null after Isha rather than incorrectly returning today's past Isha.
- [Prayer screen](../../lib/features/prayer_tracking/presentation/screens/prayer_tracking_screen.dart): removes `demo-user` writes, handles failed writes, releases timer/listeners and refreshes on resume. Completion timestamps clear when a log changes away from completed.

## Authority and limits

These are calculated prayer **start times**, not a certified official mosque timetable. The local convention must be chosen and checked against a trusted local timetable before launch. The package documents distinct methods and Ramadan adjustment requirements: [adhan_dart documentation](https://pub.dev/documentation/adhan_dart/latest/), [upstream implementation](https://github.com/prayer-timetable/adhan_dart).

GPS-based locations are refreshed, without a permission prompt, on app start and resume when permission was already granted: if the user moved more than 3 km, the phone's zone changed, or the label is still the generic "Current location", the city and zone are re-resolved. There is no background tracking while the app is closed. A refresh is skipped when the phone's zone is unavailable, and a hand-picked city or zone is never replaced. Legacy "Current location" saves count as GPS-based only while their zone is unconfirmed. Offline geocoding keeps the generic label but still sets the zone. Verification: [device location tests](../../test/prayer_location_device_test.dart) and the onboarding location test; a real-device check on the next TestFlight build is still pending. Timezone rules depend on the packaged tz database and must be updated when civil rules change. No fixed end-of-prayer or menstrual obligation logic has been added. Scholarly review of prayer obligations, interrupted bleeding and qadha remains separate.

Historical `prayer_log.scheduled_time` uses the pre-existing neutral wall-clock wire encoding. This change does not reinterpret old records as true UTC instants or migrate the backend schema; absolute instants are retained in the calculated schedule for comparisons only.

## Verification

See [regression tests](../../test/prayer_time_integrity_test.dart) and [existing prayer tests](../../test/prayer_tracking_test.dart). Numerical fixtures use fixed upstream adhan-js/adhan_dart reference outputs (Raleigh summer/Hanafi ISNA and winter/standard MWL), rather than generating expected values by calling the same library again. Additional tests cover DST, cross-zone date changes, Ramadan expiry, unsupported settings/polar conditions, midnight next prayer, manual log status, late loads, lifecycle cleanup and Arabic settings.

Verified locally with Flutter 3.47.0 / Dart 3.13.0:

- 22 prayer regression tests pass, including 25 exact reference start times across five fixed city/date/convention fixtures and 432 ordered-schedule configurations (6 presets × 6 methods × 12 months).
- The same prayer tests plus the existing DST/day-count/calendar suites pass under `TZ=Europe/London`: 27 tests, no skips. This exercises the four host-DST tests that are conditionally skipped under UTC.
- `dart analyze lib/features/prayer_tracking lib/core/preferences/prayer_location_controller.dart test/prayer_time_integrity_test.dart`: no issues.
- Full `lib` analysis plus the changed tests: zero errors/warnings, 24 pre-existing informational notices outside the prayer changes.
- `python scripts/sync_project_vault.py --check`: passed; generated links valid.

- Final full non-golden regression suite: **1,468 passed, 0 failed, 6 skipped**, across 158 test files, in 3m50s. The exclusion matches CI (`matchesGoldenFile` files). Four skips are host-DST conditions under UTC and pass in the separate London run above; two are pre-existing explicitly disabled tests in `parity_today_stepper_consistency_test.dart`.
- Formatting check for all changed Dart files and `git diff --check`: passed.

Implemented and locally verified does not mean deployed or scholar-approved.
