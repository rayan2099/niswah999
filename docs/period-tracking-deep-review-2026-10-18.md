# Deeper period-tracking review — 2026-10-18

Scope: concurrent local persistence, account changes during awaited operations, deletion
cleanup, canonical timing under partial daily observations, and sync acknowledgements.
This is an engineering investigation, not a promise of zero defects or perfect forecasts.

Related: [Cycle Tracking](../project-hub/generated/feature-cycle_tracking.md),
[previous integrity review](period-tracking-integrity-review-2026-10-18.md),
[draft PR #26](https://github.com/rayan2099/niswah999/pull/26).

The first commit adds adversarial tests before the corresponding fixes. Suspected defects:
concurrent pending-operation and local-log read/modify/write losing data or reviving a
cleared entry; ambient account changes redirecting awaited writes; pending payloads omitted
from account-deletion cleanup; and partial flow observations inventing a second start inside
an explicitly recorded completed episode. These are hypotheses until execution results are
recorded below. All fixtures are synthetic; no real health records are committed.

Verification and fixes will be recorded after reproduction. Broader release, real-device,
independent prediction and clinical/scholarly review gates remain separate.

## Reproduction and implemented safeguards

The negative baseline was executed against remote commit
`4a46d04c813894ddb04a5889e5dbb90d27573112`, before the fixes below.
[CI run 39115489498](https://github.com/rayan2099/niswah999/actions/runs/39115489498)
reported **1,337 passing tests, eight failures, and two existing skips**. Every newly
introduced regression failed: the seven concurrency/cleanup cases in
[`period_tracking_concurrency_test.dart`](../test/period_tracking_concurrency_test.dart)
and the partial-episode canonical calculation case. The existing suite passing did not
cover these failures.

Implemented, awaiting full Flutter verification on the fixed tree:

- Serialize each local log or pending-operation read/modify/write by category and captured
  owner across datasource instances. A failing transaction does not poison later writes;
  unrelated owners/categories can proceed independently.
- Capture storage ownership before the first await, including legacy migration. Account
  deletion now clears pending-operation payloads as well as the existing registered data.
- Suppress phantom log-derived starts inside an explicitly closed canonical episode.
  Unknown ends remain unknown; partial evidence cannot invent an end.
- Preserve a newer external history-review update arriving while the current save refreshes.
- Match sync acknowledgements to the exact persisted snapshot, so an older success/failure
  cannot overwrite a newer local edit or revive a deleted local record. Missing account
  sync stays pending rather than being reported as synchronized. Pending/failed local edits
  take precedence over stale remote copies in list/report reads.
- Capture replay ownership for queue reads, acknowledgements and retry failures; stop
  scheduling further replay operations after the account changes. Serialize replay passes.
- Interactive canonical writes pass their original account explicitly. Canonical RPCs and
  legacy upserts capture and validate the session before the request and pin authorization
  on that individual request, avoiding a shared-client account switch redirecting the write.
  Start-episode responses retain the original account identity after an awaited response.
  No credentials or real health records are included in fixtures or reports.

[`cycle_calculation_generated_histories_test.dart`](../test/cycle_calculation_generated_histories_test.dart)
checks 1,000 seeded synthetic histories with partial observations, shuffled evidence and
independently calculated starts, intervals and averages. The pure Dart suite currently
passes **225 tests in Asia/Riyadh and America/New_York**, including these generated cases
and queue ordering/isolation/failure tests. Synthetic histories are engineering stress
cases, not clinical validation or independent prediction accuracy evidence.

## Limits and remaining verification

The queue coordinates one running process, not separate devices or isolates. These fixes
are not a durable server-wide conflict-resolution or offline-deletion tombstone protocol.
Legacy remote write/delete ordering, migration failures, tied/incomplete daily timestamps,
process interruption and deletion overlapping newly scheduled background work require
additional review and real-device exercises. Independent historical evaluation and
clinical/scholarly review remain separate gates. Prediction percentages must retain their
stated day tolerance and dataset; no 100% or 90% prediction claim follows from these tests.

Full Flutter analysis, tests, database rebuild and Android/iOS compilation results will be
appended after execution. This review does not authorize merging, deploying or certifying
launch readiness.
