# Prediction history review and recent-history policy

Implemented locally on `fix/engine-trust-gaps`, 2026-10-17. **Not deployed, independently
validated or clinically approved.** Version: `cycle-prediction-v2-history-review-2026-10-17`.

Related: [Cycle Tracking](../project-hub/generated/feature-cycle_tracking.md),
[Insights](../project-hub/generated/feature-insights.md),
[Dashboard](../project-hub/generated/feature-dashboard.md),
[Notifications](../project-hub/generated/feature-notifications.md),
[Husband Report](../project-hub/generated/feature-husband_report.md),
[prediction specification](period-prediction-validation.md),
[original v1 benchmark](external-cycle-benchmark.md),
[launch gate](../DEFINITION_OF_DONE_BEFORE_LAUNCH.md).

## Problem and implemented behavior

An all-history average treated long gaps between recorded starts as biological cycles. It could
produce misleading dates and historical ranges spanning hundreds of days. The revised predictor
uses at most six recent intervals, explains excluded history and withholds an estimate when
recent input cannot support a useful date. The default formula remains a rounded arithmetic
mean; median, weighted and trimmed means remain evaluation candidates. The later
[controlled accuracy program](prediction-accuracy-program.md) preserves these v2 scores and
coverage, and adds an explicitly selected trimmed-mean research method without promoting it.

A recent gap above 90 days needs review. A gap also needs review when at least three preceding
usable intervals exist, it exceeds twice their median, and the excess is at least 14 days.
The personal baseline uses up to six earlier intervals between 15 and 90 days. Only earlier
records determine the gap flag; a held-out next start never affects its own prediction.

The user can save or change one of three forecasting-only answers:

- **Missed recording periods:** exclude that gap and earlier intervals from forecasts; never
  divide the gap into invented cycles or insert bleeding observations.
- **Unsure:** the same conservative forecasting boundary, without affirming that a period
  occurred or was missed.
- **A genuinely longer cycle:** retain the interval as reported, without classifying it as
  medically normal. An interval beyond supported limits still cannot produce a date.

After a reviewed interruption, require two actual later intervals (three starts from the
boundary) before resuming. An unreviewed flagged gap within the recent window still withholds
forecasts even if some later starts exist. Once a gap falls outside the six-interval window, it
cannot distort a recent forecast; excluded intervals are disclosed. Original records and
all-history descriptive averages remain unchanged.

Also withhold when the recent min/max range width exceeds 21 days, the last start is over 90
calendar days old, a start is in the future, any supplied interval is below the existing 15-day
eligibility floor, or history/review storage cannot be verified. The short-interval gate remains
history-wide and conservative; this patch does not automatically resolve questionable bleeding
starts. An elapsed estimate inside the supported horizon remains overdue, never rolled forward.

**Six intervals, 90 days, 21 days, the relative-gap rule and two intervals after a break are
engineering eligibility/usability policies, not medical normality thresholds or validated
clinical optima.** They were fixed before observing v2 benchmark scores and were not tuned to
improve those scores. Clinical review may require a different supported-population policy.

## Storage, corrections and shared consumers

`PredictionHistoryReview` stores exact endpoint dates, answer and UTC report time. Endpoint
matching invalidates an answer when a relevant start is corrected or a start is inserted. A
historical evaluation ignores answers reported after its as-of time. These answers never enter
canonical bleeding observations, fiqh classification, prayer or fasting rules.

`PredictionHistoryReviewStore` uses the existing encrypted, explicitly user-scoped
`SecureLocalStore` adapter. Writes are serialized across screens and verified by read-back;
malformed/failed reads are not treated as confirmed empty answers. Account deletion clears the
new category. Answers persist across restarts **on the same device**; no backend migration or
cross-device synchronization is implemented. Another device safely asks again. Reviews are not
included in the husband-facing report.

Arabic/English review controls are wired to tracking, Insights, Today and the canonical calendar.
Saved-answer events refresh mounted prediction consumers. Owned view models/subscriptions are
disposed on screen/shell teardown; generation checks prevent obsolete loads overwriting a
newer result. Saving rechecks account ownership and whether the exact interval is still present.

Period, phase, fertile dates, dashboard segments and report timelines derive from the same
eligible prediction length, rather than using the descriptive all-history mean to reconstruct
another forecast. The husband report loads the same review answers and withholds dates on read
failure. Cycle reminders now call the shared predictor and load canonical episode timings;
failed/degraded reads cancel the old cycle reminder instead of calculating another date from
legacy averages. Saved-review events trigger notification reconciliation. OS cancellation and
delivery still require real-device verification; app code cannot guarantee OS acknowledgement.

## Executed external benchmark

Same consent-documented Zenodo v1 source and frozen 177-history cohort as the original benchmark.
All 11,870 target opportunities remain included. No review answers exist in the research dataset;
none were fabricated. Each forecast sees only its historical prefix. Full inputs remain outside
Git; the repository contains aggregate results only.

