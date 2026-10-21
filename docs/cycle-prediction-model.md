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

- **Her stated estimate as a starting point.** The onboarding
  `cycle_baselines` row (`USER_REPORTED_ESTIMATE`) informs predictions
  but never becomes a statistic: `averageCycleLength`, `cycleLengths` and
  `averagePeriodLength` stay logged facts. With n qualifying logged
  cycles the predicted length is `n/(n+2) × logged + 2/(n+2) × stated`
  (Flo's outline); from six logged cycles on the estimate is dropped, so
  a wrong guess cannot bias a long history. Stated cycle lengths outside
  15–90 days and period lengths outside 1–15 days are ignored.
- **Estimate alone (one logged start).** Only a next-period *range* is
  produced, labeled "Based on the estimate you gave us" (charter F6), on
  Today's one-record card and in Insights. No single date, fertile
  window, ring, calendar block or reminder is built from an estimate
  alone, keeping F5's rule that one episode does not make a pattern.
  Its spread is 4 days. When history and estimate are blended, screens
  say "Based on your logged cycles and the estimate you gave us".
- **Next period as a range.** From `ceil(spread)` days before the
  expected date to `ceil(1.5 × spread)` days after (cycles run late more
  often than early), never starting before today, and gone once she is
  clearly late. Shown on Today, Insights, the cycle screen and the
  husband report. For regular cycles this is 2 days early to 3 late.

## Round-2 property-test fixes (2026-10-21) — status: proposed

Found by the seeded property suite in `test/round2_properties/` (synthetic
histories only) and changed on branch `fix/round2-prediction-properties`.
Implemented and covered by tests there; **proposed**, not owner-reviewed,
not merged, not device-verified, not medically reviewed. Each item replaces
the rule stated above where they differ.

- **Same episode from two sources (proposed).** A start detected from flat
  `cycle_entries` logs that falls inside a canonical episode's span (from
  its start to its end date, or after its start while it is still open) is
  that same episode: the canonical start is kept, and the flat start and its
  paired period length are dropped. Before, a projection that began two or
  more days after an onboarding start whose first day was "I'm not sure"
  counted one period as two cycles, and one beginning the next day moved the
  start by a day. A flat start one day *before* a canonical start still
  replaces it, as before.
  ([cycle_calculation_service.dart](../lib/features/cycle_tracking/domain/services/cycle_calculation_service.dart) `_mergeCanonical`; tests R2-6, R2-6b, P6, P9.)
- **Late end of the range = late tolerance (proposed).** The next-period
  range now runs from `ceil(spread)` days early to `lateToleranceDays(spread)`
  (`ceil(1.5 × spread)` capped at 10) days late, so no range is offered once
  she is past the tolerance and "late by N days" shows no date. Before, for a
  spread above about 6.7 days, the uncapped late end kept a range on Insights
  next to "Late by N days". Regular cycles are unchanged (2 early, 3 late).
  ([cycle_tracking_controller.dart](../lib/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart) `nextPeriodRange`; tests R2-4, P2b.)
- **Fertile window clamped to the cycle (proposed).** The widened window
  never starts before the cycle's first day. A 21-day predicted cycle with
  a spread above 2 days (always the case with fewer than three cycles)
  started the day before the period. (`calculateFertileWindow`; tests R2-5,
  P3.)
- **Missed-log rule is leave-one-out (proposed).** An interval is left out
  when it is at least twice the median of the *other* qualifying intervals;
  a lone interval is always kept. A median that included the gap itself let
  `[35, 70]` through and moved the prediction from 35 to 51 days.
  (`predictFromIntervals`; tests R2-7, P7, P10.)
  **Open question for the owner:** a missed period's gap is the sum of two
  real cycles, so it lands just under twice the median about half the time
  (e.g. 69 among 35-day cycles) and is then still counted; the property
  suite's P10 checks only gaps the rule covers. A tolerance (for example ≥ 1.8 × the median of the others)
  would cover it; not changed here because it is a model decision.
- **Ring segments never overlap (proposed).** In `CycleSegmentPlanner` the
  second purity segment starts after both the fertile window and the period
  have ended. Before, a period that outlasted the fertile window overlapped
  it and the segments summed to more than the cycle.
  ([cycle_segment_planner.dart](../lib/features/cycle_tracking/domain/services/cycle_segment_planner.dart); tests R2-8, S1.)

Verification: `test/round2_properties/` (property suites,
`round2_regressions_test.dart`) under `TZ=Europe/London` and
`TZ=America/New_York`, plus the existing prediction tests listed below. The
fiqh regressions in `test/round2_properties/fiqh_regressions_test.dart` are
outside this change and still fail until the fiqh fixes land.

## Impact and verification

Tests: `test/cycle_tracking_controller_test.dart`,
`test/cycle_calculation_service_test.dart`, `test/calendar_days_test.dart`,
`test/canonical_calendar_screen_test.dart`,
`test/services/notification_scheduler_test.dart`,
`test/cycle_prediction_estimate_test.dart`. These pass with
`TZ=UTC`, `TZ=Europe/London` and `TZ=America/New_York`; CI runs in UTC,
where the daylight-saving cases cannot fail. Not medically reviewed;
predictions remain planning aids, not contraception or a diagnosis.
