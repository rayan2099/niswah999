// Pregnancy/notifications hardening (2026-10-21) — regression tests for
// three review-bot findings on PR #31:
// 1. a birth logged on this device cancels the pregnancy-week reminder even
//    when the server row is stale (postpartum write failed) or unreadable;
// 2. a failed profile read never plans a cycle reminder as if not pregnant;
// 3. the feed notifies listeners when a scheduled entry's fire time passes.
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/notification_log_controller.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/notifications/domain/entities/notification_preference.dart';
import 'package:niswah/features/notifications/domain/services/notification_refresh_coordinator.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';
import 'package:niswah/features/pregnancy_profile/data/pregnancy_state_sync.dart';
import 'package:niswah/features/pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pluginChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

/// A server that cannot be written; reads return [row] or throw.
class _OfflineRepo extends PregnancyProfileRepository {
  _OfflineRepo({this.row, this.readFails = false})
    : super(supabaseClient: null);

  PregnancyProfile? row;
  bool readFails;

  @override
  Future<PregnancyProfile?> getForUser(String userId) async {
    if (readFails) throw StateError('offline');
    return row;
  }

  @override
  Future<PregnancyProfile> upsert(PregnancyProfile profile) async =>
      throw StateError('offline');

  @override
  Future<void> markPostpartumStarted(
    String userId, {
    DateTime? startDate,
  }) async => throw StateError('offline');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('refresh with a failed or stale pregnancy profile', () {
    // Anchored to the real date: the notification plugin rejects a fire
    // time that is in the past by the wall clock, whatever AppClock says.
    final today = calendarDay(DateTime.now());
    final now = DateTime(today.year, today.month, today.day, 9);
    final pending = <int>{};

    // Week 10 set 3 days ago: the week flips (and a milestone is due)
    // within the planner's probe window.
    final pregnantRow = PregnancyProfile(
      id: 'p',
      userId: 'user-1',
      trackingBasis: TrackingBasis.manualWeek,
      manualWeekValue: 10,
      manualWeekSetAt: addCalendarDays(today, -3),
    );

    // Two periods 28 days apart, the last 9 days ago: enough history to
    // plan a cycle reminder a couple of weeks ahead.
    final history = [
      CanonicalEpisodeTiming(
        startDate: addCalendarDays(today, -37),
        endDate: addCalendarDays(today, -32),
      ),
      CanonicalEpisodeTiming(
        startDate: addCalendarDays(today, -9),
        endDate: addCalendarDays(today, -4),
      ),
    ];

    Future<void> refresh(PregnancyProfileRepository repo) =>
        NotificationRefreshCoordinator.refresh(
          userId: 'user-1',
          pregnancyRepository: repo,
          bleedingRepository: BleedingEpisodeRepositoryImpl(client: null),
          cycleHistoryLoader: (_) async => history,
        );

    setUp(() async {
      AppClock.now = () => now;
      SharedPreferences.setMockInitialValues({});
      await PregnancyStatusController.instance.load();
      await NotificationLogController.instance.load();
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
                pending.add(args['id'] as int);
                return null;
              case 'cancel':
                pending.remove(call.arguments['id'] as int);
                return null;
              case 'cancelAll':
                pending.clear();
                return null;
              case 'pendingNotificationRequests':
                return [
                  for (final id in pending) {'id': id},
                ];
              default:
                return null;
            }
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (call) async => 'UTC');
    await NotificationService.instance.initialize();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pluginChannel, null);
      PregnancyStatusController.instance.resetInMemory();
      NotificationLogController.instance.resetInMemory();
      AppClock.reset();
    });

    Future<void> logBirthWhileOffline(_OfflineRepo repo) async {
      final synced = await PregnancyStateSync(
        repository: repo,
        currentUserId: () => 'user-1',
        refreshNotifications: (_) => refresh(repo),
      ).startNifas();
      expect(synced, isFalse);
      expect(PregnancyStatusController.instance.isNifasActive, isTrue);
    }

    test('birth logged, postpartum write failed, profile read fails: '
        'the pregnancy milestone is cancelled', () async {
      final repo = _OfflineRepo(row: pregnantRow);
      await refresh(repo);
      expect(pending, contains(NotificationScheduler.pregnancyNotificationId));

      repo.readFails = true;
      await logBirthWhileOffline(repo);

      expect(
        pending,
        isNot(contains(NotificationScheduler.pregnancyNotificationId)),
      );
    });

    test('birth logged, postpartum write failed, read returns the stale '
        'pregnant row: no pregnancy milestone is scheduled', () async {
      final repo = _OfflineRepo(row: pregnantRow);
      await refresh(repo);
      expect(pending, contains(NotificationScheduler.pregnancyNotificationId));

      await logBirthWhileOffline(repo);

      expect(
        pending,
        isNot(contains(NotificationScheduler.pregnancyNotificationId)),
      );
    });

    test('failed profile read, nothing pregnant on this device: no cycle '
        'reminder is planned from history', () async {
      await refresh(_OfflineRepo(readFails: true));

      expect(
        pending,
        isNot(contains(NotificationScheduler.cycleNotificationId)),
      );
    });

    test('failed profile read leaves an already planned cycle reminder in '
        'place', () async {
      final repo = _OfflineRepo();
      await refresh(repo);
      expect(pending, contains(NotificationScheduler.cycleNotificationId));

      repo.readFails = true;
      await refresh(repo);

      expect(pending, contains(NotificationScheduler.cycleNotificationId));
    });
  });

  group('feed reveals scheduled entries at their fire time', () {
    final start = DateTime(2026, 3, 1, 8);
    var elapsed = Duration.zero;

    NotificationLogEntry entry(String id, DateTime fireAt) =>
        NotificationLogEntry(
          id: id,
          type: NotificationType.pregnancy,
          titleAr: 't',
          bodyAr: 'b',
          titleEn: 't',
          bodyEn: 'b',
          createdAt: start,
          fireAt: fireAt,
        );

    // Moves AppClock and the test's fake timers forward together.
    Future<void> advance(WidgetTester tester, Duration by) async {
      elapsed += by;
      await tester.pump(by);
    }

    setUp(() async {
      elapsed = Duration.zero;
      AppClock.now = () => start.add(elapsed);
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      NotificationLogController.instance.resetInMemory();
      AppClock.reset();
    });

    testWidgets('listeners are notified when the nearest entry fires', (
      tester,
    ) async {
      final log = NotificationLogController.instance;
      await log.load();
      await log.upsertScheduled(
        '102',
        entry('102_a', start.add(const Duration(hours: 2))),
      );
      await log.upsertScheduled(
        '103',
        entry('103_a', start.add(const Duration(hours: 5))),
      );
      var notified = 0;
      void listener() => notified++;
      log.addListener(listener);
      addTearDown(() => log.removeListener(listener));

      await advance(tester, const Duration(hours: 1, minutes: 59));
      expect(notified, 0);
      expect(log.entries, isEmpty);

      await advance(tester, const Duration(minutes: 1));
      expect(notified, 1);
      expect(log.entries.map((e) => e.id), ['102_a']);

      await advance(tester, const Duration(hours: 3));
      expect(notified, 2);
      expect(log.entries.map((e) => e.id), ['103_a', '102_a']);
    });

    testWidgets('a cancelled pending entry no longer wakes listeners', (
      tester,
    ) async {
      final log = NotificationLogController.instance;
      await log.load();
      await log.upsertScheduled(
        '102',
        entry('102_a', start.add(const Duration(hours: 2))),
      );
      await log.removePending('102');
      var notified = 0;
      void listener() => notified++;
      log.addListener(listener);
      addTearDown(() => log.removeListener(listener));

      await advance(tester, const Duration(hours: 3));
      expect(notified, 0);
    });
  });
}
