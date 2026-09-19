import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/notifications/data/local/notification_event_log_store.dart';
import 'package:niswah/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:niswah/features/notifications/domain/entities/notification_event.dart';
import 'package:niswah/features/notifications/domain/entities/notification_preference.dart';
import 'package:niswah/features/notifications/domain/services/notification_refresh_coordinator.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';

const _pluginChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

/// A real open episode, no observations ever recorded — the exact
/// "Niswah is never reopened after the initial scheduling" fixture the
/// charter asks to be simulated: one single coordinator refresh must
/// already leave a full week of genuine, independently-scheduled
/// reminders behind.
class _FakeOpenEpisodeRepository extends BleedingEpisodeRepositoryImpl {
  _FakeOpenEpisodeRepository() : super(client: null);

  @override
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String userId) async {
    return LoadSuccess(
      BleedingEpisode(
        id: 'episode-1',
        userId: userId,
        lifecycleStatus: LifecycleStatus.open,
        continuationCertainty: ContinuationCertainty.confirmed,
        startDate: DateTime(2026, 9, 10),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userObserved,
      ),
    );
  }

  @override
  Future<LoadResult<List<BleedingObservation>>> getObservationsForEpisode(
    String episodeId,
  ) async => const LoadSuccess([]);
}

/// No open episode at all (e.g. it has since ended) — used to verify
/// the recurring fallback gets explicitly cancelled in this case too,
/// not only when the preference itself is disabled.
class _FakeNoOpenEpisodeRepository extends BleedingEpisodeRepositoryImpl {
  _FakeNoOpenEpisodeRepository() : super(client: null);

  @override
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String userId) async {
    return const LoadSuccess(null);
  }
}

/// New critical finding — multi-day notification continuity. Exercises
/// the real NotificationRefreshCoordinator (not just the pure scheduler
/// function) end to end: a single refresh call, simulating the one and
/// only time the app is ever opened, must leave genuinely-scheduled OS
/// notifications and structural audit events behind for every day in
/// the rolling window — proving continuity does not depend on being
/// reopened once per day.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final zonedScheduleCalls = <Map<dynamic, dynamic>>[];
  final cancelledIds = <int>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    zonedScheduleCalls.clear();
    cancelledIds.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'createNotificationChannel':
            case 'getNotificationAppLaunchDetails':
              return null;
            case 'zonedSchedule':
              zonedScheduleCalls.add(call.arguments as Map<dynamic, dynamic>);
              return null;
            case 'cancel':
              cancelledIds.add(call.arguments['id'] as int);
              return null;
            case 'areNotificationsEnabled':
              return true;
            default:
              return null;
          }
        });
    await NotificationService.instance.initialize();

    // activeBleeding defaults OFF (Commit E2) — must be explicitly
    // enabled here, exactly as the real contextual-consent flow would
    // have done, for this refresh to have anything to plan at all.
    final preferenceRepository = NotificationRepositoryImpl();
    final current = await preferenceRepository.loadPreferences();
    current[NotificationType.activeBleeding] =
        current[NotificationType.activeBleeding]!.copyWith(enabled: true);
    await preferenceRepository.savePreferences(current);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, null);
  });

  test('a single refresh (simulating the app never being reopened again) '
      'schedules and structurally audits a full rolling week of distinct '
      'reminder ids, not merely today\'s', () async {
    await NotificationRefreshCoordinator.refresh(
      userId: 'user-1',
      bleedingRepository: _FakeOpenEpisodeRepository(),
      preferenceRepository: null,
    );

    final expectedIds = List.generate(
      7,
      (offset) => ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: DateTime.now().add(Duration(days: offset)),
      ),
    ).map((id) => id.toString()).toSet();

    final allEvents = await NotificationEventLogStore.loadAll();
    final scheduledReminderIds = allEvents
        .where((e) => e.state == NotificationEventState.scheduled)
        .map((e) => e.reminderId)
        .toSet();

    expect(
      scheduledReminderIds,
      expectedIds,
      reason:
          'every one of the 7 rolling days must have its own genuine '
          'scheduled audit event from this single refresh call',
    );
  });

  group('New critical finding — notification continuity beyond 7 days', () {
    test('a refresh also registers the OS-native recurring fallback '
        'alongside the rolling week — one extra pending slot that covers '
        'the app never being reopened past the 7-day window', () async {
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: null,
      );

      final recurringCalls = zonedScheduleCalls.where(
        (args) =>
            args['id'] ==
            NotificationRefreshCoordinator.activeBleedingRecurringFallbackId,
      );
      expect(
        recurringCalls,
        hasLength(1),
        reason: 'exactly one registration for the recurring fallback id',
      );
      expect(
        recurringCalls.single['matchDateTimeComponents'],
        isNotNull,
        reason:
            'must be a genuinely OS-native repeating schedule (matches '
            'only the time component), never a one-off instance the '
            'app would need to reschedule itself',
      );

      final payload = jsonDecode(
        recurringCalls.single['payload'] as String,
      ) as Map<String, dynamic>;
      expect(
        payload['type'],
        ActiveBleedingReminderScheduler.recurringFallbackType,
      );
      expect(payload.containsKey('localDate'), isFalse);
    });

    test('disabling the preference cancels the recurring fallback, not only '
        'the per-day rolling ids', () async {
      final preferenceRepository = NotificationRepositoryImpl();
      final current = await preferenceRepository.loadPreferences();
      current[NotificationType.activeBleeding] =
          current[NotificationType.activeBleeding]!.copyWith(enabled: false);
      await preferenceRepository.savePreferences(current);

      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: preferenceRepository,
      );

      expect(
        cancelledIds,
        contains(
          NotificationRefreshCoordinator.activeBleedingRecurringFallbackId,
        ),
      );
    });

    test(
      'an episode that has since ended cancels the recurring fallback too',
      () async {
        await NotificationRefreshCoordinator.refresh(
          userId: 'user-1',
          bleedingRepository: _FakeNoOpenEpisodeRepository(),
          preferenceRepository: null,
        );

        expect(
          cancelledIds,
          contains(
            NotificationRefreshCoordinator.activeBleedingRecurringFallbackId,
          ),
        );
      },
    );
  });
}
