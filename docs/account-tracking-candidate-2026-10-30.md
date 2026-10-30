# Account and tracking candidate — 2026-10-30

This draft combines previously verified safeguards on current main `5a88cd7753914c4dfa5260d0e1950bd622a7ea04`. Separate green branches cannot establish that their combined source compiles or preserves all regressions. This candidate extends PR #69, preserving its real route-boundary/entry-sheet deletion interaction test, and includes the later owner and calculation fixes.

## Source reconciliation

| Source | Included behavior | Reviewed source SHA |
| --- | --- | --- |
| #69 | #62 single-entry read owner; #65 route/recovery/export boundary; #66 interrupted draft; #67 deletion marker; #68 historical cutoff; real screen-disposal interaction | `5370eade073203b97d048db2986b70f3446a678e` |
| #74 | Completed canonical period takes precedence over adjacent projected start and duration | `503e0897fa04449880de73f6bbd2070755f86bd5` |
| #75–77 | Reject foreign save before local write; fence report history across account switches; acknowledge delayed interactive/background sync in original cache | `435c5905624a077d198e0571d13d26214381234b` |

The repository implementation merged without a source conflict. The account-switch test file required retaining #62's three additional single-entry cases while accepting #77's optional acknowledgement owner parameter. Generated maps were regenerated from the final inventory. The historical-date note retains #74's completed-period follow-up. No old PR #26 wholesale merge or prediction-model replacement was attempted.

## Verification

PR #77's exact head above passed CI [41016654784](https://github.com/rayan2099/niswah999/actions/runs/41016654784): 1,614 tests passed, 7 skipped, all nine sync-snapshot cases and 11 existing concurrency regressions passed. Android debug and unsigned iOS compilation, schema rebuild and bootstrap passed. This is source-branch evidence, not combined-candidate evidence.

Combined-candidate behavioral CI is pending. Locally verify Dart parsing/formatting for the resolved test, whitespace, generated navigation and four vault tests. Retain the full existing test suite, including report-owner, save-owner, sync-snapshot, historical-cutoff, completed-authority and account/deletion interaction cases. No skipped test is promoted to a pass.

## Remaining gates and scope

This is an account/tracking integration candidate, not the complete public-launch application. It excludes #60's tracking correction rollout, #63's signup guidance, #70's community UI and #71–73's split/merge and combined SQL candidate. Those changes still require deliberate integration and relevant verification before a release can be identified.

Fresh read-only environment inspection on October 30 confirms staging has correction/removal RPCs but no unknown-end support; production lacks those correction/removal RPCs and unknown-end support. The four reviewed security-definer functions have no anonymous execution grants in either environment. This does not establish every live security or recovery gate. No migrations were applied.

Remaining PR #26 concerns include exact revision/timestamp acknowledgement, A→B→A generation fences, signed-out cache ownership and broader canonical unknown/open conflict handling. Device recovery/tracking acceptance, deployment evidence, launch-scope decisions and specialist evidence remain separate gates. No overall PT/NJ coverage, medical/scholarly approval, prediction accuracy, device validation, deployment or GO is claimed. No merges or production changes were made.

Navigation: [tracking](../project-hub/generated/feature-cycle_tracking.md), [quality](../project-hub/generated/Quality-and-Release.md), [prior integration](account-tracking-integration-2026-10-30.md).
