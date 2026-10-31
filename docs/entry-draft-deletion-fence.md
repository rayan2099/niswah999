# Entry drafts after account deletion — 2026-10-30

Scope: follow-up to PR #66 (`99fa8274e3cae51b93ae3e09bc5bec67da3346e6`), intended to work alongside PR #65's account route boundary. This is a focused NJ-054/NJ-182 deletion invariant, not complete journey acceptance.

## Trigger and correction

[Account deletion](../lib/features/auth/domain/account_deletion_orchestrator.dart) cleans local data before local sign-out. The [entry sheet](../lib/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart) saves changed values to a draft when disposed after an account change. With ordinary deletion of the draft slot, that late save can recreate private notes after deletion cleanup succeeds.

[CycleLogDraftStore](../lib/features/cycle_tracking/data/local/cycle_log_draft_store.dart) now serializes writes, normal clears and account-deletion cleanup per explicit account. Confirmed deletion replaces the draft with a durable marker in the same encrypted slot. The marker holds no form values; later writes and normal discard/save cleanup preserve it. A new account ID uses its own slot. This assumes deleted account IDs are not reused. Retaining this local marker is intentional to prevent old callbacks restoring deleted content.

[Cleanup registration](../lib/core/storage/local_sensitive_data_cleanup.dart) uses the deletion-specific method. Normal session expiry still keeps a draft for the original account. This change does not fence other storage categories or establish general cross-process storage ordering.

## Verification

[Regression tests](../test/account_isolation/entry_draft_after_session_end_test.dart) cover cleanup-before-sign-out sheet disposal, writes queued on both sides of deletion, later discard and write, another account's independent draft, and a restart simulated by reinitializing the platform fake from persisted state. Existing restore/discard/session-change tests remain.

Dart parsing/formatting, whitespace and project-vault checks pass locally. Flutter behavioral verification requires CI; local package dependencies are unavailable. No device acceptance or general account-deletion pass is claimed. No migration or production mutation is involved.

## Related verified evidence

PR #62 at `6a90a16aba5790ff479602b5ac862340b0031628`: CI [40960318626](https://github.com/rayan2099/niswah999/actions/runs/40960318626) passes all jobs, with 1,601 behavioral tests passed and 7 skipped. Logs explicitly pass the three single-entry account-switch regressions and 11 concurrency tests originally introduced/extended through #45. Native checks are Android debug and iOS no-codesign compilation, not signed-device acceptance. These results do not verify the draft change in this branch.

PR #26 remains unsuitable for a wholesale merge. Main contains later local serialization/owner capture and conditional sync acknowledgment. Retry/deletion fencing, A→B→A transitions, cross-device writes, and native recovery remain separate acceptance obligations.

Navigation: [tracking feature](../project-hub/generated/feature-cycle_tracking.md), [quality map](../project-hub/generated/Quality-and-Release.md).
