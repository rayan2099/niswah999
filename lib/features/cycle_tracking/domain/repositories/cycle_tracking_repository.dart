import '../../domain/entities/cycle_log.dart';

abstract class CycleTrackingRepository {
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  });

  Future<CycleLog?> getCycleLogById(String id);

  /// Always saves locally first (authoritative for the UI). Returns `true`
  /// if the remote sync also succeeded, `false` if it failed — local-only
  /// saves are never silently indistinguishable from synced ones (DI-002).
  Future<bool> saveCycleLog(CycleLog log);

  Future<void> upsertCycleLog(CycleLog log);

  Future<void> deleteCycleLog(String id);

  Future<List<CycleLog>> syncPendingLogs();
}
