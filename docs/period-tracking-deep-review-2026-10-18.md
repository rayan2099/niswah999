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

## First fixed-tree CI feedback

[Run 39116343016](https://github.com/rayan2099/niswah999/actions/runs/39116343016)
verified all eight original regressions and all five sync-snapshot tests. The full result
was 1,354 passing / four failing / two existing skips. Three failures concerned duplicate
review refresh counts (the first failed test also left a listener alive in that test
isolate); the fourth was an invalid synthetic open-episode fixture missing its required
continuation certainty. The application change now compares committed per-owner review
revisions before/after the refresh, which detects external updates without mistaking its
own delayed broadcast for new evidence. The fixture now satisfies the entity invariant.
The analyzer had zero errors and 25 informational notices; the new queue notice is also
corrected without changing the existing CI ceiling. Follow-up fixed-tree execution remains
required.

The production historical fold exporter was rerun after the timing changes: all 9,263
issued forecasts and withholding decisions are exactly identical to the preceding export
(177 source histories, 11,870 eligible targets, 2,607 withheld). This is a parity check on
the same research input, not an additional independent cohort or evidence of improved
prediction accuracy. Raw participant inputs and fold files remain outside Git.

## Device and server scenarios still to execute

These checks remain **unverified**. A green automated suite does not close them.

| Scenario | Required evidence |
| --- | --- |
| Offline save followed by force-close/restart and reconnect | One canonical operation/observation for the original idempotency key; retained retry payload until acknowledgement; accurate UI sync state. |
| Corrections from two real devices | Conflicting canonical corrections surface the existing conflict state; effective history agrees on both devices after refresh. Also inspect the legacy compatibility view. |
| Account switch during network/storage waits | Neither account displays the other's observations; success/failure acknowledgements touch only the original owner's queue. |
| Account deletion with an already running retry | No completed or newly scheduled callback restores sensitive cache/queue data after cleanup; failures remain observable and cleanup is retried. |
| Timezone/date boundary and actual reminders | Recorded civil dates remain consistent across dashboard/history/report; reminders are delivered/cancelled on supported phones under actual OS background restrictions. |
| Storage read/write/migration failure and recovery | No false save confirmation or confident empty-history inference; preserved inputs can be recovered without changing ownership. |

Legacy offline deletion and cross-device write ordering need a durable server-aware design
and explicit tests before claiming them resolved. These remain engineering gaps, not
items to hide behind a passing calculation percentage. This note records bounded fixes
and the remaining work; it does not certify zero defects.

## Verified fixed-tree app results

[CI run 39117038035](https://github.com/rayan2099/niswah999/actions/runs/39117038035)
on remote commit `a057552ad433d7da3d56f0453663a144d63f1c7c`
(local source commit `1d253c43f3d2ee7910014786da0cd8a99b47d848`, identical Git tree
`5592b18fff5e0408c28ee84897c18b777474690c`) reports:

- **1,359 Flutter tests passed, zero failures, two existing skipped legacy-ring scenarios.**
  The unchanged CI policy excludes platform-dependent golden-image comparison files;
  this result covers the behavioral suite and is not a claim that every test file ran.
- All eight negative-baseline regressions now pass; all six sync-snapshot checks pass.
- Review saves refresh once normally and reload external evidence changed during refresh.
- Replay acknowledgements remain owner-scoped after account changes. The real pinned
  Supabase SDK with mocked HTTP verifies mismatch rejection, original authorization on
  the RPC, and original response ownership after another synthetic account signs in.
- Analyzer: **zero errors, 24 informational notices**, below the unchanged ceiling of 27.
- Database migration rebuild, local bootstrap and secret-redaction checks passed.

Intermediate run 39116812865 passed 1,358 tests, with its sole failure caused by the
mock HTTP response omitting the request metadata required by the pinned PostgREST SDK.
The fixture was corrected to model a real response; the subsequent full run above passed.
Android debug and iOS no-codesign compile outcomes are available in the same linked CI run.
These jobs establish compilation only; actual phone journeys remain unverified.
