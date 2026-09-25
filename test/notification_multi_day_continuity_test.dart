import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/app_clock.dart';
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

  /// New critical finding (local notification reconciliation closure) —
  /// the whole point of reconciling against the OS's own actual pending
  /// set is that a disable/verified-no-open-episode cancellation must
  /// never need a second Supabase read to decide what to cancel. This
  /// counter is the direct proof: it must stay at 0 across every
  /// cancellation-flow test below.
  int getEpisodesForUserCallCount = 0;

  @override
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String userId) async {
    return LoadSuccess(_openEpisode(userId: userId));
  }

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async {
    getEpisodesForUserCallCount++;
    return LoadSuccess([_openEpisode(userId: userId)]);
  }

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
  int getEpisodesForUserCallCount = 0;

  @override
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String userId) async {
    if (episodeHasEnded) return const LoadSuccess(null);
    return LoadSuccess(_openEpisode(userId: userId, startDate: today));
  }

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async {
    getEpisodesForUserCallCount++;
    return LoadSuccess([
      if (episodeHasEnded)
        _endedEpisode(userId: userId, startDate: today, endDate: today)
      else
        _openEpisode(userId: userId, startDate: today),
    ]);
  }

  @override
  Future<LoadResult<List<BleedingObservation>>> getObservationsForEpisode(
    String episodeId,
  ) async => const LoadSuccess([]);
}

/// A genuine read failure — must never be treated as "verified: no open
/// episode" (Closure Blocker 1), so nothing should ever be cancelled
/// because of this repository's own responses. Both reads are
/// deliberately unavailable, not only [getOpenEpisode], to prove the
/// disable flow's own independence from Supabase entirely — even a
/// fully-unreachable backend must not block a local opt-out.
class _FakeUnavailableRepository extends BleedingEpisodeRepositoryImpl {
  _FakeUnavailableRepository() : super(client: null);

  int getEpisodesForUserCallCount = 0;

  @override
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String userId) async =>
      const LoadUnavailable(LoadErrorCategory.network);

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async {
    getEpisodesForUserCallCount++;
    return const LoadUnavailable(LoadErrorCategory.network);
  }
}

/// New critical finding — multi-day notification continuity. Exercises
/// the real NotificationRefreshCoordinator (not just the pure scheduler
/// function) end to end: a single refresh call, simulating the one and
/// only time the app is ever opened, must leave genuinely-scheduled OS
/// notifications and structural audit events behind for every day in
/// the rolling window — proving continuity does not depend on being
/// reopened once per day.
/// One pinned instant fed to `AppClock.now` — the SINGLE clock both the
/// production coordinator (`NotificationRefreshCoordinator`) and
/// `BleedingEpisodeRepositoryImpl.localToday` derive the logical "today"
/// from. Dates are in 2030 on purpose: `flutter_local_notifications`
/// validates every `zonedSchedule` against the REAL wall clock, so every
/// pinned instant must stay in the real future.
///
/// Every scenario is a LOCAL `DateTime(...)`, exactly what production's
/// `AppClock.now` (default `DateTime.now`) always yields — a UTC-kind
/// value would be an input production never produces. The machine's own
/// zone therefore supplies the UTC offset, so running this file under
/// different `TZ=` values (see scripts/run_notification_clock_matrix.sh)
/// exercises positive, negative, half-hour and +14 offsets, and the
/// UTC-date vs local-date disagreement, against the same wall times.
class _ClockScenario {
  const _ClockScenario(this.name, this.clock);
  final String name;
  final DateTime Function() clock;
}

final _clockScenarios = <_ClockScenario>[
  _ClockScenario('09:00', () => DateTime(2030, 1, 15, 9)),
  _ClockScenario(
    '17:59:59 (last second before lead time)',
    () => DateTime(2030, 1, 15, 17, 59, 59),
  ),
  _ClockScenario(
    '18:00:00 (exactly the lead time)',
    () => DateTime(2030, 1, 15, 18),
  ),
  _ClockScenario('20:29:59', () => DateTime(2030, 1, 15, 20, 29, 59)),
  _ClockScenario(
    '20:59:59 (last second of default catch-up)',
    () => DateTime(2030, 1, 15, 20, 59, 59),
  ),
  _ClockScenario(
    '21:00:00 (default catch-up closes)',
    () => DateTime(2030, 1, 15, 21),
  ),
  _ClockScenario(
    '21:07 (the time of day CI first failed)',
    () => DateTime(2030, 1, 15, 21, 7),
  ),
  _ClockScenario('23:29:59', () => DateTime(2030, 1, 15, 23, 29, 59)),
  _ClockScenario(
    '23:30:00 (20:30-lead catch-up closes)',
    () => DateTime(2030, 1, 15, 23, 30),
  ),
  _ClockScenario(
    '23:59:59 (last second of the day)',
    () => DateTime(2030, 1, 15, 23, 59, 59),
  ),
  _ClockScenario(
    '00:00:00 (first second of next day)',
    () => DateTime(2030, 1, 16),
  ),
  _ClockScenario('00:00:01', () => DateTime(2030, 1, 16, 0, 0, 1)),
  _ClockScenario(
    '2030-12-31 23:59:59 (year boundary)',
    () => DateTime(2030, 12, 31, 23, 59, 59),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in _clockScenarios) {
    group('under pinned clock: ${scenario.name}', () => _suite(scenario));
  }
}

