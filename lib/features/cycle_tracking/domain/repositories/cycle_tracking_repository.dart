import '../../domain/entities/cycle_log.dart';

class CyclePendingSyncResult {
  const CyclePendingSyncResult({
    required this.synced,
    required this.stillPending,
    required this.permanentlyFailed,
  });

  final int synced;
  final int stillPending;
  final int permanentlyFailed;

  bool get hadWork => synced + stillPending + permanentlyFailed > 0;
}

abstract class CycleTrackingRepository {
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  });

  Future<CycleLog?> getCycleLogById(String id);

  /// Always saves locally first (authoritative for the UI). Returns the
  /// resulting [SyncStatus]: `synced` if the remote write also succeeded;
  /// `pending` if it failed but will be retried automatically (a
  /// transient/network condition — see `syncPendingLogs`); `failed` if it
  /// failed for a reason retrying won't fix (a validation/policy
  /// rejection) — local-only saves are never silently indistinguishable
  /// from synced ones, and the caller can tell "will auto-retry" apart
  /// from "won't" (DI-002, RR-001).
  Future<SyncStatus> saveCycleLog(CycleLog log);

  Future<void> upsertCycleLog(CycleLog log);

  Future<void> deleteCycleLog(String id);

  /// Retries every locally-stored log still marked [SyncStatus.pending]
  /// against the remote table (idempotent — the remote upsert is keyed by
  /// `id`, so a retry of an already-synced row is a safe no-op). A log
  /// whose failure is classified non-retryable (e.g. a policy/validation
  /// rejection, not a network condition) is marked [SyncStatus.failed]
  /// instead and is *not* retried again automatically — see
  /// `mapRepositoryError`'s retryable classification.
  Future<CyclePendingSyncResult> syncPendingLogs();
}
