import '../entities/prayer_entry.dart';

class PrayerTimeCalculator {
  const PrayerTimeCalculator();

  static PrayerTimeSlot nextPrayer({
    required PrayerSchedule schedule,
    required DateTime now,
  }) {
    final currentDate = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(
      schedule.date.year,
      schedule.date.month,
      schedule.date.day,
    );

    final slots = PrayerName.values.map((prayerName) {
      final time = schedule.timeFor(prayerName);
      if (time == null) {
        throw StateError('Missing prayer slot for $prayerName');
      }
      return PrayerTimeSlot(
        name: prayerName,
        time: time,
        scheduledAt: time.toDateTime(targetDate),
      );
    }).toList();

    for (final slot in slots) {
      if (currentDate.isAtSameMomentAs(targetDate) &&
          now.isBefore(slot.scheduledAt)) {
        return slot;
      }
    }

    return slots.last;
  }

  static PrayerStatus statusFor({
    required PrayerSchedule schedule,
    required PrayerName prayerName,
    required DateTime now,
  }) {
    final time = schedule.timeFor(prayerName);
    if (time == null) {
      return PrayerStatus.pending;
    }

    final scheduledAt = time.toDateTime(schedule.date);
    if (now.isBefore(scheduledAt)) {
      return PrayerStatus.pending;
    }
    if (now.isAtSameMomentAs(scheduledAt)) {
      return PrayerStatus.completed;
    }
    return PrayerStatus.missed;
  }
}
