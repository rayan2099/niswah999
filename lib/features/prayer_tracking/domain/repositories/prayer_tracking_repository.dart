import '../entities/prayer_entry.dart';

abstract class PrayerTrackingRepository {
  Future<List<PrayerEntry>> getDailyPrayerLog(
    DateTime date, {
    required String userId,
  });

  Future<List<PrayerEntry>> getPrayerHistory({
    required String userId,
    DateTime? from,
    DateTime? to,
  });

  Future<void> savePrayer(PrayerEntry entry);

  Future<void> deletePrayer(String id);
}
