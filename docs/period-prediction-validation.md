# Personalized period prediction and validation

Implemented on the local `fix/engine-trust-gaps` branch, 2026-10-17.
Not deployed, clinically validated, or a claim of increased real-world accuracy.

Related: [Cycle Tracking](../project-hub/generated/feature-cycle_tracking.md),
[Insights](../project-hub/generated/feature-insights.md),
[trust remediation](engine-trust-remediation.md),
[launch gate](../DEFINITION_OF_DONE_BEFORE_LAUNCH.md).

## User-facing behavior

- The point estimate remains a mean, now over at most six recent usable intervals, projected
  once from the last recorded start. [History review](prediction-history-review.md) withholds
  dates for unexplained gaps, excessive variation and stale history; users can review gaps
  without changing actual bleeding records or fiqh evidence. The median candidate is not promoted.
- With two or more recorded cycle intervals, show the smallest/largest observed interval
  projected from the last start. This is a **historical variation range**, not a calibrated
  probability interval. No 90%/95% confidence, guaranteed date, or conception probability is asserted.
- One recorded interval can support the existing limited estimate but cannot establish variability.
  Disclose the sample count and limited history instead of inventing an uncertainty margin.
- When the point estimate has passed, show an overdue-estimate explanation and ask the user to
  check her records. This does not diagnose a late period or assume another period occurred.
- Known unverified history, future starts, or intervals below the existing app input-eligibility
  floor withhold estimates pending record review. Raw records and averages are not rewritten.
  The eligibility floor is not a definition of a normal/healthy cycle.
- Insights and cycle tracking share `PeriodPredictionDetails`; canonical and legacy calendars
  share `CycleTrackingController`/`CyclePredictionService`. Dashed calendar dates now identify
  estimated START dates, not fabricated days of bleeding. Observations take priority.
- Period prediction has no Madhhab input and never determines prayer or fasting obligations.
  Ovulation remains a separately labeled calendar heuristic, not independently validated detection.

Implementation: `period_prediction.dart`, `cycle_prediction_service.dart`, and
`cycle_tracking_controller.dart`. Version: `cycle-prediction-v2-history-review-2026-10-17`.
The existing Fiqh ruleset version is not changed by this prediction work.

## Comparable methods

| Method | Point estimate | Data used |
|---|---|---|
| `historicalMean` (shipping default) | Rounded arithmetic mean | Up to six recent usable intervals |
| `recentMedian` (candidate) | Rounded median | Up to six most recent intervals |
| `recentWeightedMean` (candidate) | Mean weighted 1…N, newest highest | Up to six most recent intervals |
| `recentTrimmedMean` (research candidate) | Remove one min/max if at least five, otherwise mean | Up to six recent usable intervals; historical range preserved |

Six intervals is a declared eligibility setting, not a clinical optimum. Candidates must demonstrate
benefit on held-out participants and prospective data before promotion. The comparison never
selects a winner automatically. An adherence-aware probabilistic model and physiological-signal
integration remain future research work; this patch does not pretend either is implemented.

## Run a retrospective comparison

After normal project dependency installation:

```bash
dart run scripts/backtest_cycle_predictions.dart --compare /secure/path/histories.json
```

Input: an array of strictly increasing `YYYY-MM-DD` date arrays, one de-identified history per
array. Use explicit consent/approved research access. No real histories, identifying data, or
participant-level outputs belong in Git or public CI logs. The CLI emits aggregate metrics only.

Each fold receives **only the starts preceding its held-out target**. It predicts at the last
training start, then compares against the next actual start. It reports:

- Evaluated and withheld predictions, forecast coverage, withholding reasons, history counts and short histories.
- Mean/median absolute day error and fractions within ±1, ±3 and ±7 days.
- An additional mean giving each history equal weight (not proof of unique participant weighting).
- Results stratified by available history: one, two–five, and six or more intervals.
- Empirical historical-range coverage, number of ranges evaluated, and average range width.

Zero denominators return null, not invented accuracy. A dubious interval already in training
is counted as a withheld prediction. It is never silently dropped to improve a score. No held-out
outcome is used to clean its own training data or determine its prediction range.

## Evidence still needed before claiming high accuracy

1. A clinician-reviewed definition of a period start, record quality criteria and supported
   populations. Pregnancy, postpartum, hormonal contraception, PCOS and other materially different
   contexts need an explicit inclusion/exclusion and model policy. Existing protections are not
   comprehensive clinical validation of every subgroup.
2. A representative consented dataset, including the Saudi launch population. Keep participant
   splits separate for model development, tuning, and final evaluation; a model chosen using one
   test set must not be advertised using that same set as independent validation.
3. Clinician-agreed acceptance criteria and uncertainty analysis. Evaluate regular/irregular
   patterns separately with sample sizes; the CLI's history-length strata do not replace this.
4. Prospective evaluation: freeze model/version and each prediction **before** the next period is
   recorded, then compare. A retrospective backtest alone is not prospective validation.
5. Review range calibration and sharpness. Observed min/max can miss the next period even with
   identical prior intervals. Report actual coverage alongside width; do not relabel it as 95%.
6. Validate exact released app, Arabic/English layout, correction/relaunch behavior and device
   integration. Flutter/widget/build checks remain pending in this environment; prior automatic
   approval rejection still prevents publication without explicit authorization.

## Verification

The original v1 run passed 129 pure Dart tests in two time zones; 27 knowledge-boundary Python
tests and the KB review gate also passed in that earlier work. The updated history-review work
passes **192 pure Dart tests in both Asia/Riyadh and America/New_York**; see the
[implementation, full benchmark and remaining checks](prediction-history-review.md).
Flutter UI/integration tests are written but remain **NOT RUN** in this environment.

The [original external benchmark](external-cycle-benchmark.md) is preserved unchanged as v1
historical evidence. On 9,263 identical targets forecast by both versions, default-method MAE
was 10.59 days for v1 and 3.90 days for v2. Overall forecast coverage decreased from 87.9% to
78.0%; improved error does not imply every history now receives a reliable forecast. This is
development evidence, not independent, prospective, clinical or fiqh validation.

The [controlled accuracy program](prediction-accuracy-program.md) tested ten methods at fixed
coverage. Its strongest candidate reached 81.03% within ±3 days; the default remains unchanged.
This does not establish a 90% accuracy claim or replace independent/prospective validation.