void _suite(_ClockScenario scenario) {
  // Documented production rule (notification_scheduler.dart `_planForDay`):
  // a default 18:00 reminder whose time has passed gets ONE fixed
  // catch-up at lead + 3h (21:00); at/after that there is no same-day
  // reminder — the next day's is the genuine next touchpoint. So today's
  // slot exists iff the pinned local clock time is before 21:00:00. This
  // is exact, not a loosened count: 30 window days, or 29 when today's
  // slot has legitimately closed.
  bool todaysSlotOpen({int leadSeconds = 18 * 3600}) {
    final now = scenario.clock();
    final secondsIntoDay = now.hour * 3600 + now.minute * 60 + now.second;
    return secondsIntoDay < leadSeconds + 3 * 3600;
  }

  int firstDayOffset() => todaysSlotOpen() ? 0 : 1;
  int expectedWindowCount() =>
      ActiveBleedingReminderScheduler.defaultRollingWindowDays -
      firstDayOffset();

  final zonedScheduleCalls = <Map<dynamic, dynamic>>[];
  final cancelledIds = <int>[];
  var cancelAllCallCount = 0;
  final rejectCancelIds = <int>{};

  // New critical finding (local notification reconciliation closure) —
  // a stateful simulation of the OS's own actual pending-request set,
  // the exact thing `pendingNotificationRequests()` is meant to reflect:
  // populated on `zonedSchedule`, removed on a genuinely-accepted
  // `cancel`/`cancelAll`. This is what makes it possible to test
  // `NotificationService.pendingActiveBleedingReminders()` — and, in
  // turn, the coordinator's own set-reconciliation logic — against a
  // real mocked platform channel rather than merely asserting on the
  // call log.
  final pendingRequests = <int, Map<String, dynamic>>{};

  setUp(() async {
    AppClock.now = scenario.clock;
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    zonedScheduleCalls.clear();
    cancelledIds.clear();
    cancelAllCallCount = 0;
    rejectCancelIds.clear();
    pendingRequests.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'createNotificationChannel':
            case 'getNotificationAppLaunchDetails':
              return null;
            case 'zonedSchedule':
              final args = call.arguments as Map<dynamic, dynamic>;
              zonedScheduleCalls.add(args);
              final id = args['id'] as int;
              pendingRequests[id] = {
                'id': id,
                'title': args['title'],
                'body': args['body'],
                'payload': args['payload'],
              };
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
              pendingRequests.remove(id);
              return null;
            case 'cancelAll':
              cancelAllCallCount++;
              pendingRequests.clear();
              return null;
            case 'pendingNotificationRequests':
              return pendingRequests.values.toList();
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
    AppClock.reset();
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
      AppClock.now().timeZoneOffset.inMinutes,
    );
    await NotificationRefreshCoordinator.refresh(
      userId: 'user-1',
      bleedingRepository: _FakeOpenEpisodeRepository(),
      preferenceRepository: null,
    );

    final expectedIds = List.generate(
      expectedWindowCount(),
      (offset) => ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: today.add(Duration(days: offset + firstDayOffset())),
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
        AppClock.now().timeZoneOffset.inMinutes,
      );
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: null,
      );

      final activeBleedingIds = List.generate(
        expectedWindowCount(),
        (offset) => ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: today.add(Duration(days: offset + firstDayOffset())),
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
      for (var day = firstDayOffset(); day < 15; day++) {
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
        AppClock.now().timeZoneOffset.inMinutes,
      );
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: null,
      );

      final activeBleedingIds = List.generate(
        expectedWindowCount(),
        (offset) => ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: today.add(Duration(days: offset + firstDayOffset())),
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

  group('New critical finding — local notification reconciliation closure', () {
    DateTime today() => BleedingEpisodeRepositoryImpl.localToday(
      AppClock.now().timeZoneOffset.inMinutes,
    );

    Set<int> windowIds({
      required String userId,
      required String episodeId,
      required DateTime start,
    }) => List.generate(
      expectedWindowCount(),
      (offset) => ActiveBleedingReminderScheduler.reminderId(
        userId: userId,
        episodeId: episodeId,
        localDay: start.add(Duration(days: offset + firstDayOffset())),
      ),
    ).toSet();

    Future<void> setActiveBleedingEnabled(bool enabled) async {
      final preferenceRepository = NotificationRepositoryImpl();
      final current = await preferenceRepository.loadPreferences();
      current[NotificationType.activeBleeding] =
          current[NotificationType.activeBleeding]!.copyWith(enabled: enabled);
      await preferenceRepository.savePreferences(current);
    }

    // Cycle/pregnancy/wellbeing all default to enabled (unlike
    // active-bleeding, which defaults off) — `pendingRequests` as a
    // whole legitimately contains their own ids too (wellbeing's fixed
    // id in particular, scheduled unconditionally whenever enabled, with
    // no data dependency). Every assertion below that means "the 30
    // active-bleeding ids" must filter down to exactly those — by
    // payload `type`/`userId`, mirroring the real production
    // reconciliation filter — rather than asserting on the raw pending
    // map, which would otherwise be contaminated by those unrelated,
    // legitimately-still-scheduled types.
    Set<int> activeBleedingPendingIds({required String userId}) =>
        pendingRequests.entries
            .where((entry) {
              final payload = entry.value['payload'];
              if (payload is! String) return false;
              try {
                final decoded = jsonDecode(payload);
                return decoded is Map &&
                    decoded['type'] == 'activeBleedingCheckin' &&
                    decoded['userId'] == userId;
              } catch (_) {
                return false;
              }
            })
            .map((entry) => entry.key)
            .toSet();

    test('1. 30 scheduled, then Supabase unavailable, then disabled — zero '
        'owned active-bleeding pending requests remain (an explicit local '
        'opt-out never depends on a Supabase read to take effect)', () async {
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );
      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        hasLength(expectedWindowCount()),
      );

      await setActiveBleedingEnabled(false);
      final unavailableRepository = _FakeUnavailableRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: unavailableRepository,
        preferenceRepository: null,
      );

      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        isEmpty,
        reason:
            'every one of the 30 owned active-bleeding requests must be '
            'cancelled locally, purely from the OS\'s own pending set — '
            'both getOpenEpisode AND getEpisodesForUser on this repository '
            'are wired to LoadUnavailable, and the disable still succeeds',
      );
      expect(
        unavailableRepository.getEpisodesForUserCallCount,
        0,
        reason:
            'the disable flow must never call getEpisodesForUser (a '
            'Supabase read) to discover what to cancel',
      );
    });

    test('2. Supabase unavailable while enabled — no false inference of '
        'episode end (a read failure stays honestly unknown)', () async {
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );
      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        hasLength(expectedWindowCount()),
      );

      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeUnavailableRepository(),
        preferenceRepository: null,
      );

      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        hasLength(expectedWindowCount()),
        reason:
            '"could not verify" must never be treated as "verified: no '
            'open episode" — the honest response is to leave whatever is '
            'already scheduled untouched',
      );
    });

    test('3. a verified clean "no open episode" cancels local pending '
        'requests without any second getEpisodesForUser query', () async {
      final day = today();
      final repository = _FakeRemotelyEndedEpisodeRepository(today: day);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );
      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        hasLength(expectedWindowCount()),
      );
      expect(repository.getEpisodesForUserCallCount, 0);

      repository.episodeHasEnded = true;
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        isEmpty,
        reason:
            'once getOpenEpisode cleanly returns null (VERIFIED, not a '
            'read failure), every owned pending request must be '
            'cancelled — this covers an episode ended on a different '
            'device just as much as one ended here',
      );
      expect(
        repository.getEpisodesForUserCallCount,
        0,
        reason:
            'the verified-no-open-episode cancellation path must reconcile '
            'against the OS\'s own pending set, never a second '
            'getEpisodesForUser Supabase read',
      );
    });

    test('4. a device timezone shift backward across a calendar boundary '
        'removes the old far-edge notification no longer in the new '
        'desired window', () async {
      // Deliberately far in the future (2030), not merely "tomorrow" —
      // `flutter_local_notifications` itself validates every
      // `zonedSchedule` call's `scheduledDate` against the REAL wall
      // clock (`tz.TZDateTime.now(tz.local)`), not against this test's
      // own AppClock injection; a date anywhere near the real "now"
      // could otherwise land in the real past for one of the two
      // refreshes below and be rejected by the plugin itself.
      AppClock.now = () => DateTime(2030, 1, 15, 12, 0);
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );
      final oldFarEdgeId = ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: DateTime(2030, 2, 13),
      );
      expect(pendingRequests.containsKey(oldFarEdgeId), isTrue);

      // The device's own timezone changes backward — "today" itself
      // moves back one calendar day (the charter's own worked example:
      // Sep 21 -> Sep 20, reproduced here as Jan 15 -> Jan 14).
      // AppClock.now feeds
      // ActiveBleedingReminderScheduler.planRollingDailyCheckins's own
      // "today" directly; this is a faithful, honest exercise of the
      // reconciliation mechanism's reaction to a shifted desired window,
      // whatever its real-world cause — a genuine device timezone change
      // itself remains E4-only, not exercised here.
      AppClock.now = () => DateTime(2030, 1, 14, 12, 0);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      expect(
        pendingRequests.containsKey(oldFarEdgeId),
        isFalse,
        reason:
            'Feb 13 is no longer part of the new Jan 14 - Feb 12 desired '
            'window and must be cancelled',
      );
      final newNearEdgeId = ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: DateTime(2030, 1, 14),
      );
      expect(pendingRequests.containsKey(newNearEdgeId), isTrue);
    });

    test('5. a device timezone shift forward across a calendar boundary '
        'removes the old past notification and adds the new far-edge '
        'one', () async {
      AppClock.now = () => DateTime(2030, 1, 14, 12, 0);
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );
      final oldNearEdgeId = ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: DateTime(2030, 1, 14),
      );
      expect(pendingRequests.containsKey(oldNearEdgeId), isTrue);

      AppClock.now = () => DateTime(2030, 1, 15, 12, 0);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      expect(
        pendingRequests.containsKey(oldNearEdgeId),
        isFalse,
        reason: 'Jan 14 is now in the past relative to the new today',
      );
      final newFarEdgeId = ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: DateTime(2030, 2, 13),
      );
      expect(pendingRequests.containsKey(newFarEdgeId), isTrue);
    });

    test('6. changing the preferred reminder time reschedules the same '
        'logical days, reflects the new time, and leaves no stale '
        'duplicate requests', () async {
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
      expect(activeBleedingPendingIds(userId: 'user-1'), ids);

      // Tomorrow's slot, not today's: today's own slot legitimately
      // closes at lead time + 3h (the catch-up rule), so it is not
      // present under every pinned clock, while tomorrow's is always a
      // plain future day at exactly the preferred wall-clock time.
      final todaysId = ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: day.add(const Duration(days: 1)),
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
      int minuteOfDay(Map<dynamic, dynamic> call) {
        final stamp = call['scheduledDateTime'] as String;
        return int.parse(stamp.substring(11, 13)) * 60 +
            int.parse(stamp.substring(14, 16));
      }

      final firstMinuteOfDay = minuteOfDay(firstCall);

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
      final secondMinuteOfDay = minuteOfDay(secondCall);

      expect(
        (secondMinuteOfDay - firstMinuteOfDay) % (24 * 60),
        150,
        reason:
            'the preferred time moved from 18:00 to 20:30 — exactly 150 '
            'minutes later, regardless of this test environment\'s own '
            'timezone-fallback offset (whole-hour or half-hour: the '
            'absolute :00/:30 fields shift with the offset, the delta '
            'does not)',
      );
      // Every day that was pending before is still pending under its
      // same id (idempotently replaced, never duplicated alongside a
      // stale copy). The ONLY permitted difference is today's own slot:
      // moving the lead time from 18:00 to 20:30 also moves today's
      // catch-up cutoff from 21:00 to 23:30, so a today slot that had
      // already closed under the old time may legitimately reopen —
      // exactly when the pinned clock is before 23:30:00.
      final todayId = ActiveBleedingReminderScheduler.reminderId(
        userId: 'user-1',
        episodeId: 'episode-1',
        localDay: day,
      );
      final expectedAfterChange = {
        ...ids,
        if (todaysSlotOpen(leadSeconds: 20 * 3600 + 30 * 60)) todayId,
      };
      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        expectedAfterChange,
        reason:
            'the same logical days remain pending, plus today only if the '
            'new lead time\'s catch-up window is still open',
      );
    });

    test('7. a malformed pending-notification payload is ignored safely, '
        'never crashes the sweep', () async {
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      const malformedId = 777777;
      pendingRequests[malformedId] = {
        'id': malformedId,
        'title': 'x',
        'body': 'y',
        'payload': 'not-valid-json{{{',
      };

      await setActiveBleedingEnabled(false);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      expect(
        pendingRequests.containsKey(malformedId),
        isTrue,
        reason:
            'a malformed payload must never be treated as an owned '
            'active-bleeding request — it is excluded, not crashed on, '
            'and left untouched here (this disable call must still '
            'complete and cancel every one of user-1\'s real 30 ids)',
      );
      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        isEmpty,
        reason:
            'every one of user-1\'s real active-bleeding ids must '
            'still be cancelled despite the unrelated malformed entry',
      );
    });

    test('8. a pending active-bleeding request for another user is '
        'untouched while the current user\'s preference is disabled', () async {
      final repository = _FakeOpenEpisodeRepository();
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      const otherUserRequestId = 918273;
      pendingRequests[otherUserRequestId] = {
        'id': otherUserRequestId,
        'title': 'x',
        'body': 'y',
        'payload': jsonEncode({
          'type': 'activeBleedingCheckin',
          'userId': 'user-2',
          'episodeId': 'episode-other',
          'localDate': '2026-09-25',
        }),
      };

      await setActiveBleedingEnabled(false);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        isEmpty,
        reason:
            'every one of user-1\'s own real ids must still be '
            'cancelled',
      );
      expect(
        pendingRequests.containsKey(otherUserRequestId),
        isTrue,
        reason:
            'account isolation — only requests the payload structurally '
            'attributes to the current signed-in user may be cancelled; '
            'user-2\'s own request must survive user-1\'s own disable',
      );
    });

    test('9. other notification types are never touched by the '
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
        pendingRequests.containsKey(
          NotificationRefreshCoordinator.wellbeingReminderId,
        ),
        isTrue,
        reason:
            'disabling active-bleeding must never cancel an unrelated, '
            'still-enabled reminder type',
      );
    });

    test('10. one rejected cancellation never stops the rest from being '
        'attempted, and is never recorded as a false "cancelled" audit '
        'event; recovery remains possible once the platform accepts the '
        'call again', () async {
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
        activeBleedingPendingIds(userId: 'user-1'),
        hasLength(expectedWindowCount()),
      );

      final rejectedId = ids.first;
      rejectCancelIds.add(rejectedId);

      await setActiveBleedingEnabled(false);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );

      expect(
        pendingRequests.containsKey(rejectedId),
        isTrue,
        reason: 'the rejected id is still live — the platform refused it',
      );
      final eventsForRejected = await NotificationEventLogStore.loadForReminder(
        rejectedId.toString(),
      );
      expect(
        eventsForRejected.any(
          (e) => e.state == NotificationEventState.cancelled,
        ),
        isFalse,
        reason:
            'a platform rejection must never be recorded as a successful '
            'cancellation — the notification may still be live',
      );
      for (final id in ids.where((id) => id != rejectedId)) {
        expect(
          pendingRequests.containsKey(id),
          isFalse,
          reason:
              'every OTHER owned id must still have been attempted and '
              'cancelled — one rejection must never abort the rest of '
              'the sweep',
        );
      }

      // Recovery: the platform now accepts the call.
      rejectCancelIds.remove(rejectedId);
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: repository,
        preferenceRepository: null,
      );
      expect(pendingRequests.containsKey(rejectedId), isFalse);
    });

    test('11. disable then re-enable — one freshly-scheduled reminder per '
        'eligible day, not a permanently cancelled one', () async {
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
      expect(activeBleedingPendingIds(userId: 'user-1'), isEmpty);

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
      expect(activeBleedingPendingIds(userId: 'user-1'), ids);
    });

    test('12. account switch — cancelAll reaches the platform, and the new '
        'account\'s own reminders schedule independently afterward', () async {
      await NotificationRefreshCoordinator.refresh(
        userId: 'user-1',
        bleedingRepository: _FakeOpenEpisodeRepository(),
        preferenceRepository: null,
      );
      expect(
        activeBleedingPendingIds(userId: 'user-1'),
        hasLength(expectedWindowCount()),
      );

      await NotificationService.instance.cancelAll();
      expect(
        cancelAllCallCount,
        1,
        reason:
            'this is the real mechanism AuthController wires at '
            'sign-out — verified here at the platform-channel level',
      );
      expect(pendingRequests, isEmpty);

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
      expect(activeBleedingPendingIds(userId: 'user-2'), user2Ids);
    });
  });
}
