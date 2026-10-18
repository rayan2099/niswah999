---
type: decision
status: proposed
area: cycle_tracking
owner: unassigned
reviewed_on:
---

# Cycle prediction model

## Context and sources

A review of the period, ovulation and fertile-window predictions against
Flo's published calculator formulas and documented app behavior found the
core formula right but several application bugs: the next period jumped a
whole cycle on its due day (the comparison used the clock time, not the
date), a late period was silently replaced by next month's date while the
canonical calendar kept drawing the old one on past days, `Duration`-based
day math was off by one around daylight-saving changes, one unlogged
period inflated the average, the fertile window ignored irregularity, and
ovulation was shown for cycles too short for the luteal-phase rule.

Code: [cycle_calculation_service.dart](../lib/features/cycle_tracking/domain/services/cycle_calculation_service.dart),
[cycle_tracking_controller.dart](../lib/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart),
[calendar_days.dart](../lib/core/utils/calendar_days.dart),
[canonical_calendar_screen.dart](../lib/features/cycle_tracking/presentation/screens/canonical_calendar_screen.dart),
[notification_scheduler.dart](../lib/features/notifications/domain/services/notification_scheduler.dart).
Related: [menstrual data integrity contract](menstrual-data-integrity-contract.md).

## Decision and rationale

Proposed, pending owner review:

- **Two numbers, two jobs.** `averageCycleLength` stays the plain factual
  mean of every logged interval (reports show it). Predictions use
  `predictedCycleLength`: intervals outside 15–90 days or at least twice
  the median are left out (almost always a missed log), then the last six
  are averaged with weights 0.8^k, newest first. Spread is the weighted
  standard deviation, floored at 1.5 days and assumed to be 3 days with
  fewer than three qualifying cycles.
- **One prediction everywhere.** The dashboard, calendars, husband report
  and reminders all build from that same length, and reminders now
  include canonical (onboarding) history.
- **Ovulation** = expected next period − 14 days; fertile window =
  ovulation − 5 to + 1. When spread exceeds 2 days the window widens by
  up to 3 days on each side (13 days at most). Not shown for predicted
  cycles under 21 or over 60 days. These follow Flo's published rules.
- **Late periods.** No roll-forward. Past the expected date the next
  period shows as "today" for a tolerance of ceil(1.5 × spread) days
  (capped at 10), then as "late by N days" with no date; the fertile
  window is withheld while late. Predicted calendar days are never drawn
  in the past.
- **Calendar days.** All cycle date math uses `calendar_days.dart`
  (`DateTime(y, m, d + n)` and UTC-date differences), never
  `Duration(days:)` or `.difference().inDays` on local midnights.
- **Episode end date.** `bleeding_episodes.end_date` is the day bleeding
  was recorded as stopped and carries the closing `flow = none`
  observation, so a period's length is `end_date − start_date`, as
  `CycleCalculationService` already counted. The canonical calendar's
  predicted block now uses the same count (it added one extra day).
  If the product intends "When did it stop?" to mean the last day with
  bleeding, both places should change together.

## Impact and verification

Tests: `test/cycle_tracking_controller_test.dart`,
`test/cycle_calculation_service_test.dart`, `test/calendar_days_test.dart`,
`test/canonical_calendar_screen_test.dart`,
`test/services/notification_scheduler_test.dart`. These pass with
`TZ=UTC`, `TZ=Europe/London` and `TZ=America/New_York`; CI runs in UTC,
where the daylight-saving cases cannot fail. Not medically reviewed;
predictions remain planning aids, not contraception or a diagnosis.
