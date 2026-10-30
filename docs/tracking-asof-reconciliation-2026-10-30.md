# Tracking PR #26 reconciliation — 2026-10-30

Reviewed main: `5a88cd7753914c4dfa5260d0e1950bd622a7ea04`. This branch ports only historical civil-date filtering, retaining the current prediction model and canonical merge behavior.

## Finding and change

[CycleCalculationService.calculate](../lib/features/cycle_tracking/domain/services/cycle_calculation_service.dart) used `asOf` to label the current day but still built starts, intervals and durations from all supplied records. A later recorded start could move the historical anchor forward; a future end could become a measured historical period length.

Filter legacy observations and canonical starts by the requested civil date. Withhold canonical ends after that date in the derived view. An event later on the same civil date remains eligible: this is date-based tracking, not an instant-based audit of what was known at an earlier time of day. Capture the date once per calculation. Stored facts are not modified.

Five [regressions](../test/cycle_calculation_asof_boundary_test.dart) cover future legacy starts and ends, canonical starts on and after the cutoff date, a future canonical end without mutating the input, and an end on the cutoff civil date.

## Reconciliation by concern

| PR #26 concern | Current disposition |
|---|---|
| Concurrent local mutation and owner capture | Later main commits serialize mutations and capture owners. The original seven plus four extended regressions pass in PR #62 CI 40960318626; this is not general cross-device ordering proof. |
| Pending-operation account-deletion cleanup | Registered on main; targeted concurrency test passes. A late write after cleanup remains a separate invariant per storage category. |
| Phantom starts inside a completed canonical span | Main's `_mergeCanonical` suppresses log-derived starts inside canonical spans. Do not replace it wholesale with the old branch algorithm. |
| Historical date cutoff | Missing on reviewed main; focused implementation and five tests added here, behavioral CI pending. |
| Canonical start/duration precedence | Not completely reconciled: main intentionally retains a log start one day before a canonical start. Old #26 would prefer canonical timing. Needs a focused regression and authority decision; not closed here. |
| Sync snapshot acknowledgment | Main has `setSyncStatusIfUnchanged` and local-first pending merge; timestamp/version, owner-transition and deletion races remain separate review items. |
| Single-entry delayed reads | PR #62 is verified at 6a90a16: 1,601 tests passed, 7 skipped; all jobs green in CI 40960318626. It remains unmerged. |
| Draft recreation after account deletion | PR #67 is verified at d5e72fd: 1,605 tests passed, 7 skipped; all three deletion regressions and four existing draft tests pass in CI 40967719222. Stacked on #66; unmerged. |
| Reminder cancellation and calendar arithmetic | Main has civil-day helpers, generation guards and local opt-outs before network work; device delivery and cancellation remain native acceptance obligations. |
| History-review revisions, retries and cross-device ordering | Not closed by this pass. Preserve the newer main model and port only demonstrated missing behavior. |

## Verification and launch decision

Local Dart formatting/parser, whitespace, project-map generation/check and four vault tests pass. Behavioral verification for this branch is pending CI; do not infer it from #62 or #67. Local Flutter setup is unavailable following automatic approval review's block of a cloud-metadata side effect; no workaround is attempted.

Public-launch GO is not established. Signed-device recovery/tracking, required environment rollout and specialist evidence remain independent gates. No prediction accuracy, clinical/scholarly approval, signed-device pass, deployment or overall PT/NJ coverage total is established by this code change.

Navigation: [tracking](../project-hub/generated/feature-cycle_tracking.md), [quality](../project-hub/generated/Quality-and-Release.md).

## Completed canonical authority follow-up

A focused follow-up now handles a completed canonical period adjacent to an earlier compatibility start. The existing one-day deduplication policy remains; when the canonical candidate has a measured duration, both its explicit date and duration replace the earlier projected pair. This preserves a known five-day period that previously disappeared from duration statistics, or was replaced by a conflicting nine-day projection. Two regressions in `test/cycle_calculation_completed_authority_test.dart` assert the corrected 27-day interval and equal-weight mean duration. This is derived-statistics precedence, not a change to stored observations or a religious/medical classification. Unknown/open canonical timings and broader conflicts remain unreconciled.

The historical-cutoff portion at bcc611f is independently verified by CI 40972953852 (1,603 passed, 7 skipped, all jobs green). The completed-authority follow-up is parsed/formatted and statically checked locally; its behavioral CI is pending. The earlier table's blanket canonical-precedence blocker is narrowed only for completed canonical periods with a measured end; no broader closure is claimed.
