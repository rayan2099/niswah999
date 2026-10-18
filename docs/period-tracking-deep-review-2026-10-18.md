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
