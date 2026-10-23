import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../../../../core/preferences/prayer_location_controller.dart';
import '../../../prayer_tracking/domain/entities/prayer_entry.dart';
import '../../../prayer_tracking/domain/services/prayer_schedule_builder.dart';
import 'notification_scheduler.dart';

/// Five days x five prayers = 25 requests. With 30 tracking check-ins,
/// wellbeing, cycle, pregnancy and nifas, the app owns at most 59 slots,
/// below iOS's 64-request ceiling. Refresh extends this bounded window.
class PrayerReminderScheduler {
  static const daysAhead = 5;
  static const firstId = 200;
  static const slotCount = daysAhead * 5;
  static Iterable<int> get ids =>
      Iterable.generate(slotCount, (i) => firstId + i);

  static List<PlannedNotification> plan({
    required String userId,
    required PrayerLocation? location,
    required DateTime now,
    required String method,
    required bool hanafiAsr,
    required int leadMinutes,
    DateTime? ramadanAdjustmentUntil,
  }) {
    if (location == null || leadMinutes < 0 || leadMinutes > 120) {
      return const [];
    }
    try {
      final zone = PrayerScheduleBuilder.zoneFor(location);
      final today = tz.TZDateTime.from(now, zone);
      final plans = <PlannedNotification>[];
      for (var day = 0; day < daysAhead; day++) {
        final schedule = PrayerScheduleBuilder.build(
          location: location,
          now: tz.TZDateTime(
            zone,
            today.year,
            today.month,
            today.day + day,
            12,
          ),
          method: method,
          hanafiAsr: hanafiAsr,
          ramadanAdjustmentUntil: ramadanAdjustmentUntil,
        );
        for (final name in PrayerName.values) {
          final fireAt = schedule.instants[name]!.subtract(
            Duration(minutes: leadMinutes),
          );
          if (!fireAt.isAfter(now)) continue;
          plans.add(
            PlannedNotification(
              id: firstId + day * 5 + name.index,
              fireAt: fireAt.toUtc(),
              titleAr: NotificationScheduler.discreetTitleAr,
              bodyAr: NotificationScheduler.discreetBodyAr,
              titleEn: NotificationScheduler.discreetTitleEn,
              bodyEn: NotificationScheduler.discreetBodyEn,
              payload: jsonEncode({'type': 'prayerReminder', 'userId': userId}),
            ),
          );
        }
      }
      return plans;
    } catch (_) {
      // Missing/unconfirmed zones and unsupported polar dates never create
      // guessed prayer reminders. The settings screen explains setup.
      return const [];
    }
  }
}
