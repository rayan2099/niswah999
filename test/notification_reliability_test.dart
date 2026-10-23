import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/core/preferences/notification_log_controller.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/notifications/data/local/notification_event_log_store.dart';
import 'package:niswah/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:niswah/features/notifications/domain/entities/notification_event.dart';
import 'package:niswah/features/notifications/domain/entities/notification_preference.dart';
import 'package:niswah/features/notifications/domain/services/notification_refresh_coordinator.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';
import 'package:niswah/features/notifications/domain/services/prayer_reminder_scheduler.dart';

import 'support/notification_platform_harness.dart';

class EpisodeRepo extends BleedingEpisodeRepositoryImpl {
  EpisodeRepo() : super(client: null);
  Completer<LoadResult<BleedingEpisode?>>? held;
  final started = Completer<void>();
  int reads = 0;
  @override
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String userId) async {
    reads++;
    if (!started.isCompleted) started.complete();
    if (held != null) return held!.future;
    return LoadSuccess(episode());
  }

  @override
  Future<LoadResult<List<BleedingObservation>>> getObservationsForEpisode(
    String id,
  ) async => const LoadSuccess([]);
  static BleedingEpisode episode() => BleedingEpisode(
    id: 'new',
    userId: 'u',
    lifecycleStatus: LifecycleStatus.open,
    continuationCertainty: ContinuationCertainty.confirmed,
    startDate: DateTime(2030, 1, 14),
    startPrecision: ObservationPrecision.dateOnly,
    startSource: ObservationSource.userObserved,
  );
}

