# Cycle sync acknowledgement ownership — 2026-10-30

Stacked on PR #76 at `9c57042c99a26847b211388426a72d21981d1550`. This reconciles another remaining PR #26 safeguard without replacing the newer main storage implementation.

## Finding and correction

A save/replay reads and uploads A's record, then awaits the network. If B becomes active before completion, `setSyncStatusIfUnchanged` previously looked in B's cache. It could leave A's completed upload pending or fail to record A's permanent refusal, causing incorrect retry state. This is distinct from rejecting a foreign record before its initial local save (PR #75).

The [local datasource](../lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart) now accepts an explicit acknowledgement owner while retaining the old default for other callers. [Interactive saves and background replay](../lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart) capture the original storage owner before the first local await and pass it on both success and permanent failure. Existing conditional-content checks and mutation serialization remain; deleted rows are not recreated and newer edits are not overwritten.

The existing test double accepts the optional owner argument. When reconciling this change with PR #62's extended account-switch test file, retain that signature as well as its additional tests.

## Regression evidence to collect

[cycle_sync_snapshot_test.dart](../test/cycle_sync_snapshot_test.dart) ports PR #26's six snapshot cases to the current datasource API: older success/failure versus newer edits, deletion during upload, original acknowledgement bucket, foreign save refusal, and truthful pending state without a configured server. Three additional cases cover delayed permanent failure and background success/failure with another account holding the same synthetic record ID. All nine use synthetic data. The remote request is deliberately delayed/overridden in these tests; token pinning has separate repository regressions.

Dart parsing/formatting, whitespace, four vault tests and generated navigation pass locally. Behavioral CI is pending. This does not establish durable cross-device ordering, exact version/timestamp comparison, A→B→A generation fencing, or account-deletion protection against all future writes. No broad PT/NJ pass or signed-device acceptance is claimed.

## Related verified state

PR #76's targeted bootstrap retry passed after the initial Docker rate limit/port-conflict failure. CI 41008189371 is now green across all current jobs, with 1,605 tests passed and 7 skipped; all four report-owner cases passed. No app source or test gate was altered for that infrastructure retry.

No production mutation, migration, merge, release, prediction-accuracy or medical/scholarly approval is performed or claimed.

Navigation: [tracking](../project-hub/generated/feature-cycle_tracking.md), [quality](../project-hub/generated/Quality-and-Release.md).
