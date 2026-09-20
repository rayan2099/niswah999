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

BleedingEpisode _openEpisode({
  String id = 'episode-1',
  String userId = 'user-1',
  DateTime? startDate,
}) => BleedingEpisode(
  id: id,
  userId: userId,
  lifecycleStatus: LifecycleStatus.open,
  continuationCertainty: ContinuationCertainty.confirmed,
  startDate: startDate ?? DateTime(2026, 9, 10),
  startPrecision: ObservationPrecision.dateOnly,
  startSource: ObservationSource.userObserved,
);

BleedingEpisode _endedEpisode({
  String id = 'episode-1',
  String userId = 'user-1',
  required DateTime startDate,
  required DateTime endDate,
}) => BleedingEpisode(
  id: id,
  userId: userId,
  lifecycleStatus: LifecycleStatus.ended,
  startDate: startDate,
  startPrecision: ObservationPrecision.dateOnly,
  startSource: ObservationSource.userObserved,
  endDate: endDate,
  endPrecision: ObservationPrecision.dateOnly,
  endSource: ObservationSource.userObserved,
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
    return LoadSuccess(_openEpisode(userId: userId));
  }

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async => LoadSuccess([_openEpisode(userId: userId)]);

  @override
  Future<LoadResult<List<BleedingObservation>>> getObservationsForEpisode(
    String episodeId,
  ) async => const LoadSuccess([]);
}

/// Simulates an episode that was open on the FIRST refresh and has
/// since ended — verified, not merely suspected — on the SECOND,
/// exactly like Finding 2's "ended on another device, discovered on
/// this device's next successful refresh" scenario. [today] must match
/// whatever the test itself uses to compute expected ids.
class _FakeRemotelyEndedEpisodeRepository
    extends BleedingEpisodeRepositoryImpl {
  _FakeRemotelyEndedEpisodeRepository({required this.today})
    : super(client: null);

  final DateTime today;
  bool episodeHasEnded = false;

  @override
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String userId) async {
    if (episodeHasEnded) return const LoadSuccess(null);
    return LoadSuccess(_openEpisode(userId: userId, startDate: today));
  }

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async => LoadSuccess([
    if (episodeHasEnded)
      _endedEpisode(userId: userId, startDate: today, endDate: today)
    else
      _openEpisode(userId: userId, startDate: today),
  ]);

  @override
  Future<LoadResult<List<BleedingObservation>>> getObservationsForEpisode(
    String episodeId,
  ) async => const LoadSuccess([]);
}

/// A genuine read failure — must never be treated as "verified: no open
/// episode" (Closure Blocker 1), so nothing should ever be cancelled
/// because of this repository's own responses.
class _FakeUnavailableRepository extends BleedingEpisodeRepositoryImpl {
  _FakeUnavailableRepository() : super(client: null);

