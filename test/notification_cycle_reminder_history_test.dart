import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/notifications/domain/services/notification_refresh_coordinator.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';

class _RecordingCycleRepository extends CycleTrackingRepositoryImpl {
  _RecordingCycleRepository() : super(client: null);
  final limits = <int>[];

  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    limits.add(limit);
    return const [];
  }
}

const _pluginChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

/// The period reminder is planned from the same canonical (onboarding)
/// history the dashboard predicts from, and never from history known to
/// be incomplete.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pending = <int, Map<String, dynamic>>{};

  setUp(() async {
    AppClock.now = () => DateTime(2026, 10, 10, 9);
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    pending.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, (call) async {
          switch (call.method) {
            case 'initialize':
            case 'areNotificationsEnabled':
              return true;
            case 'zonedSchedule':
              final args = call.arguments as Map<dynamic, dynamic>;
              pending[args['id'] as int] = {'id': args['id']};
              return null;
            case 'cancel':
              pending.remove(call.arguments['id'] as int);
              return null;
            case 'cancelAll':
              pending.clear();
              return null;
            case 'pendingNotificationRequests':
              return pending.values.toList();
            default:
              return null;
          }
        });
    await NotificationService.instance.initialize();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, null);
    AppClock.reset();
  });

  // Two onboarding-reported periods 28 days apart; the next is due Oct 29.
  final onboardingHistory = [
    CanonicalEpisodeTiming(
      startDate: DateTime(2026, 9, 3),
      endDate: DateTime(2026, 9, 8),
    ),
    CanonicalEpisodeTiming(
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 6),
    ),
  ];

  test('canonical history alone is enough to plan the reminder', () async {
    await NotificationRefreshCoordinator.refresh(
      userId: 'user-1',
      bleedingRepository: BleedingEpisodeRepositoryImpl(client: null),
      cycleHistoryLoader: (_) async => onboardingHistory,
    );

    expect(pending.keys, contains(NotificationScheduler.cycleNotificationId));
  });

  test(
    'a degraded (partly quarantined) history cancels the reminder',
    () async {
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: BleedingEpisodeRepositoryImpl(client: null),
        cycleHistoryLoader: (_) async => onboardingHistory,
      );
      expect(pending.keys, contains(NotificationScheduler.cycleNotificationId));

      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: BleedingEpisodeRepositoryImpl(client: null),
        cycleHistoryLoader: (_) async => null,
      );

      expect(
        pending.keys,
        isNot(contains(NotificationScheduler.cycleNotificationId)),
      );
    },
  );

  test('the reminder reads the same history window as the view model '
      '(prediction-efficiency audit, 2026-10-21)', () async {
    final repository = _RecordingCycleRepository();
    await NotificationRefreshCoordinator.refresh(
      userId: 'user-1',
      cycleRepository: repository,
      bleedingRepository: BleedingEpisodeRepositoryImpl(client: null),
      cycleHistoryLoader: (_) async => onboardingHistory,
    );
    expect(repository.limits, [CycleCalculationService.historyLogLimit]);
  });
}