| Default method / scope | Evaluated | Mean absolute error | Within ±3 days |
|---|---:|---:|---:|
| v1, all issued forecasts | 10,438 | 17.38 days | 64.6% |
| v1, only targets also forecast by v2 | 9,263 | 10.59 days | 68.9% |
| v2, identical common targets | 9,263 | 3.90 days | 80.3% |

V2 forecast coverage is **78.0%**, compared with **87.9%** for v1. Withheld cases increased from
1,432 to 2,607: 1,432 short-interval history cases, 496 unexplained-gap cases and 679 excessive-
variation cases. The 1,175 newly withheld targets had v1 MAE 70.87 days. The common-target table
separates recency changes from abstention, but its subset is selected by the new policy and it
is still a development-cohort comparison, not independent performance evidence.

V2 median absolute error is 2 days. Historical ranges were available on 9,095 forecasts, with
mean width 6.25 days and empirical coverage 76.3%. These remain historical variation ranges,
not calibrated confidence intervals. Do not relabel them as 90% or 95% intervals.

| Source subgroup | Evaluated / withheld | V2 default MAE | Forecast coverage |
|---|---:|---:|---:|
| `old` | 1,724 / 500 | 3.56 days | 77.5% |
| `new` | 7,539 / 2,107 | 3.98 days | 78.2% |

The recent-median candidate had MAE 3.902 days versus 3.904 for the default on the same 9,263
forecasts. This small exploratory difference is not a basis for automatic promotion.
All source-label ambiguity, discontinuity, consent-provenance and population limitations from
the original report still apply. The target is the next **recorded** start; it may differ from
the next experienced biological period.

[Aggregate model results](validation/prediction-history-review-2026-10-17/zenodo-v2-results.json),
[paired actual-controller comparison](validation/prediction-history-review-2026-10-17/zenodo-v1-v2-paired-results.json),
[old subgroup](validation/prediction-history-review-2026-10-17/zenodo-v2-old-results.json),
[new subgroup](validation/prediction-history-review-2026-10-17/zenodo-v2-new-results.json),
[source hashes and policy manifest](validation/prediction-history-review-2026-10-17/execution-manifest.json).

## Verification and reproduction

**192 pure Dart tests passed in both Asia/Riyadh and America/New_York** using Dart 3.13.0 and
the existing offline package configuration. Scratch copies of thirteen pure test files changed
only the `flutter_test` import to `test` (and resolved the backtest script import). Actual
application source and assertion bodies ran unchanged. This includes the earlier engine tests,
new history/review/storage/controller cases, and 39 notification-planner tests. The paired
comparator independently reproduces both CLI aggregates exactly; withholding counts reconcile.

Arabic/English sheet tests, view-model restart/read-failure/correction tests, report integration
cases and account-deletion storage checks are written but **NOT RUN under Flutter here**.
Formatting parsed the changed Dart files, which is not type analysis or device verification.
Full Flutter analyzer/widget/build/device checks remain pending. The earlier Flutter SDK
bootstrap was rejected by automatic approval review because it attempted instance-metadata
access; direct offline Dart execution was used without retrying that bootstrap.

After standard dependency installation, prepare the pinned source using the original report's
instructions, then run:

```bash
dart run scripts/backtest_cycle_predictions.dart --compare /secure/prepared/zenodo-unflagged.json
# Use a separate trusted checkout at 192e0bc for the baseline.
python scripts/compare_cycle_prediction_revisions.py /path/to/v1-checkout /secure/prepared/zenodo-unflagged.json --packages /path/to/package_config.json
```

The comparison executes both real controllers, with separate entity types, and scores civil
dates rather than elapsed timestamp durations. It emits aggregate metrics only.

## Remaining acceptance work

1. Review the supported-population policy and thresholds with a clinician; recruit a separate,
   consented and representative validation cohort, including Saudi users. Do not tune this
   policy on that cohort and then describe it as an untouched final test.
2. Run Flutter and actual-device journeys: review all three answers, edit/insert starts, restart,
   switch accounts/devices, trigger secure-storage failures and verify reminder cancellation.
3. With appropriate consent, run a prospective study. Freeze model version, UTC issue time,
   point/range or withholding reason and the exact input revision before the next start is
   reported. Preserve corrections separately; never recalculate a historic forecast and label
   it as the one originally issued. Predeclare outcome definitions and acceptance criteria;
   report error, range coverage/width, withholding and subgroup sample sizes together.
   Production forecast collection and a completed prospective study are **not implemented or
   claimed by this patch**.
4. Fiqh requires a separate qualified scholarly review and adjudicated cases. This patch neither
   changes the fiqh ruleset nor makes its decisions more authoritative through prediction scores.