  @override
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String userId) async =>
      const LoadUnavailable(LoadErrorCategory.network);

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async => const LoadUnavailable(LoadErrorCategory.network);
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
  var cancelAllCallCount = 0;
  final rejectCancelIds = <int>{};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    zonedScheduleCalls.clear();
    cancelledIds.clear();
    cancelAllCallCount = 0;
    rejectCancelIds.clear();
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
              final id = call.arguments['id'] as int;
              if (rejectCancelIds.contains(id)) {
                throw PlatformException(
                  code: 'FAIL',
                  message: 'simulated cancellation failure',
                );
              }
              cancelledIds.add(id);
              return null;
            case 'cancelAll':
              cancelAllCallCount++;
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

  group('New critical finding — notification cancellation closure', () {
    DateTime today() => BleedingEpisodeRepositoryImpl.localToday(
      DateTime.now().timeZoneOffset.inMinutes,
    );

    Set<int> windowIds({
      required String userId,
      required String episodeId,
      required DateTime start,
    }) => List.generate(
      ActiveBleedingReminderScheduler.defaultRollingWindowDays,
      (offset) => ActiveBleedingReminderScheduler.reminderId(
        userId: userId,
        episodeId: episodeId,
        localDay: start.add(Duration(days: offset)),
      ),
    ).toSet();

    Future<void> setActiveBleedingEnabled(bool enabled) async {
      final preferenceRepository = NotificationRepositoryImpl();
      final current = await preferenceRepository.loadPreferences();
      current[NotificationType.activeBleeding] =
          current[NotificationType.activeBleeding]!.copyWith(enabled: enabled);
      await preferenceRepository.savePreferences(current);
    }

    test('1. schedule 30 reminders, then disable — zero outstanding '
        'active-bleeding reminders (every id genuinely cancelled)', () async {
      final day = today();
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );
      final ids = windowIds(
        userId: 'user-1',
        episodeId: 'episode-1',
        start: day,
      );
      expect(
        zonedScheduleCalls.where((c) => ids.contains(c['id'])),
        hasLength(30),
      );

      await setActiveBleedingEnabled(false);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      for (final id in ids) {
        expect(
          cancelledIds,
          contains(id),
          reason:
              'reminder id $id must be cancelled once the '
              'preference is disabled, not merely left unscheduled '
              'going forward',
        );
      }
    });

    test('2. disable then re-enable — one valid (freshly scheduled) '
        'reminder per eligible day, not a permanently cancelled one', () async {
      final day = today();
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      await setActiveBleedingEnabled(false);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      await setActiveBleedingEnabled(true);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      final ids = windowIds(
        userId: 'user-1',
        episodeId: 'episode-1',
        start: day,
      );
      for (final id in ids) {
        final callsForId = zonedScheduleCalls.where((c) => c['id'] == id);
        expect(
          callsForId.length,
          greaterThanOrEqualTo(2),
          reason:
              'id $id must have been scheduled again after re-enabling '
              '— once initially, and again once re-enabled',
        );
      }
    });

    test('3. changing the preferred reminder time reschedules outstanding '
        'reminders to the new time', () async {
      final day = today();
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      final todaysId = ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: day,
      );
      final firstCall = zonedScheduleCalls.lastWhere(
        (c) => c['id'] == todaysId,
      );
      // Not asserted against a hardcoded "18:00" wall-clock string: this
      // test's own environment may not have a real IANA zone mocked
      // (unlike notification_timezone_test.dart, which covers that
      // separately), so `tz.local` can fall back to UTC while the
      // system's own real local zone differs — reinterpreting the same
      // wall-clock fields under a different zone shifts the hour
      // component. What must hold regardless of that offset is the
      // *delta* between the default (18:00) and the newly-chosen
      // (20:30) preferred time — exactly 2 hours, 30 minutes later.
      final firstMinute = int.parse(
        (firstCall['scheduledDateTime'] as String).substring(14, 16),
      );
      final firstHour = int.parse(
        (firstCall['scheduledDateTime'] as String).substring(11, 13),
      );

      final preferenceRepository = NotificationRepositoryImpl();
      final current = await preferenceRepository.loadPreferences();
      current[NotificationType.activeBleeding] =
          current[NotificationType.activeBleeding]!.copyWith(
            enabled: true,
            preferredHour: 20,
            preferredMinute: 30,
          );
      await preferenceRepository.savePreferences(current);

      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      final secondCall = zonedScheduleCalls.lastWhere(
        (c) => c['id'] == todaysId,
      );
      final secondMinute = int.parse(
        (secondCall['scheduledDateTime'] as String).substring(14, 16),
      );
      final secondHour = int.parse(
        (secondCall['scheduledDateTime'] as String).substring(11, 13),
      );

      expect(
        (secondHour - firstHour) % 24,
        2,
        reason:
            'the preferred hour moved from 18:00 to 20:00 — a real, '
            '2-hour change, regardless of this test environment\'s own '
            'timezone-fallback offset',
      );
      expect(firstMinute, 0);
      expect(secondMinute, 30);
    });

    test('4. an episode verified to have ended remotely is cancelled on '
        'this device\'s next successful refresh', () async {
      final day = today();
      final repository = _FakeRemotelyEndedEpisodeRepository(today: day);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );
      final ids = windowIds(
        userId: 'user-1',
        episodeId: 'episode-1',
        start: day,
      );
      expect(
        zonedScheduleCalls.where((c) => ids.contains(c['id'])),
        hasLength(30),
      );

      repository.episodeHasEnded = true;
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      for (final id in ids) {
        expect(
          cancelledIds,
          contains(id),
          reason:
              'once this device verifies (not merely suspects) the '
              'episode has ended, every id from that episode\'s window '
              'must be cancelled — it was ended on a different device, '
              'so this device\'s own end-episode call sites never ran',
        );
      }
    });

    test(
      '5. a genuine read failure never triggers a false cancellation',
      () async {
        await NotificationRefreshCoordinator.refresh(
          userId: 'user-1',
          bleedingRepository: _FakeUnavailableRepository(),
          preferenceRepository: null,
        );

        // The unrelated cycle/pregnancy/nifas planners legitimately
        // cancel their own small, fixed ids on every refresh when they
        // have nothing to schedule (pre-existing, correct behavior,
        // entirely independent of this fake repository) — this test is
        // specifically about the ACTIVE-BLEEDING sweep never firing a
        // false cancellation from a read failure, so only its own
        // (large, hashed) ids are asserted against here.
        const fixedNonActiveBleedingIds = {
          NotificationScheduler.cycleNotificationId,
          NotificationScheduler.pregnancyNotificationId,
          NotificationScheduler.nifasNotificationId,
          NotificationRefreshCoordinator.wellbeingReminderId,
        };
        expect(
          cancelledIds.where((id) => !fixedNonActiveBleedingIds.contains(id)),
          isEmpty,
          reason:
              '"could not verify" must never be treated as "verified: '
              'nothing to schedule" — the honest response is to leave '
              'whatever is already scheduled untouched; no active-'
              'bleeding-specific id may ever appear here',
        );
      },
    );

    test('6. account switch — cancelAll reaches the platform, and the new '
        'account\'s own reminders schedule independently afterward', () async {
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: null,
      );

      await NotificationService.instance.cancelAll();
      expect(
        cancelAllCallCount,
        1,
        reason:
            'this is the real mechanism AuthController wires at '
            'sign-out — verified here at the platform-channel level',
      );

      final day = today();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-2',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: null,
      );
      final user2Ids = windowIds(
        userId: 'user-2',
        episodeId: 'episode-1',
        start: day,
      );
      for (final id in user2Ids) {
        expect(
          zonedScheduleCalls.any((c) => c['id'] == id),
          isTrue,
          reason:
              'the new account\'s own reminders must schedule '
              'independently of whatever cancelAll just cleared',
        );
      }
    });

    test('7. a rejected platform cancellation is never recorded as a false '
        '"cancelled" audit event, and recovery remains possible once the '
        'platform accepts the call again', () async {
      final day = today();
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      final todaysId = ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: day,
      );
      rejectCancelIds.add(todaysId);

      await setActiveBleedingEnabled(false);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      expect(cancelledIds, isNot(contains(todaysId)));
      final eventsForId = await NotificationEventLogStore.loadForReminder(
        todaysId.toString(),
      );
      expect(
        eventsForId.any((e) => e.state == NotificationEventState.cancelled),
        isFalse,
        reason:
            'a platform rejection must never be recorded as a '
            'successful cancellation — the notification may still be '
            'live',
      );

      // Recovery: the platform now accepts the call.
      rejectCancelIds.remove(todaysId);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );
      expect(cancelledIds, contains(todaysId));
    });

    test('8. other notification types are never touched by the '
        'active-bleeding cancellation sweep', () async {
      final preferenceRepository = NotificationRepositoryImpl();
      final current = await preferenceRepository.loadPreferences();
      current[NotificationType.activeBleeding] =
          current[NotificationType.activeBleeding]!.copyWith(enabled: true);
      current[NotificationType.wellbeing] = current[NotificationType.wellbeing]!
          .copyWith(enabled: true);
      await preferenceRepository.savePreferences(current);

      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: preferenceRepository,
      );

      await preferenceRepository.savePreferences({
        ...await preferenceRepository.loadPreferences(),
        NotificationType.activeBleeding:
            current[NotificationType.activeBleeding]!.copyWith(enabled: false),
      });
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: preferenceRepository,
      );

      // Cycle/pregnancy/nifas are deliberately not asserted against here:
      // with no real cycle/pregnancy data supplied to this test, those
      // planners legitimately have nothing to schedule and correctly
      // cancel their own fixed ids on every refresh regardless — that
      // is pre-existing, correct behavior entirely unrelated to this
      // fix. Wellbeing, kept enabled throughout with nothing that ever
      // gates it, is the clean, isolated signal: it must be scheduled
      // in both refreshes and never once cancelled as a side effect of
      // disabling the unrelated active-bleeding preference.
      final wellbeingScheduleCount = zonedScheduleCalls
          .where(
            (c) =>
                c['id'] == NotificationRefreshCoordinator.wellbeingReminderId,
          )
          .length;
      expect(wellbeingScheduleCount, 2);
      expect(
        cancelledIds,
        isNot(contains(NotificationRefreshCoordinator.wellbeingReminderId)),
        reason:
            'disabling active-bleeding must never cancel an unrelated, '
            'still-enabled reminder type',
      );
    });
  });
}
