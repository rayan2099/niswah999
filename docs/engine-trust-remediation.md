# Cycle and Fiqh trust remediation — 2026-10-17

Status: pure Dart core verified; Flutter integration pending; **not medical validation or scholarly approval**.
Base reviewed: `a2a55b0073391bd0a63b559f5b69e979e3947e4b`.

Related navigation: [Cycle Tracking](../project-hub/generated/feature-cycle_tracking.md),
[AI Advisor](../project-hub/generated/feature-ai_advisor.md),
[launch gate](../DEFINITION_OF_DONE_BEFORE_LAUNCH.md),
[threshold evidence crosswalk](../production-readiness-results/fiqh-engine/ENGINE_TO_KB_ATOM_CROSSWALK.md).

## Implemented changes

| Gap | Change | Evidence to inspect |
|---|---|---|
| Missing history became Tahara | Preserve `insufficientHistory` in the shared engine, dashboard, chat and reports; empty history cannot prove purity | `test/engine_trust_boundary_test.dart`, `test/services/cycle_status_engine_test.dart` |
| Canonical daily observations all defaulted to cycle day 1 | Compute adapter day indices within each observed episode; one episode cannot manufacture several cycle starts | `test/engine_trust_boundary_test.dart`, `test/report_canonical_evidence_test.dart` |
| Report classification duplicated the engine scan | Report classification delegates to `CycleStatusEngine`; chat uses canonical report evidence instead of the legacy cycle table | `ReportCanonicalEvidence.currentClassification`, `ClientFiqhStateProvider` |
| Degraded episode reads could be treated as complete | Both canonical result types retain uncertainty; remove the unnecessary second episode read; prediction loading fails explicitly on incomplete history | `ReportCanonicalEvidence.fromResults`, `CycleTrackingViewModel` |
| Purity thresholds were only applied for one school | A known short or unknown purity interval defers to review for every school, using its existing evidence-linked threshold. This does not decide how interrupted bleeding should be legally classified | `MadhhabRuleEvaluator`, `test/engine_trust_boundary_test.dart` |
| Maliki habit-dependent maximum was simplified | Missing or exceeded personal habit defers to review. No automatic istizhar rule is invented. Current UI callers do not supply a reviewed personal habit, so active Maliki classification will defer | `MadhhabRuleEvaluator`, quarantined `MLK-HAID-05` |
| Countdown suggested time alone would resolve another uncertainty | Only a minimum-duration-only pending case can expose `confirmAt` | `MadhhabRuleResult.minimumOnlyPending` |
| Prediction jumped forward by whole unrecorded cycles | Estimate only once from the last observed start; withhold a new next-period/fertile-window estimate once overdue; calendar no longer repeats phantom periods indefinitely | `test/cycle_tracking_controller_test.dart`, `test/engine_trust_boundary_test.dart` |
| Future data contaminated historical calculation | Exclude future starts/ends from an as-of calculation; future inputs cannot produce a confident current fiqh state | `test/engine_trust_boundary_test.dart` |
| Missing end inflated a later period duration | Pair the later explicit start with its own end; never infer the earlier missing end | `test/engine_trust_boundary_test.dart` |

Additional fixes: calendar-day arithmetic now survives daylight-saving transitions, and the
arbitrary conception-chance curve/high-medium-low labels were removed. The UI shows estimated
fertile-window dates with an explicit limitation instead. Source expectations remain engineering-derived.

The later [history-review remediation](prediction-history-review.md) addresses discontinuous
records with recent-history forecasting, explicit review answers and shared notification/report
gates. Its development-cohort benchmark does not constitute clinical or scholarly approval.

Ruleset identifier advances to `v2-2026-10-17`. Existing records are not rewritten.
Historical interval version lookup already exists; this patch does not implement historical execution of old rulesets.
Release must verify version provenance and the required history migration in the intended environment.

## Independent review still required

The subsequent [personalized prediction work](period-prediction-validation.md) adds shared
historical-variation ranges, sample counts, candidate comparisons and validation metrics. It does
not establish clinical accuracy or remove the review requirements below.

Passing implementation-derived tests cannot certify the religious rules or medical prediction accuracy.
The legacy golden set and September scholar packet contain historical wording/values; use the October
crosswalk and current code together, and do not send the old packet as a current specification.

