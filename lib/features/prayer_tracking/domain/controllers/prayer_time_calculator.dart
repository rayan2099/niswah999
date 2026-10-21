import '../entities/prayer_entry.dart';

class PrayerTimeCalculator {
  const PrayerTimeCalculator();

  /// Absolute instants handle another city's zone and prayers after midnight.
  /// Without tomorrow's schedule there is no known next prayer after Isha.
  static PrayerTimeSlot? nextPrayer({
    required PrayerSchedule schedule,
    required DateTime now,
    PrayerSchedule? tomorrow,
  }) {
    final slots = <PrayerTimeSlot>[];
    for (final day in [schedule, ?tomorrow]) {
      for (final name in PrayerName.values) {
        final time = day.timeFor(name);
        if (time == null) continue;
        final instant = day.instants[name] ?? time.toDateTime(day.date);
        if (!instant.isBefore(now)) {
          slots.add(
            PrayerTimeSlot(name: name, time: time, scheduledAt: instant),
          );
        }
      }
    }
    slots.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return slots.isEmpty ? null : slots.first;
  }

  /// No entry means unrecorded, at every time of day. Do not infer completed,
  /// missed, excused, or qadha from elapsed time or from predicted bleeding.
  static PrayerStatus statusFor({
    required PrayerSchedule schedule,
    required PrayerName prayerName,
    required DateTime now,
  }) => PrayerStatus.pending;
}
