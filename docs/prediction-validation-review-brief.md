# Niswah prediction validation: clinical, statistical and data-access brief

Prepared 2026-10-17 for review. **No reviewer approval, data-use agreement or prospective study
is represented as completed.** No researcher has been contacted or agreement signed by this work.

Related: [accuracy research](prediction-accuracy-program.md),
[history-review implementation](prediction-history-review.md),
[Cycle Tracking](../project-hub/generated/feature-cycle_tracking.md),
[existing medical review packet](../production-readiness-results/knowledge-base/MEDICAL_REVIEW_PACKET.csv),
[KB review gate](../production-readiness-results/knowledge-base/REVIEW_READINESS_GATE.md),
[launch gate](../DEFINITION_OF_DONE_BEFORE_LAUNCH.md).

## Intended use and exact research question

Evaluate calendar-based estimates of the next menstrual start for planning, using information
actually available when the estimate is issued. Do not infer pregnancy probability, confirmed
ovulation, contraception effectiveness or fiqh rulings from prediction accuracy.

The research target is **within ±3 civil days of the next actual start**, with issuance coverage
reported beside accuracy. Our current research data establishes next *recorded* starts only;
clinical reviewers must define what constitutes an actual menstrual start and how its timing
is verified. Published correlations, agreement coefficients, phase-classification scores or
±7-day hit rates are not interchangeable with this endpoint.

## Decisions for the clinical reviewer — all pending

| Decision | Engineering behavior to review | Required review outcome |
|---|---|---|
| Onset definition | Start dates currently come from reported bleeding episode timing | Approved distinction between period onset, spotting, non-menstrual bleeding and ambiguous dates; no new facts inferred |
| Population | No representative Saudi validation cohort has been obtained | Supported ages and contexts, approved inclusion/exclusion and separate handling of pregnancy, postpartum/lactation, hormonal contraception, PCOS and perimenopause |
| History completeness | A long recorded gap may be genuine or missed logging | Approved completeness questions, when to defer, and how to adjudicate an answer without rewriting bleeding evidence |
| Eligibility limits | Up to six intervals; historical interval below 15 days gates the full history; recent interval above 90 days gates review; range width above 21 days withholds; last start older than 90 days withholds | Approve, revise or reject each engineering limit with rationale; none is currently a clinical normality threshold |
| Personal-gap rule | More than twice the median of at least three prior usable intervals, with at least 14 days excess, prompts review | Assess false alarms, missed ambiguity, and effect on women with genuine longer cycles |
| Restart after interruption | Two subsequent actual intervals before resuming after a missed/unsure answer | Review minimum evidence needed and wording |
| Disclosure and safety | No guaranteed date; historical ranges are not calibrated probability intervals | Approve Arabic/English copy, unsupported-context behavior, and clinically appropriate escalation language |
| Acceptance | 90% within ±3 days is a research aspiration | Agree clinically meaningful error, coverage, subgroup and range criteria before final testing; no guarantee of reaching 90% |

The clinician should review the actual code/policy version and dated test cases, record reviewer
identity/qualification, scope, decisions, unresolved issues and signature/date. An engineer's
passed check is not a substitute. Re-review is needed if the supported population or algorithm changes.

## Independent dataset request specification — prepared, not sent

Purpose: external validation of a Saudi-focused commercial women's-health app, with permitted
research and commercial-product evaluation explicitly confirmed by the provider. Model selection
and tuning data must be separate from a final locked evaluation cohort. Do not ask for identities.

Minimum useful fields:

- A stable pseudonymous participant key, keeping every segment/device/study round from the same
  person grouped. Relative start-day sequences and their chronology can replace absolute dates.
- Actual observed start events, recording timestamps/precision, missing-entry or completeness
  indicators, and correction provenance. Distinguish non-observation from verified absence.
- Approved context labels needed to identify the supported population and report subgroups;
  request age bands or other sensitive covariates only when justified and permitted.
- Consent scope, ethics/release documentation, data dictionary, permitted uses, retention,
  redistribution/publication restrictions and whether commercial app evaluation is authorized.
- Explanation of repeated IDs, discontinuous history and birth-related flags. Never infer a
  pregnancy-free history merely from absence of a flag.

No minimum sample size is invented here. A statistician should plan the number of independent
participants and follow-up cycles using the desired uncertainty/power and within-person
correlation. Thousands of repeated cycles do not constitute thousands of independent women.

Sources screened and next legitimate access steps:

