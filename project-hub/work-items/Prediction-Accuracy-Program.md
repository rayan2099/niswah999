---
type: work-item
status: in-progress
area: cycle_tracking
owner: unassigned
reviewed_on: 2026-10-18
---

# Prediction accuracy: controlled research complete, external validation pending

## Problem and acceptance criteria

Aim for 90% of issued period-start forecasts within ±3 days without improving the score by
withholding more cases. Require an independently evaluated supported population and prospective
evidence before a public accuracy claim; keep actual observations and fiqh review separate.

## References and dependencies

- [Controlled experiment, results and implementation](../../docs/prediction-accuracy-program.md)
- [Frozen protocol](../../docs/validation/prediction-accuracy-program-2026-10-17/protocol.json)
- [Clinical, data access and prospective review brief](../../docs/prediction-validation-review-brief.md)
- [Cycle Tracking](../generated/feature-cycle_tracking.md)
- [Earlier history-review task](Prediction-History-Review.md)
- [Launch gate](../../DEFINITION_OF_DONE_BEFORE_LAUNCH.md)

## Outcome and verification

Ten methods compared with identical eligibility. Group-selected trimmed mean reached 81.03%
versus 80.28% for the default at unchanged 78.04% coverage on the previously examined cohort.
90% was not reached. A trimmed-mean candidate is implemented for explicit evaluation; the
default remains unchanged. Runtime parity, 202 pure Dart checks in two zones and 15 Python
evaluation checks pass; prospective record structure was checked with synthetic records only.

Open: eligible independent data access, clinician/statistician decisions, prospective study,
Flutter/device verification and separate scholarly approval. No agreements were signed,
messages sent, production data collected or deployment performed by this work.
