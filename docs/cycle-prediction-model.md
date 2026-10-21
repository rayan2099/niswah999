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
- **Missed-log rule is leave-one-out at 1.8× the median (decided
  2026-10-21).** An interval is left out when it is at least
  `CycleCalculationResult.missedPeriodMedianFactor` (1.8) times the median
  of the *other* qualifying intervals; a lone interval is always kept, and
  the rule never drops every interval (if it would, all qualifying
  intervals are used). A median that included the gap itself let
  `[35, 70]` through and moved the prediction from 35 to 51 days.
  **Decision (2026-10-21, made by the team at the owner's request):** the
  factor was lowered from 2.0 to 1.8. A missed period's gap is the sum of
  two real cycles, so with ordinary variation it lands just under twice the
  median about half the time (e.g. 69 among 35-day cycles); under 2.0 it was
  still counted and skewed predictions by weeks. At 1.8, `[35, 35, 69]` and
  `[35, 69]` both predict 35. A single genuine cycle at 1.8× her usual
  length or more is now left out of the forward prediction too (it stays in
  `cycleLengths` and `averageCycleLength`, which are never filtered); the
  generated irregular histories of P7/P10 were run to confirm ordinary
  irregular variation does not reach it.
  (`predictFromIntervals`; tests R2-7, R2-7b, R2-7c, P7, P10.)
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

## Prediction-efficiency audit (2026-10-21) — status: proposed

Changed on branch `perf/prediction-efficiency`. Implemented and covered by
tests there; **proposed**, not owner-reviewed, not merged, not
device-verified, not medically reviewed. Synthetic data only.

- **One calculation per load, not per rebuild (proposed).** Today, the
  Calendar tab and Insights each re-ran `CycleCalculationService.calculate`
  on every rebuild (all three stay mounted and rebuild on every view-model
  change, Today also once a minute), and `loadLogs` ran it a second time
  for the summary. With three years of daily logs one run measured about
  5 ms in the test VM, so one change cost about 20 ms of recalculation.
  [cycle_tracking_view_model.dart](../lib/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart)
  now keeps the result until the data or the calendar day changes, builds
  the summary from it (`CycleTrackingController.summarizeCalculation`), and
  caches the Calendar tab's month/year summary (`calculationUpTo`) the same
  way. Results are unchanged.
- **One startup load (proposed).** The home shell and the Today screen both
  loaded the shared view model at startup, so every launch read
  `cycle_entries`, `bleeding_episodes` and `cycle_baselines` twice. Only
  the Today screen (always mounted) loads it now
  ([main.dart](../lib/main.dart)).
- **One prediction gate (proposed).** `canPredictFromHistory` now also
  requires `hasPlausibleAverage`, the gate Today and Insights already
  applied. Starts logged 3 and then 20 days apart (average 12) showed no
  prediction on Today and Insights, while the Calendar tab, the canonical
  calendar, the husband report and the reminder still predicted from the
  20-day interval. Insights now also uses `canPredictFromHistory`, like
  Today's ring.
- **The canonical calendar uses the shared summary (proposed).** Its block
  used to come from a second copy of the prediction over the raw episode
  list, which did not merge an episode restarted the day after a same-day
  stop and so drew the block a day earlier than Today gave. It now uses
  `summarizeCalculation` over the same episodes (still nothing while an
  episode is open, from an estimate alone, or from a degraded read).
- **No range start within 15 days of the last start (proposed).** The
  range's early end is now never sooner than
  `minPlausibleCycleLengthDays` after the current cycle's start: short,
  irregular histories offered ranges from cycle day 13 (6 of 150 generated
  irregular histories, property P2c).
- **Calendar-day summary ranges (proposed).** The Calendar tab's month
  summary ended at `last day + 24 h`, so a month ending on a spring-forward
  Sunday (31 March 2024 in the UK) pulled in the next month's first day,
  which made March 2024 show no statistics at all. The Hijri-year end and
  the custom "last N days" presets had the same `Duration` arithmetic; the
  presets also kept the clock time, so their first day's logs were left
  out in every zone.

Not changed (recorded for review): the view model still predicts from a
degraded `bleeding_episodes` read (a quarantined row) while the reminder
and the canonical calendar refuse to; the view model reads 200 remote
`cycle_entries` rows and the reminder 1,000; a bleeding restart under 15
days after a start moves the prediction's anchor to the restart; the
Calendar tab repeats "Expected Haid" every predicted cycle while the
canonical calendar shows only the next period; the conception-chance
curve on the Calendar tab peaks one day before the predicted ovulation
day its comment names.

Tests: `test/prediction_efficiency/prediction_efficiency_test.dart`,
`test/canonical_calendar_screen_test.dart` (shared-summary block),
`test/round2_properties/prediction_properties_test.dart` (P2c).

## Impact and verification

Tests: `test/cycle_tracking_controller_test.dart`,
`test/cycle_calculation_service_test.dart`, `test/calendar_days_test.dart`,
`test/canonical_calendar_screen_test.dart`,
`test/services/notification_scheduler_test.dart`,
`test/cycle_prediction_estimate_test.dart`. These pass with
`TZ=UTC`, `TZ=Europe/London` and `TZ=America/New_York`; CI runs in UTC,
where the daylight-saving cases cannot fail. Not medically reviewed;
predictions remain planning aids, not contraception or a diagnosis.
