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
      'schedules and structurally audits a full rolling window of distinct '
      'reminder ids, not merely today\'s', () async {
    // Fix 6 (regression-baseline reconciliation) — BleedingEpisodeRepositoryImpl
    // .localToday is a deliberately real-wall-clock-only pure function
    // (see its own dedicated test/doc comment, PR #4 hardening Blocker
    // 7) — it is not, and must not become, AppClock-injectable. The
    // prior flakiness came from this test independently re-deriving
    // "today" via a second, separate clock read instead of mirroring
    // the exact same derivation the coordinator itself uses — computed
    // once, immediately before the single call that consumes it, to
    // keep the two as close together as this design allows.
    final today = BleedingEpisodeRepositoryImpl.localToday(
      DateTime.now().timeZoneOffset.inMinutes,
    );
    await NotificationRefreshCoordinator.refresh(
      userId: 'user-1',
      bleedingRepository: _FakeOpenEpisodeRepository(),
      preferenceRepository: null,
    );

    final expectedIds = List.generate(
      ActiveBleedingReminderScheduler.defaultRollingWindowDays,
      (offset) => ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: today.add(Duration(days: offset)),
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
          'every one of the rolling window\'s days must have its own '
          'genuine scheduled audit event from this single refresh call',
    );
  });

  group('New critical finding — single-owner scheduling policy (fixes a '
      'real, immediate duplicate-notification defect the prior hybrid '
      'design had)', () {
    test('a single refresh schedules exactly one OS notification per local '
        'day, covering at least 15 days including the day-seven/day-eight '
        'transition — no second, overlapping mechanism', () async {
      final today = BleedingEpisodeRepositoryImpl.localToday(
        DateTime.now().timeZoneOffset.inMinutes,
      );
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: null,
      );

      final activeBleedingIds = List.generate(
        ActiveBleedingReminderScheduler.defaultRollingWindowDays,
        (offset) => ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: today.add(Duration(days: offset)),
        ),
      ).toSet();

      for (final id in activeBleedingIds) {
        final callsForThisId = zonedScheduleCalls.where(
          (args) => args['id'] == id,
        );
        expect(
          callsForThisId,
          hasLength(1),
          reason:
              'reminder id $id must be scheduled exactly once this '
              'refresh — never twice (which is what the removed OS '
              'recurring-fallback layer would have caused for every '
              'day within the rolling window on iOS specifically, per '
              'the verified plugin source cited in '
              'ActiveBleedingReminderScheduler.defaultRollingWindowDays\'s '
              'own doc comment)',
        );
      }

      // Day-seven/day-eight transition, and well beyond — at least 15
      // consecutive days, all present, all from the SAME mechanism.
      for (var day = 0; day < 15; day++) {
        final id = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: today.add(Duration(days: day)),
        );
        expect(
          zonedScheduleCalls.any((args) => args['id'] == id),
          isTrue,
          reason:
              'day $day (spanning the old 7-day boundary) must be '
              'scheduled by this single refresh',
        );
      }
    });

    test('no active-bleeding reminder is ever registered as an OS-native '
        'recurring schedule — every one is a plain, exact, one-off '
        'instance for its own specific date', () async {
      final today = BleedingEpisodeRepositoryImpl.localToday(
        DateTime.now().timeZoneOffset.inMinutes,
      );
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: null,
      );

      final activeBleedingIds = List.generate(
        ActiveBleedingReminderScheduler.defaultRollingWindowDays,
        (offset) => ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: today.add(Duration(days: offset)),
        ),
      ).toSet();

      final activeBleedingCalls = zonedScheduleCalls.where(
        (args) => activeBleedingIds.contains(args['id']),
      );
      expect(activeBleedingCalls, isNotEmpty);
      for (final call in activeBleedingCalls) {
        expect(
          call['matchDateTimeComponents'],
          isNull,
          reason:
              'a recurring (matchDateTimeComponents-based) schedule '
              'would, on iOS, fire at the next matching clock time '
              'regardless of which date was requested — exactly the '
              'platform inconsistency this policy avoids by never '
              'using one for this reminder type',
        );
      }
    });
  });
}
