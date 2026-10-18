# Prediction accuracy program — controlled development experiment

2026-10-17. **Target: 90% within ±3 days. Not achieved or clinically validated.**
The app default remains the six-interval mean. `recentTrimmedMean` is added as an explicit
research candidate only. No method is automatically promoted and no production data collection
or deployment occurred.

Related: [Cycle Tracking](../project-hub/generated/feature-cycle_tracking.md),
[history-review implementation](prediction-history-review.md),
[prediction specification](period-prediction-validation.md),
[clinical/data-access/prospective handoff](prediction-validation-review-brief.md),
[launch gate](../DEFINITION_OF_DONE_BEFORE_LAUNCH.md).

## What was fixed before scoring

The [protocol](validation/prediction-accuracy-program-2026-10-17/protocol.json) was committed at
`e3e147e` before the candidate experiment. This is a local pre-score freeze, not external
preregistration or proof from a trusted timestamp service. The runner checks the exact protocol
SHA-256 and rejects a changed accuracy tolerance or candidate-specific withholding policy.

- All ten candidates receive the same baseline-selected prior intervals and identical 9,263
  forecast opportunities. The baseline's eligibility policy is unchanged; no candidate can
  improve its percentage by withholding more cases. The ±3-day goal is not widened to ±7.
- The actual Dart controller receives only preceding starts. Only after predicting does the
  exporter attach the target interval for scoring. Questionable short prefixes still withhold
  rather than letting legacy start deduplication clean them silently.
- Multiple histories sharing a declared participant/source key stay together in group folds.
  The existing cohort provides source labels, not audited participant identities; we do not
  call those labels independently confirmed women.
- Method selection uses equal-group hit rate, then equal-group MAE, on the other four of five
  source-group folds only. Each held-out group is scored once using that training-selected method.
  This does not undo earlier policy development on the same cohort: the result is exploratory.
- Uncertainty uses 2,000 paired whole-group bootstrap resamples with a frozen seed. These are
  conditional intervals for fixed out-of-fold predictions, not refit-model uncertainty or
  proof of representative population performance.

No synthetic records are mixed into the real-data result. Synthetic cases test the pipeline only.
Absolute dates and original group labels do not enter the minimized research fold artifact;
that artifact still contains sensitive cycle histories and remains outside Git. Repo outputs
contain aggregate results only.

## Actual results on the existing consent-documented development cohort

177 source groups; 11,870 target opportunities; **9,263 issued and 2,607 withheld** for every
candidate. Forecast coverage remains **78.04%**. Of the 177 groups, 175 have scored predictions.
The target remains the next recorded start, not independently verified biological onset.

| Fixed candidate | Within ±3 days | MAE, days | Role |
|---|---:|---:|---|
| Current mean of up to six | 80.28% | 3.904 | Unchanged default |
| Median of up to six | 80.51% | 3.902 | Research candidate |
| Mean of latest three | 78.61% | 4.000 | Research only |
| Median of latest three | 78.18% | 4.026 | Research only |
| Trimmed mean of up to six | **81.03%** | **3.876** | Strongest candidate in this experiment |
| Exponential mean, newest weight doubled | 78.42% | 4.005 | Research only |
| Last recorded interval | 71.52% | 4.498 | Research only |
| Bounded linear trend | 73.37% | 4.278 | Research only |
| Historical ±3-day window center | 80.52% | 3.914 | Research only |
| Personal past-performance expert | 79.29% | 3.989 | Research only |

All five folds selected the trimmed mean using training groups only. It removes one minimum
and one maximum from the point-estimator calculation when at least five prior intervals are
available; with fewer, it uses the mean. Original records, selected-history count and the
historical min/max range are preserved. This is not a clinical assertion that the extremes
are invalid cycles.

The out-of-fold result is a gain of **0.756 percentage points**, with a conditional paired
95% bootstrap interval of **+0.373 to +1.120 points**. The candidate hit-rate interval is
**79.10–82.91%**. Its MAE improvement is 0.028 days; the small size matters as well as the
conditional uncertainty. These intervals are development-cohort descriptions, not expected
Saudi-launch accuracy or clinical acceptance.

