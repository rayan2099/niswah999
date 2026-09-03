import '../entities/pregnancy_milestone.dart';

abstract class PregnancyTrackingRepository {
  Future<List<PregnancyMilestone>> getMilestonesForUser(String userId);

  Future<void> saveMilestone(PregnancyMilestone milestone);

  Future<void> deleteMilestone(String id);
}
