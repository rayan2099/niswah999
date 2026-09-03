import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/notifications/domain/entities/notification_preference.dart';

void main() {
  group('Notification preference model', () {
    test('serializes and deserializes preference values', () {
      final preference = NotificationPreference(
        type: NotificationType.prayer,
        enabled: true,
        leadTimeMinutes: 15,
        channels: const ['morning', 'midday'],
      );

      final json = preference.toJson();
      final restored = NotificationPreference.fromJson(json);

      expect(restored.type, NotificationType.prayer);
      expect(restored.enabled, isTrue);
      expect(restored.leadTimeMinutes, 15);
      expect(restored.channels, ['morning', 'midday']);
    });

    test('builds a daily schedule from a preference set', () {
      final preferences = {
        NotificationType.prayer: NotificationPreference(
          type: NotificationType.prayer,
          enabled: true,
          leadTimeMinutes: 10,
          channels: const ['fajr', 'dhuhr'],
        ),
        NotificationType.cycle: NotificationPreference(
          type: NotificationType.cycle,
          enabled: false,
          leadTimeMinutes: 30,
          channels: const ['cycle'],
        ),
      };

      final schedule = buildReminderSchedule(preferences: preferences, now: DateTime(2026, 8, 18, 9, 0));

      expect(schedule[NotificationType.prayer]?.enabled, isTrue);
      expect(schedule[NotificationType.cycle]?.enabled, isFalse);
      expect(schedule[NotificationType.prayer]?.leadTimeMinutes, 10);
    });
  });
}