Equal-source-group results are lower than cycle-weighted headline scores: **76.16% → 76.63%**
within ±3 days, with MAE **4.444 → 4.412 days**. Long histories otherwise contribute more targets.
Groups are not confirmed unique participants, so neither averaging nor bootstrap can establish
participant identity or representativeness.

The stronger prospective goal remains unproved. Do not turn 81% into a 90% claim through a
wider tolerance, additional exclusions, selecting only regular histories, or calling the same
records an untouched independent test.

## What changed in application code

`PeriodPredictionMethod.recentTrimmedMean` is available for explicit evaluation through the
actual service/controller and the existing backtest CLI. The production-default argument is
still `historicalMean`; user screens do not select a winner from this experiment.

The actual Dart baseline, median and trimmed candidate reproduce the research implementation's
point predictions **exactly**, forecast by forecast, across all 9,263 issued forecasts; counts, MAE and ±1/±3/±7-day rates also agree. Candidate addition
does not change the default version's original metrics or its coverage. The candidate retains
the same history-quality checks and range semantics. No fiqh engine rule was modified.

## Artifacts and reproduction

- [Frozen protocol](validation/prediction-accuracy-program-2026-10-17/protocol.json)
- [Full aggregate experiment](validation/prediction-accuracy-program-2026-10-17/development-results.json)
- [Actual Dart candidate comparison](validation/prediction-accuracy-program-2026-10-17/runtime-candidate-results.json)
- [Execution/source manifest](validation/prediction-accuracy-program-2026-10-17/execution-manifest.json)
- [Clinical and access review brief](prediction-validation-review-brief.md)
- [Prospective forecast schema](validation/prediction-accuracy-program-2026-10-17/prospective-forecast.schema.json)

After standard dependency installation and the original pinned Zenodo preparation:

```bash
dart run scripts/export_cycle_evaluation_folds.dart /secure/prepared/zenodo-unflagged.json /secure/research/folds.json
python scripts/evaluate_cycle_candidates.py /secure/research/folds.json > /secure/research/aggregate-results.json
dart run scripts/backtest_cycle_predictions.dart --compare /secure/prepared/zenodo-unflagged.json
```

Existing date-array input treats each source history as a group. For a new approved dataset,
the exporter also accepts `{"histories":[{"group":"pseudonymous-key","starts":["YYYY-MM-DD"]}]}`.
All fragments of one person must use the same key. Overlapping fragments in one group are
rejected; grouping declarations are not independently authenticated by the software.

**202 pure Dart tests passed in Asia/Riyadh and America/New_York**, using fourteen offline
scratch test copies with only `flutter_test` imports changed to `test` and script imports
resolved to real source paths. App source/assertions ran unchanged. **15 Python tests passed**
for candidate formulas, fixed coverage, group selection, bootstrap units, count reconciliation,
missing-fold rejection and no invented metrics. The prospective JSON Schema passed Draft
2020-12 validation plus two accepted and six rejected synthetic-record checks. This schema is
only a structural contract; it proves neither consent, approved hashes, range/time ordering nor
that a forecast preceded an outcome. No prospective study or ledger is enabled.

Final core/evaluation verification was repeated on 2026-10-18.

Full Flutter analyzer/widget/build/device checks remain pending under the already documented
SDK-bootstrap approval block. The [previous report](prediction-history-review.md) records the
block and the offline alternative. This work does not claim those checks passed.

## Decision and required next evidence

**Keep the default unchanged.** The trimmed candidate is suitable for further study, not a
new marketing promise. This experiment did not reach 90%.

Independent source screening found access or reuse constraints: mcPHASES requires a DUA;
Clue data is not public and requires approved access; Utah repository metadata lists CC BY-NC;
Marquette's ordinary download remains unavailable. The additional public CILab repository
explicitly uses synthetic data. No restricted data, unapproved mirror or agreement accepted
on the user's behalf was used. Primary source links and concrete request requirements are
in the review brief.

The next stage requires an eligible independent dataset, clinician/statistician review of
population and acceptance criteria, and predictions frozen before future outcomes under
appropriate consent. The brief makes those steps reviewable; it does not label them completed.
Clinical prediction evidence and scholarly fiqh approval remain separate release gates.