| Source | Evidence and limitation | Next step |
|---|---|---|
| [mcPHASES, PhysioNet](https://www.physionet.org/content/mcphases/1.0.0/) | Documented consent for release; access requires registration and a signed DUA; only short tracking rounds for many participants | Authorized owner reviews the DUA and permitted use; assess available complete histories before calling it a prediction-validation cohort |
| [Clue research data / 2026 foundation-model study](https://www.nature.com/articles/s44294-026-00142-x) | Real records are not public; article specifies research access by agreement and provides `research@helloclue.com` | Submit an honest access request through the provider's process after owner authorization; clarify commercial evaluation and permitted redistribution |
| [Marquette Menstrual Cycle Data](https://epublications.marquette.edu/data_nfp/7/) | University documents anonymized dissemination and subject reuse consent; ordinary file download returned 403 | Request a working institutional delivery route and applicable reuse terms; no mirror or access-control bypass |
| [Utah Hive cycle data, DOI 10.7278/S50d-4gxs-s4hj](https://doi.org/10.7278/S50d-4gxs-s4hj) | Official repository metadata lists CC BY-NC | Obtain explicit permission suitable for Niswah's intended commercial-product evaluation before use |
| [FitrWoman state-space study](https://www.nature.com/articles/s41598-021-95960-1) | Paper reports licensed-data restrictions; dataset was not obtained | Provider permission and compatible study/data definitions are needed for replication |
| [CILab public prediction code](https://github.com/cilab-ufersa/period_cycle_prediction) | Authors explicitly describe generating synthetic data | May inform software research; does not supply independent real-world validation |

The current Zenodo cohort has already informed development, even if it is repartitioned later.
It cannot become a pristine final test through renaming. Records excluded for birth-related
flags are not automatically an approved independent test cohort either.

## Prospective study protocol — planned, not collecting

1. Obtain the required consent, institutional/data-use review and approved supported-population
   protocol. Keep participation optional and access limited to authorized personnel. Do not
   turn on new production data collection merely because a schema exists.
2. Freeze the model artifact, parameters, data-quality policy, forecast timing, definitions,
   primary/secondary metrics, coverage floor, missingness/attrition plan and subgroup plan before
   the first evaluation participant. A candidate chosen during development is fixed at this point.
3. Save each forecast as issued, before the next onset is known. The
   [forecast-record schema](validation/prediction-accuracy-program-2026-10-17/prospective-forecast.schema.json)
   captures consent/approval references, UTC issue time and local civil date/zone, exact
   model/input-revision hashes, point/range or withholding reason, and reported completeness.
   Hashes are integrity references, not anonymization or evidence of consent.
4. Use an approved protected, append-only research store and independent time/audit controls.
   A local JSON file or self-entered timestamp alone does not prove that a prediction existed
   before its outcome. This repository supplies a contract, not a deployed ledger or trusted clock.
5. Separate day-of-start forecasts from late/backfilled forecasts. Define their timing window
   in advance; never describe late-issued estimates as day-zero predictions. If timing precision
   cannot establish that a forecast preceded onset, label that case rather than inventing a time.
6. Collect outcomes separately and link them to the original forecast ID. Preserve corrections
   as new revisions and retain the original issued prediction. Do not recompute a prediction
   after seeing its outcome and present the replacement as the original.
7. Have outcome/completeness adjudication performed using predeclared rules and, where feasible,
   blinded to candidate estimates. Do not remove a long actual cycle or a large error because
   it makes the model look worse. Predeclare follow-up/censoring, withdrawal and missing-data
   handling; publish their denominators.
8. Report MAE, median/tail error, ±1/±3/±7-day hit rates, forecast coverage and withholding reasons,
   equal-participant results, range coverage/width and subgroup sample sizes. Use grouped/paired
   uncertainty estimates; a statistician should determine confirmatory inference and sample size.
9. For a defensible 90% claim under the frozen research goal: the independent confirmatory lower
   95% bound must reach 90% within ±3 days, coverage must meet the fixed baseline floor on the
   same opportunities, and the clinician-approved population and prospective results must support
   the wording. This is a proposed research gate, not a universal clinical standard.

## Separate fiqh review

Prediction estimates never determine prayer or fasting obligations. Continue the existing
[school-specific scholarly review program](../production-readiness-results/knowledge-base/REVIEW_READINESS_GATE.md)
and [reviewer outreach preparation](../production-readiness-results/knowledge-base/REVIEWER_OUTREACH_TEMPLATES.md).
A clinician's approval of a period prediction is not a scholar's approval of a religious ruling,
and a higher numerical forecasting score does not adjudicate fiqh cases.