| Review | Required acceptance evidence | Current status |
|---|---|---|
| Four-school fiqh decisions | Named qualified reviewers, exact rule version and source passages, independently authored expected outcomes, scope/conditions and signed review decisions | NOT REVIEWED |
| Irregular/interrupted bleeding | Reviewed treatment of short purity, spotting, cumulative vs elapsed bleeding, habit changes, and retrospective obligations | NOT REVIEWED; defer unsupported cases |
| Precision and current-state freshness | Review date-only vs exact-time boundaries, stale observations, same-day changes and uncertainty; never infer exact hours from an unknown start time | NOT VALIDATED comprehensively |
| Pregnancy/postpartum | Review bleeding during pregnancy and postpartum cessation/resumption. Pregnancy tracking phases are not independent validation of Nifas rulings | NOT REVIEWED comprehensively |
| Medical prediction | Clinician review of assumptions, exclusions, uncertainty and bilingual copy; out-of-sample evaluation on consented representative histories | NO clinical accuracy claim established |
| Release integration | Exact signed app build + deployed backend/migrations; device journey for each unresolved state, both languages, all report/chat surfaces | NOT VERIFIED by this patch |

The existing launch gate remains **NOT READY**. Do not relabel pending reviews as approvals,
use synthetic scenarios to advertise accuracy, or treat this branch as production deployment.

## Review scenario specification

Reviewers must supply their own expected outcomes before comparing with engine output.
For each of the four schools, cover: first recorded bleeding; exact and approximate start time;
one minute below/at/above each applicable duration boundary; known and unknown preceding purity;
short purity with resumed bleeding; brief discharge; an uncertain day; a missing check-in;
same-day cessation/resumption; correction of a past observation; changed habit; prolonged bleeding;
pregnancy bleeding; postpartum stop/resume; and an unknown or changed madhhab.

Each review row must record: scenario ID, school, complete inputs and missing inputs,
reviewer-authored expected outcome (including defer/ask-more-information), source locator,
reviewer identity/qualification, review date, ruleset version, and disposition.
An engineering-generated expected answer is never a reviewer-approved answer.

For prediction evaluation, hide the next period from the predictor, calculate using only earlier
observations, then compare the held-out start. Report participant and cycle counts, exclusions,
MAE/median absolute error, within ±1/±3/±7-day rates and subgroup results. No clinical acceptance
threshold is invented here. Ovulation estimates require a separate reference standard; period-start
accuracy cannot validate ovulation detection or contraception suitability.

## Verification boundaries

- **115 core tests passed in Asia/Riyadh and America/New_York.** These exercised the real app
  Dart domain services. To run them without Flutter startup, scratch copies of ten pure test files
  replaced only `package:flutter_test/flutter_test.dart` with `package:test/test.dart` (and the
  backtest test's relative import with its absolute source URI). Assertions and app imports were
  unchanged. This is pure Dart test evidence, not a Flutter/widget/integration suite result.
- **27 Python candidate-builder/trust-boundary tests passed.**
- **KB review packet gate passed**, preserving 180 Fiqh rows / 74 Health-Safety rows and no
  fabricated human approvals.
- Dart formatting parsed changed Dart files; Git whitespace checks passed.
- The new Flutter-dependent `fiqh_context_evidence_test.dart`, report/dashboard widget tests,
  analyzer and platform builds remain **NOT RUN** here.

The backtest CLI is `dart run scripts/backtest_cycle_predictions.dart <histories.json>` after
normal project dependency installation. Input is an array of date arrays (YYYY-MM-DD), with no
identifiers. It rejects invalid/duplicate/reversed dates and reports aggregate hold-out errors only.
Its three synthetic regression tests passed; no real clinical dataset was supplied or evaluated.

Local Flutter SDK startup was stopped
by automatic approval review after an attempted instance-metadata request; do not bypass that rejection.
Full GitHub CI must run before merge. The attempted branch push was rejected by automatic approval
review as an unverified/public export. Subsequent read-only verification confirmed that the supplied
repository is public and owned by the connected user `rayan2099` (admin/push permission). The branch
remains local; obtain explicit approval to publish it and open a draft PR rather than bypassing that rejection.
No remote CI result is claimed.
No production data, credentials, migrations or deployments are changed by this remediation.
