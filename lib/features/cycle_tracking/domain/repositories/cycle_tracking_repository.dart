import '../../domain/entities/cycle_log.dart';

abstract class CycleTrackingRepository {
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  });

  Future<CycleLog?> getCycleLogById(String id);

  Future<void> saveCycleLog(CycleLog log);

  Future<void> upsertCycleLog(CycleLog log);

  Future<void> deleteCycleLog(String id);

  Future<List<CycleLog>> syncPendingLogs();
}
