import '../entities/pregnancy_milestone.dart';

class PregnancyMilestonePendingSyncResult {
  const PregnancyMilestonePendingSyncResult({
    required this.synced,
    required this.stillPending,
    required this.permanentlyFailed,
  });

  final int synced;
  final int stillPending;
  final int permanentlyFailed;

  bool get hadWork => synced + stillPending + permanentlyFailed > 0;
}

abstract class PregnancyTrackingRepository {
  Future<List<PregnancyMilestone>> getMilestonesForUser(String userId);

  /// Saves locally first (local-authoritative), then attempts a remote
  /// write. Returns the resulting sync status so the caller can show
  /// accurate feedback rather than assuming success.
  Future<PregnancySyncStatus> saveMilestone(PregnancyMilestone milestone);

  Future<void> deleteMilestone(String id);

  /// Retries any locally-`pending` milestones against the remote — call
  /// from wherever this feature's own lifecycle makes sense (this feature
  /// has no app-wide lifecycle hook the way cycle tracking does via
  /// NiswahHomeShell, since it isn't reachable from app navigation today —
  /// see the wave report).
  Future<PregnancyMilestonePendingSyncResult> syncPendingMilestones();
}
