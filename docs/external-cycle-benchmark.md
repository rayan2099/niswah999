# External period-start benchmark — 2026-10-17

Historical **v1** evidence, retained with its original scores. The subsequent
[v2 history-review implementation and benchmark](prediction-history-review.md) supersede
the default-policy description below; this report is not a description of the current local code.

**Executed, exploratory, and not a clinical validation or a replication of a published prediction model.**
The current all-history average is vulnerable to discontinuous records. No prediction method was
changed or promoted on the basis of this run. No participant records are included in this repository.

Related: [prediction design and validation](period-prediction-validation.md),
[trust remediation](engine-trust-remediation.md),
[Cycle Tracking](../project-hub/generated/feature-cycle_tracking.md),
[launch gate](../DEFINITION_OF_DONE_BEFORE_LAUNCH.md).

## Source and consent evidence

Used Förster, Charlotte and Mitesser, Oliver (2025), dataset v1,
[Zenodo DOI 10.5281/zenodo.15598359](https://doi.org/10.5281/zenodo.15598359).
The official record's API metadata identifies the release as open, **CC BY 4.0**.
Original file: `menstruationdata.csv`, 887,713 bytes,
MD5 `1409abf2d80a62a26922ae62a487f5c9`,
SHA-256 `7712b11290d2d34384eaa3bca02739067a0dd6ddc8bd90c6fe91c545efffe28f`.

The associated Helfrich-Förster et al. paper,
[Science Advances, DOI 10.1126/sciadv.adw4096](https://doi.org/10.1126/sciadv.adw4096),
reports that Würzburg ethics approval was sought under identifier 20210407 01 for storing,
collating and retrospectively analyzing anonymized records, and that written informed consent
was obtained for the relevant datasets. This is verification
of the authors' documented consent and release terms, not an independent inspection of signed
consent forms. The paper's lunar hypothesis is not used in Niswah's predictor.

The repository describes 198 women; the downloaded CSV contains **199 distinct source labels**.
That discrepancy is unresolved. Counts below refer to source histories, not confirmed unique women.
These records do not establish representativeness of Saudi users or all clinical contexts.

## Preparation and evaluation

The cohort rule was chosen before inspecting forecast scores: exclude an entire source label
if any `BeforeBirth`, `AfterBirth` or `Birth` flag is 1; deduplicate exact same-label dates;
preserve all remaining chronological gaps. This conservative flag exclusion does not establish
absence of pregnancy, contraception, postpartum changes or other conditions. Flag semantics and
record continuity require clarification before stronger clinical interpretation.

The source has 15,686 rows. Excluding 22 flagged labels leaves **177 histories and 12,224 distinct
recorded starts**. Four duplicate dates occur in the source. Eligible histories contain 12,047
intervals: 29 below 15 days and 72 above 90 days; the maximum is **18,966 days**. A 90-day count
is descriptive only: no upper-gap cutoff was applied. No target was trimmed to improve a score.
Birthday and origin fields were discarded; IDs are used only to group records outside the checkout.

Frozen application revision: `192e0bc` (`cycle-prediction-v1-2026-10-17`).
The [existing Dart CLI](../scripts/backtest_cycle_predictions.dart) calls the actual
`CycleTrackingController` and prediction service. For every target it sees only earlier starts;
it predicts at the most recent training start and scores the next recorded start. Folds start
with one observed interval. The first held-out target is the third start.

Of 11,870 eligible folds, **10,438 were evaluated and 1,432 withheld**. The existing input policy
withholds predictions after a training interval below 15 days; no forecast is scored while
withheld. This threshold is an app eligibility policy, not a medical definition of normality.
An early questionable interval can suppress many later folds. Accuracy percentages below apply
only to evaluated folds; evaluated coverage is 87.9% of possible folds. Missing biological periods
cannot be reconstructed from these records.

## Actual app results

| Method | Mean absolute error, days | Median absolute error, days | Within ±3 days | Within ±7 days |
|---|---:|---:|---:|---:|
| All-history mean — current default | 17.38 | 2.0 | 64.6% | 82.6% |
| Median of latest up to six intervals — candidate | 7.99 | 2.0 | 77.6% | 92.3% |
| Recency-weighted mean of latest up to six — candidate | 9.95 | 2.0 | 73.6% | 89.5% |

Every method used the same 10,438 targets. The mean and median errors must be read together:
many small misses coexist with very large misses. Equal-history-weighted mean absolute errors
are 15.78, 7.94 and 9.53 days respectively. Repeated targets from the same history are correlated;
they are not 10,438 independent participants. No confidence intervals or significance claim are made.

| Historical variation range | Empirical coverage | Mean width, days |
|---|---:|---:|
| All-history min/max | 92.3% | 348.65 |
| Latest-six min/max (both candidates) | 77.1% | 29.52 |

Ranges were available for 10,262 targets. High coverage from a very wide range is not useful
precision. These are observed historical bounds, not calibrated 90% or 95% intervals.

Source study subgroups were also run separately, without selecting on prediction outcomes:

| Source subgroup | Histories | Evaluated / withheld | Default MAE | Recent-median MAE |
|---|---:|---:|---:|---:|
| `old` | 15 | 1,996 / 228 | 19.30 days | 8.20 days |
| `new` | 162 | 8,442 / 1,204 | 16.93 days | 7.94 days |

These are the source's study labels, not independent development/test partitions or demographic
subgroups. All three methods and history-length strata are retained in the
[aggregate results](validation/external-cycle-benchmark-2026-10-17/zenodo-unflagged-results.json).
Separate [old](validation/external-cycle-benchmark-2026-10-17/zenodo-unflagged-old-results.json)
and [new](validation/external-cycle-benchmark-2026-10-17/zenodo-unflagged-new-results.json)
outputs are retained as well.

## Interpretation and release implications

1. This exposes a real robustness gap: long gaps can contaminate all-history averages and make
   min/max ranges extremely broad. Treat continuity, stale history and uncertain tracking as
   explicit input-quality cases before claiming accurate prediction. Do not silently invent
   missing periods or recode every long interval as skipped tracking.
2. Recent median is a promising development candidate on this dataset. Choosing it using these
   results makes this a development dataset; improvement must be checked on a separately held-out
   cohort and prospectively frozen forecasts before promotion or an accuracy claim.
3. The target here is the **next recorded start**, which can differ from the next experienced
   biological period. Unexplained date gaps, source-label ambiguity, changing physiology and
   retrospective data entry limit clinical interpretation. Do not call 77.6% “clinical accuracy.”
4. This does not validate ovulation, pregnancy chances or fiqh rulings. Fiqh still requires a
   separately adjudicated set of cases with qualified scholarly review and explicit school rules.
5. Launch readiness is not established. The exact released app, data-entry and correction flows,
   clinical inclusion policy, scholarly review and prospective validation remain separate gates.

## Other sources screened

| Source | Evidence / access finding | Disposition |
|---|---|---|
| [Marquette Menstrual Cycle Data](https://epublications.marquette.edu/data_nfp/7/) | University states anonymized dissemination and subject consent for reuse; ordinary file download returned HTTP 403 | Not used; no mirror substituted |
| [PhysioNet mcPHASES](https://www.physionet.org/content/mcphases/1.0.0/) | Access requires approved credentials and a signed data-use agreement | Not used |
| [Padova cycle database](https://www.stat.unipd.it/ricerca/basi-di-dati) | Department requires a research proposal/application | Not used |
| [Li et al. JAMIA prediction study](https://pmc.ncbi.nlm.nih.gov/articles/PMC8714275/) | Real Clue dataset requires a data-use agreement | Cannot reproduce its published real-data scores with current access |
| [Authors' public code](https://github.com/iurteaga/menstrual_cycle_analysis) | Sample NPZ at revision `5f21f094dbdb9a6c302424b66a52b7c38e99f683` has `data_model=generalized_poisson`, simulation hyperparameters, `cycle_skipped` and `true_params`; generator code writes these fields | Simulated sample excluded from real-data evidence |

No researcher was contacted and no access agreement was accepted on the user's behalf.
This is not an exhaustive catalogue of every existing dataset. No published predictor's accuracy
has been matched or replicated: model, cohort and evaluation protocol would all need to match.

## Reproduction and verification

Obtain the exact official CSV from Zenodo and keep it in an approved location outside this checkout.
The [preparer](../scripts/prepare_zenodo_cycle_benchmark.py) checks the pinned SHA-256, validates
dates/flags, emits anonymous date arrays outside the checkout and prints aggregate counts only.
It emits no birthdays, source IDs or other demographic fields.

```bash
python scripts/prepare_zenodo_cycle_benchmark.py /secure/menstruationdata.csv /secure/prepared
dart run scripts/backtest_cycle_predictions.dart --compare /secure/prepared/zenodo-unflagged.json
dart run scripts/backtest_cycle_predictions.dart --compare /secure/prepared/zenodo-unflagged-old.json
dart run scripts/backtest_cycle_predictions.dart --compare /secure/prepared/zenodo-unflagged-new.json
```

Executed here with Dart 3.13.0 directly and an offline package configuration against the unchanged
app source. Dataset preparation was reproduced from a second official download with the same
checksum; all three prepared cohorts matched the histories used for the executed benchmarks.
Aggregate preparation counts and frozen source hashes accompany the results. No Flutter UI,
device, build, prospective or clinician/scholar validation is implied by these CLI runs.
