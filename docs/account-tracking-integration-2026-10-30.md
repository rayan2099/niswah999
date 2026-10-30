# Account and tracking integration candidate — 2026-10-30

This is an isolated review candidate based on main `5a88cd7753914c4dfa5260d0e1950bd622a7ea04`. It does not merge or publish the source PRs. All unrelated local worktrees remain untouched.

## Exact inputs

| Source | Commit | Scope |
|---|---|---|
| PR #62 | `6a90a16aba5790ff479602b5ac862340b0031628` | Single-entry read owner/token guards and test helper |
| PR #65 | `1ca3553e4e383ba8eacf372c1b63a7e11bc11a1e` | Close private routes on account changes; export and recovery guards |
| PR #66, included through #67 | `99fa8274e3cae51b93ae3e09bc5bec67da3346e6` | Owner-scoped interrupted entry drafts |
| PR #67 | `d5e72fd9b790389a80cdd9da6d238f07948b3cb3` | Durable deletion marker for entry drafts |
| PR #68 | `bcc611f1d0afce5d3d5658533de2a38ae451325b` | Historical civil-date calculation boundaries |

Source snapshots are copied only for their changed files against the shared main base; #67 deliberately supersedes #66's draft store and cleanup registration. Generated navigation is rebuilt for the combined tree. The source PRs remain independent review units. This candidate does not include PR #60's tracking UI/migrations, #63's signup guidance, or every outstanding release fix; it cannot represent the full release artifact.

## Combined behavior to verify

The [entry draft suite](../test/account_isolation/entry_draft_after_session_end_test.dart) now mounts the real [AccountRouteBoundary](../lib/core/auth/account_route_boundary.dart) observer. Its new case opens a real day-log sheet, enters private notes, runs account-deletion cleanup, then notifies an account switch. The boundary must close the sheet without a manual pop, and its disposal must not recreate a draft for either account. Existing expiry/restore, discard, deletion and persistent-marker tests remain.

Other included regressions exercise delayed remote reads, export/account transitions, recovery account identity and historical calculation cutoffs. Their previously green individual CI is not evidence that the combined candidate passes. No overall PT/NJ journey totals are inferred from suite counts.

## Prior individual evidence

- #62: CI 40960318626, 1,601 passed, 7 skipped, all jobs green.
- #67: CI 40967719222, 1,605 passed, 7 skipped, all jobs green.
- #68: CI 40972953852, 1,603 passed, 7 skipped, all five boundary tests explicitly pass; all jobs green.

These native jobs are Android debug and iOS no-codesign compilation. They do not establish signed-device acceptance, runtime notification delivery, clinical/scholarly approval, prediction accuracy or environment deployment.

## Verification and decision

Dart formatting/parser, whitespace, generated navigation and four vault tests pass locally. Combined behavioral CI is pending. No local Flutter setup workaround is attempted after the earlier metadata-access review block. No main ref, production data, migration or release is changed.

Launch remains NO-GO. Missing environment rollout, signed-device recovery/tracking, specialist evidence and the remaining scoped [PR #26 reconciliation](tracking-asof-reconciliation-2026-10-30.md) obligations remain open.

Navigation: [tracking](../project-hub/generated/feature-cycle_tracking.md), [auth](../project-hub/generated/feature-auth.md), [quality](../project-hub/generated/Quality-and-Release.md).
