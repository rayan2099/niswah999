import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/core/preferences/notification_log_controller.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/notification_delivery_preferences.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:niswah/features/notifications/domain/entities/notification_preference.dart';
import 'package:niswah/features/notifications/domain/services/notification_refresh_coordinator.dart';

import 'support/notification_platform_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NotificationPlatformHarness os;
  setUp(() async {
    os = NotificationPlatformHarness();
    await os.install();
  });
  tearDown(() async {
    await os.uninstall();
  });
  test(
    'quiet hours cancel an old scheduled slot and do not issue a replacement',
    () async {
      final s = NotificationService.instance;
      await s.scheduleAt(
        id: 7,
        title: 'Niswah',
        body: 'Generic',
        when: AppClock.now().add(const Duration(hours: 14)),
      );
      expect(os.pending, contains(7));
      final prefs = NotificationDeliveryPreferences.instance;
      prefs.apply({...prefs.toJson(), 'quiet_enabled': true});
      expect(
        await s.scheduleAt(
          id: 7,
          title: 'Niswah',
          body: 'Generic',
          when: AppClock.now().add(const Duration(hours: 14)),
        ),
        NotificationSchedulingOutcome.quietHours,
      );
      expect(os.pending, isNot(contains(7)));
      expect(
        await s.scheduleDaily(
          id: 8,
          title: 'Niswah',
          body: 'Generic',
          hour: 23,
          minute: 0,
        ),
        NotificationSchedulingOutcome.quietHours,
      );
    },
  );
  test('new reminder slots do not collide and carry destinations for the signed-in account', () async {
    final repo = NotificationRepositoryImpl();
    final prefs = await repo.loadPreferences();
    await repo.savePreferences({
      for (final e in prefs.entries)
        e.key: e.value.copyWith(
          enabled:
              e.key == NotificationType.wellbeing ||
              e.key == NotificationType.learning,
        ),
    });
    await NotificationRefreshCoordinator.refresh(userId: 'u');
    expect(os.pending.keys.toSet(), {
      NotificationRefreshCoordinator.wellbeingReminderId,
      NotificationRefreshCoordinator.learningReminderId,
    });
    expect(
      jsonDecode(os.pending[104]!['payload'] as String)['destination'],
      'wellbeing',
    );
    expect(
      jsonDecode(os.pending[106]!['payload'] as String)['destination'],
      'learning',
    );
    expect(jsonDecode(os.pending[106]!['payload'] as String)['userId'], 'u');
    expect({101, 102, 103, 104, 105, 106}.length, 6);
  });
  test(
    'prayer phone alerts and feed entries open prayer tracking, not pregnancy',
    () async {
      final repo = NotificationRepositoryImpl();
      final prefs = await repo.loadPreferences();
      await repo.savePreferences({
        for (final e in prefs.entries)
          e.key: e.value.copyWith(enabled: e.key == NotificationType.prayer),
      });
      await PrayerLocationController.instance.select(
        PrayerLocationController.mecca,
      );
      await NotificationRefreshCoordinator.refresh(userId: 'u');
      final prayers = os.pending.values.where(
        (p) => (p['id'] as int) >= 200 && (p['id'] as int) < 225,
      );
      expect(prayers, isNotEmpty);
      for (final p in prayers) {
        expect(jsonDecode(p['payload'] as String)['destination'], 'prayer');
      }
      final feed = NotificationLogController.instance.allEntries.where(
        (e) => e.type == NotificationType.prayer,
      );
      expect(feed.length, prayers.length);
      expect(feed.every((e) => e.target?.destination.name == 'prayer'), true);
    },
  );
  test('fertility alert follows eligible calendar estimates and cancels when history is unavailable', () async {
    AppClock.now = () => DateTime.utc(2030, 1, 7, 9);
    final repo = NotificationRepositoryImpl();
    final prefs = await repo.loadPreferences();
    await repo.savePreferences({
      for (final e in prefs.entries)
        e.key: e.value.copyWith(
          enabled: e.key == NotificationType.fertility,
          preferredHour: 10,
          preferredMinute: 0,
        ),
    });
    final history = [
      CanonicalEpisodeTiming(
        startDate: DateTime(2029, 12, 4),
        endDate: DateTime(2029, 12, 9),
      ),
      CanonicalEpisodeTiming(
        startDate: DateTime(2030, 1, 1),
        endDate: DateTime(2030, 1, 6),
      ),
    ];
    await NotificationRefreshCoordinator.refresh(
      userId: 'u',
      bleedingRepository: BleedingEpisodeRepositoryImpl(client: null),
      cycleHistoryLoader: (_) async => history,
    );
    final request =
        os.pending[NotificationRefreshCoordinator.fertilityReminderId];
    expect(request, isNotNull);
    final start = const CycleTrackingController()
        .summarizeHistory([], now: AppClock.now(), canonicalEpisodes: history)
        .fertileWindow
        .start!;
    final date =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    expect(request!['scheduledDateTime'], '${date}T10:00:00');
    expect(jsonDecode(request['payload'] as String)['destination'], 'calendar');
    await NotificationRefreshCoordinator.refresh(
      userId: 'u',
      bleedingRepository: BleedingEpisodeRepositoryImpl(client: null),
      cycleHistoryLoader: (_) async => null,
    );
    expect(
      os.pending,
      isNot(contains(NotificationRefreshCoordinator.fertilityReminderId)),
    );
  });
}