Future<void> preferences({
  bool active = false,
  bool prayer = false,
  bool wellbeing = false,
  int hour = 18,
  int minute = 0,
}) async {
  final repo = NotificationRepositoryImpl();
  final prefs = await repo.loadPreferences();
  await repo.savePreferences({
    for (final e in prefs.entries)
      e.key: e.value.copyWith(
        enabled: switch (e.key) {
          NotificationType.activeBleeding => active,
          NotificationType.prayer => prayer,
          NotificationType.wellbeing => wellbeing,
          _ => false,
        },
        preferredHour: hour,
        preferredMinute: minute,
      ),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NotificationPlatformHarness os;
  final service = NotificationService.instance;
  setUp(() async {
    os = NotificationPlatformHarness();
    await os.install();
  });
  tearDown(() async {
    SecureLocalStore.debugUserIdOverride = null;
    await os.uninstall();
  });

  Future<NotificationSchedulingOutcome> schedule(int id) => service.scheduleAt(
    id: id,
    title: 'Niswah',
    body: 'Reminder',
    when: AppClock.now().add(const Duration(hours: 1)),
  );

  test('native delivery contracts include Android schedule/boot receivers and iOS delegation', () {
    final android = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(android, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    for (final receiver in [
      'ScheduledNotificationReceiver',
      'ScheduledNotificationBootReceiver',
    ]) {
      expect(
        android,
        contains('com.dexterous.flutterlocalnotifications.$receiver'),
      );
    }
    expect(android, contains('android.intent.action.BOOT_COMPLETED'));
    expect(android, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(ios, contains('UNUserNotificationCenter.current().delegate'));
  });

  test('sign-out during scheduling cannot leak an old request or erase a new account request', () async {
    final entered = Completer<void>();
    final resume = Completer<void>();
    os.beforeSchedule = (args) async {
      if (args['id'] == 1) {
        entered.complete();
        await resume.future;
      }
    };
    final old = schedule(1);
    await entered.future;
    final cleanup = service.cancelAll();
    final current = schedule(2);
    resume.complete();
    expect(await old, NotificationSchedulingOutcome.superseded);
    await cleanup;
    expect(await current, NotificationSchedulingOutcome.accepted);
    expect(os.pending.keys, [2]);
  });

  test('failed account cleanup blocks new scheduling and retries on the next attempt', () async {
    os.pending[3] = {'id': 3};
    os.failCleanup = true;
    await service.cancelAll();
    expect(await schedule(4), NotificationSchedulingOutcome.failed);
    expect(os.pending.keys, [3]);
    os.failCleanup = false;
    expect(await schedule(4), NotificationSchedulingOutcome.accepted);
    expect(os.pending.keys, [4]);
  });

  test('superseded refresh work cannot cancel current requests', () async {
    expect(await schedule(5), NotificationSchedulingOutcome.accepted);
    final cancelled = await service.withWorkGuard(
      () => false,
      () => service.cancel(5),
    );
    expect(cancelled, isFalse);
    expect(os.pending, contains(5));
  });

  test('unknown timezone is never accepted as a UTC daily reminder', () async {
    os.timezone = null;
    await service.refreshLocalTimezone(forceRefresh: true);
    expect(
      await service.scheduleDaily(
        id: 6,
        title: 'Niswah',
        body: 'Reminder',
        hour: 9,
        minute: 0,
      ),
      NotificationSchedulingOutcome.timezoneUnavailable,
    );
    expect(os.scheduled, isEmpty);
    os.timezone = 'Asia/Riyadh';
    await service.refreshLocalTimezone(forceRefresh: true);
    expect(
      await service.scheduleDaily(
        id: 6,
        title: 'Niswah',
        body: 'Reminder',
        hour: 9,
        minute: 0,
      ),
      NotificationSchedulingOutcome.accepted,
    );
    expect(os.scheduled.single['timeZoneName'], 'Asia/Riyadh');
  });

  test('invalid clock inputs and past requests never reach the OS', () async {
    expect(
      await service.scheduleDaily(
        id: 7,
        title: 'N',
        body: 'R',
        hour: 24,
        minute: 0,
      ),
      NotificationSchedulingOutcome.failed,
    );
    expect(
      await service.scheduleAt(
        id: 7,
        title: 'N',
        body: 'R',
        when: AppClock.now(),
      ),
      NotificationSchedulingOutcome.failed,
    );
    expect(os.scheduled, isEmpty);
  });

  test('daily first fire retains 09:00 through DST fall-back', () async {
    os.timezone = 'America/New_York';
    await service.refreshLocalTimezone(forceRefresh: true);
    AppClock.now = () =>
        tz.TZDateTime(tz.getLocation('America/New_York'), 2030, 11, 2, 22);
    expect(
      await service.scheduleDaily(
        id: 8,
        title: 'N',
        body: 'R',
        hour: 9,
        minute: 0,
      ),
      NotificationSchedulingOutcome.accepted,
    );
    expect(os.scheduled.single['scheduledDateTime'], '2030-11-03T09:00:00');
    expect(os.scheduled.single['timeZoneName'], 'America/New_York');
  });

  test(
    'local opt-out completes while an older episode read is still pending',
    () async {
      await preferences(active: true);
      final repo = EpisodeRepo()
        ..held = Completer<LoadResult<BleedingEpisode?>>();
      final old = NotificationRefreshCoordinator.refresh(
        userId: 'u',
        bleedingRepository: repo,
      );
      await repo.started.future;
      os.pending[4567] = {
        'id': 4567,
        'payload': ActiveBleedingReminderScheduler.payloadFor(
          userId: 'u',
          episodeId: 'new',
          localDay: DateTime(2030, 1, 15),
        ),
      };
      await preferences(active: false);
      await NotificationRefreshCoordinator.refresh(
        userId: 'u',
        bleedingRepository: repo,
      );
      expect(os.pending, isEmpty);
      repo.held!.complete(LoadSuccess(EpisodeRepo.episode()));
      await old;
      expect(os.pending, isEmpty);
      expect(repo.reads, 1);
      expect(
        (await NotificationEventLogStore.loadAll()).any(
          (e) => e.state == NotificationEventState.scheduled,
        ),
        isFalse,
      );
    },
  );

  test('new episodes replace old episode requests without exhausting pending capacity', () async {
    await preferences(active: true, prayer: true, wellbeing: true);
    await PrayerLocationController.instance.select(
      PrayerLocationController.mecca,
    );
    os.pending[5000] = {
      'id': 5000,
      'payload': ActiveBleedingReminderScheduler.payloadFor(
        userId: 'u',
        episodeId: 'old',
        localDay: DateTime(2030, 1, 20),
      ),
    };
    await NotificationRefreshCoordinator.refresh(
      userId: 'u',
      bleedingRepository: EpisodeRepo(),
    );
    expect(os.pending, isNot(contains(5000)));
    expect(os.pending.length, lessThanOrEqualTo(59));
    final active = os.pending.values.where(
      (p) =>
          (p['payload'] as String?)?.contains('activeBleedingCheckin') ?? false,
    );
    expect(active.length, 30);
    expect(
      active.every(
        (p) => jsonDecode(p['payload'] as String)['episodeId'] == 'new',
      ),
      isTrue,
    );
    expect(
      os.pending.keys.where(PrayerReminderScheduler.ids.contains),
      isNotEmpty,
    );
    await preferences();
    await NotificationRefreshCoordinator.refresh(
      userId: 'u',
      bleedingRepository: EpisodeRepo(),
    );
    expect(os.pending, isEmpty);
  });

  test(
    'wellbeing uses its saved clock time and discreet lock-screen copy',
    () async {
      await preferences(wellbeing: true, hour: 17, minute: 25);
      await NotificationRefreshCoordinator.refresh(
        userId: 'u',
        bleedingRepository: EpisodeRepo(),
      );
      final request =
          os.pending[NotificationRefreshCoordinator.wellbeingReminderId]!;
      expect(request['scheduledDateTime'], '2030-01-15T17:25:00');
      expect(request['body'], NotificationScheduler.discreetBodyAr);
    },
  );

  test('signed-out refresh cancels reminders and schedules nothing', () async {
    await schedule(9);
    await NotificationRefreshCoordinator.refresh(userId: null);
    expect(os.pending, isEmpty);
  });

  test(
    'malformed records preserve valid opt-outs and never become prayer opt-ins',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'niswah_notification_preferences',
        jsonEncode([
          {
            'type': 'wellbeing',
            'enabled': false,
            'lead_time_minutes': 0,
            'channels': ['local'],
          },
          {
            'type': 'activeBleeding',
            'enabled': true,
            'lead_time_minutes': 0,
            'channels': ['local'],
            'preferred_hour': 99,
            'preferred_minute': 0,
          },
          {
            'type': 'unknown',
            'enabled': true,
            'lead_time_minutes': 0,
            'channels': ['local'],
          },
        ]),
      );
      final loaded = await NotificationRepositoryImpl().loadPreferences();
      expect(loaded[NotificationType.wellbeing]!.enabled, isFalse);
      expect(loaded[NotificationType.activeBleeding]!.enabled, isFalse);
      expect(loaded[NotificationType.prayer]!.enabled, isFalse);
      await prefs.setString('niswah_notification_preferences', '{');
      expect(
        (await NotificationRepositoryImpl().loadPreferences()).values.every(
          (p) => !p.enabled,
        ),
        isTrue,
      );
    },
  );

  test(
    'parallel audit writes retain distinct events and deduplicate retries',
    () async {
      NotificationEvent event(String id) => NotificationEvent(
        reminderId: id,
        notificationType: 'activeBleeding',
        state: NotificationEventState.scheduled,
        eventTimestamp: AppClock.now(),
        userId: 'u',
      );
      await Future.wait([
        for (var i = 0; i < 30; i++)
          NotificationEventLogStore.record(event('$i')),
        NotificationEventLogStore.record(event('0')),
      ]);
      expect(await NotificationEventLogStore.loadAll(), hasLength(30));
    },
  );

  test(
    'a feed write keeps the account it started under across a switch',
    () async {
      SecureLocalStore.debugUserIdOverride = 'a';
      await NotificationLogController.instance.load();
      final old = NotificationLogController.instance.add(
        NotificationLogEntry(
          id: 'a1',
          type: NotificationType.wellbeing,
          titleAr: 'a',
          bodyAr: 'a',
          titleEn: 'a',
          bodyEn: 'a',
          createdAt: AppClock.now(),
        ),
      );
      SecureLocalStore.debugUserIdOverride = 'b';
      NotificationLogController.instance.resetInMemory();
      await NotificationLogController.instance.load();
      await old;
      expect(NotificationLogController.instance.entries, isEmpty);
      SecureLocalStore.debugUserIdOverride = 'a';
      await NotificationLogController.instance.load();
      expect(NotificationLogController.instance.entries.single.id, 'a1');
    },
  );
  for (final readFails in [true, false]) {
    test(
      'failed ${readFails ? 'pending read' : 'stale cancellation'} cannot overlap tracking windows',
      () async {
        await preferences(active: true, wellbeing: true);
        os.pending[5000] = {
          'id': 5000,
          'payload': jsonEncode({
            'type': 'activeBleedingCheckin',
            'userId': 'u',
            'episodeId': 'old',
            'localDate': '2030-01-16',
          }),
        };
        if (readFails) {
          os.failPendingRead = true;
        } else {
          os.failedCancellations.add(5000);
        }
        await NotificationRefreshCoordinator.refresh(
          userId: 'u',
          bleedingRepository: EpisodeRepo(),
        );
        expect(os.pending, contains(5000));
        expect(
          os.scheduled.where(
            (p) =>
                p['payload']?.toString().contains('activeBleedingCheckin') ??
                false,
          ),
          isEmpty,
        );
        // An independent local reminder still reconciles despite tracking failure.
        expect(os.scheduled, isNotEmpty);
        os.failPendingRead = false;
        os.failedCancellations.clear();
        await NotificationRefreshCoordinator.refresh(
          userId: 'u',
          bleedingRepository: EpisodeRepo(),
        );
        expect(os.pending, isNot(contains(5000)));
        expect(os.pending.length, lessThanOrEqualTo(31));
      },
    );
  }
}
