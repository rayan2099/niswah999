# Exact local cycle sync acknowledgement — 2026-10-30

Stacked on PR #79 head `4477d1b124aa6c987ff4491d1c40834112b3c56b`. This is another focused PR #26 reconciliation against the newer serialized local datasource, not a merge of the old storage implementation.

## Finding and implementation

PR #77 pins the acknowledgement cache owner, but the conditional comparison still removed all timestamps. A delayed success or permanent failure could acknowledge a newer save with identical health content and a different `updated_at`. The comparison also ignored a completed sync-status transition, allowing a second delayed failure to downgrade an already synced row.

The [local datasource](../lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart) now includes stable transport timestamps in the snapshot comparison and requires the stored status to match the uploaded status before changing it (an already matching target status is an idempotent success). Deleted rows remain absent; serialized mutation and explicit owner capture remain unchanged.

`CycleLog.toJson()` fills missing timestamps from the current clock. Merely retaining timestamp fields in the comparison would therefore stop acknowledgements of an unstamped interactive save: separate cache/upload/ack serializations would create different revisions. The [repository](../lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart) freezes missing creation/update timestamps once before the local write, and uses that same immutable snapshot for upload and acknowledgement. Explicitly supplied timestamps are preserved. Background replay already reads a serialized snapshot containing timestamps.

## Verification

[The snapshot suite](../test/cycle_sync_snapshot_test.dart) retains the nine prior account/edit/deletion cases and adds four: delayed success and permanent failure versus a timestamp-only newer save, a delayed failure after success, and a save without supplied timestamps that must reach synced with the exact uploaded revision. These use synthetic local storage and deliberately held uploads; no real health data or live server is involved.

Dart parsing/formatting, whitespace, generated navigation and six Python vault/migration tests pass locally. Behavioral verification is pending in CI. The tests are not a proof of server ordering: an older network request may still reach the server later, identical timestamps are not a globally unique revision, save return values describe that request rather than the latest local row, and multi-device/server compare-and-set is not implemented here. No A→B→A generation, signed-out ownership or deletion fence for all future writes is claimed.

## Launch limits

The prior #79 head's full app verification is still running at the start of this work; its SQL/schema/bootstrap jobs passed. Fresh staging/production checks still show the previously recorded rollout gaps. No migration, environment mutation, main merge or deployment is performed. Public launch remains NO-GO; device, specialist, operating-process and remaining engineering gates are independent.

Navigation: [tracking](../project-hub/generated/feature-cycle_tracking.md), [quality](../project-hub/generated/Quality-and-Release.md), [original acknowledgement ownership](cycle-sync-ack-owner-2026-10-30.md).
