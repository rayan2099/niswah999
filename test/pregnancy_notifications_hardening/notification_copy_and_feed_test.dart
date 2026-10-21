// Pregnancy/notifications hardening (2026-10-21) — regression tests for
// findings 4 (feed entries appear at fire time, no duplicates), 5 (no
// cycle reminder while pregnant or in nifas), 7 (neutral nifas copy) and
// 12 (discreet lock-screen copy).
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/notification_log_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/notifications/domain/entities/notification_preference.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _calculation = CycleCalculationResult(
  haidStarts: [DateTime(2026, 1, 1), DateTime(2026, 1, 29)],
  currentCycleDay: 5,
  averageCycleLength: 28,
  cycleLengths: const [28],
  predictedCycleLength: 28,
  predictionSpreadDays: 3,
);

PregnancyProfile _postpartum(DateTime birth) => PregnancyProfile(
  id: 'p',
  userId: 'u',
  isPostpartum: true,
  postpartumStartDate: birth,
);

NotificationLogEntry _entry(String id, DateTime fireAt) => NotificationLogEntry(
  id: id,
  type: NotificationType.pregnancy,
  titleAr: 't',
  bodyAr: 'b',
  titleEn: 't',
  bodyEn: 'b',
  createdAt: DateTime(2026, 3, 1, 8),
  fireAt: fireAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cycle reminder is withheld while pregnant or in nifas', () {
    final now = DateTime(2026, 2, 1);

    test('baseline: not pregnant -> a reminder is planned', () {
      expect(
        NotificationScheduler.planCycleReminder(
          calculation: _calculation,
          now: now,
        ),
        isNotNull,
      );
    });

    test('pregnant (synced profile) -> nothing', () {
      final status = PregnancyStatusEngine.getStatus(
        PregnancyProfile(
          id: 'p',
          userId: 'u',
          trackingBasis: TrackingBasis.manualWeek,
          manualWeekValue: 4,
          manualWeekSetAt: DateTime(2026, 1, 25),
        ),
        now,
      );
      expect(
        NotificationScheduler.planCycleReminder(
          calculation: _calculation,
          now: now,
          pregnancy: status,
        ),
        isNull,
      );
    });

    test('pregnant or in nifas on this device only -> nothing', () {
      expect(
        NotificationScheduler.planCycleReminder(
          calculation: _calculation,
          now: now,
          locallyPregnant: true,
        ),
        isNull,
      );
      expect(
        NotificationScheduler.planCycleReminder(
          calculation: _calculation,
          now: now,
          locallyInNifas: true,
        ),
        isNull,
      );
    });

    test('inside the nifas phase -> nothing; after it -> planned', () {
      final inNifas = PregnancyStatusEngine.getStatus(
        _postpartum(DateTime(2026, 1, 20)),
        now,
      );
      expect(
        NotificationScheduler.planCycleReminder(
          calculation: _calculation,
          now: now,
          pregnancy: inNifas,
        ),
        isNull,
      );
      final afterNifas = PregnancyStatusEngine.getStatus(
        _postpartum(DateTime(2025, 10, 1)),
        now,
      );
      expect(afterNifas.phase, PregnancyStatusEngine.postNifasPhase);
      expect(
        NotificationScheduler.planCycleReminder(
          calculation: _calculation,
          now: now,
          pregnancy: afterNifas,
        ),
        isNotNull,
      );
    });
  });

  group('lock-screen and nifas copy', () {
    final cycle = NotificationScheduler.planCycleReminder(
      calculation: _calculation,
      now: DateTime(2026, 2, 1),
    )!;
    final pregnancy = NotificationScheduler.planPregnancyMilestone(
      profile: PregnancyProfile(
        id: 'p',
        userId: 'u',
        trackingBasis: TrackingBasis.manualWeek,
        manualWeekValue: 12,
        manualWeekSetAt: DateTime(2026, 1, 25, 8),
      ),
      now: DateTime(2026, 1, 28, 12),
    )!;
    final nifas = NotificationScheduler.planNifasCountdown(
      profile: _postpartum(DateTime(2026, 1, 1)),
      now: DateTime(2026, 1, 10),
    )!;

    test('cycle, pregnancy and nifas OS text is the discreet copy', () {
      for (final plan in [cycle, pregnancy, nifas]) {
        expect(plan.titleEn, NotificationScheduler.discreetTitleEn);
        expect(plan.bodyEn, NotificationScheduler.discreetBodyEn);
        expect(plan.titleAr, NotificationScheduler.discreetTitleAr);
        expect(plan.bodyAr, NotificationScheduler.discreetBodyAr);
      }
    });

    test('the specific text is kept for the in-app feed', () {
      expect(cycle.feedTitleEn, 'Your period may be approaching');
      expect(pregnancy.feedBodyEn, contains('week 13'));
    });

    test('nifas feed copy never claims nifas is ending', () {
      final texts = [
        nifas.feedTitleEn,
        nifas.feedBodyEn,
        nifas.feedTitleAr,
        nifas.feedBodyAr,
      ].join(' ');
      for (final claim in ['end', 'remain', 'انتهاء', 'تبقّى', 'تبقى']) {
        expect(texts.toLowerCase(), isNot(contains(claim)));
      }
      expect(nifas.feedTitleEn, 'Nifas tracking');
      expect(nifas.feedBodyEn, contains('35 days since the birth date'));
      expect(nifas.feedBodyAr, contains('35'));
    });

    test('no nifas reminder after the engine nifas phase', () {
      expect(
        NotificationScheduler.planNifasCountdown(
          profile: _postpartum(DateTime(2026, 1, 1)),
          now: DateTime(2026, 3, 1),
        ),
        isNull,
      );
    });
  });

  group('feed entries appear at fire time, never duplicated', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      AppClock.now = () => DateTime(2026, 3, 1, 8);
      await NotificationLogController.instance.load();
    });
    tearDown(() => AppClock.now = DateTime.now);

    test(
      'a scheduled entry is hidden (and not unread) until it fires',
      () async {
        final log = NotificationLogController.instance;
        await log.upsertScheduled(
          '102',
          _entry('102_a', DateTime(2026, 3, 2, 9)),
        );
        expect(log.entries, isEmpty);
        expect(log.unreadCount, 0);

        AppClock.now = () => DateTime(2026, 3, 2, 9);
        expect(log.entries.single.id, '102_a');
        expect(log.entries.single.shownAt, DateTime(2026, 3, 2, 9));
        expect(log.unreadCount, 1);
      },
    );

    test(
      're-scheduling the same plan or moving it never adds a second entry',
      () async {
        final log = NotificationLogController.instance;
        await log.upsertScheduled(
          '102',
          _entry('102_a', DateTime(2026, 3, 2, 9)),
        );
        await log.upsertScheduled(
          '102',
          _entry('102_a', DateTime(2026, 3, 2, 9)),
        );
        await log.upsertScheduled(
          '102',
          _entry('102_b', DateTime(2026, 3, 3, 9)),
        );
        expect(log.allEntries.map((e) => e.id), ['102_b']);

        AppClock.now = () => DateTime(2026, 3, 4);
        expect(log.entries.map((e) => e.id), ['102_b']);
      },
    );

    test(
      'a fired entry stays as history; a cancelled pending one is dropped',
      () async {
        final log = NotificationLogController.instance;
        await log.upsertScheduled(
          '102',
          _entry('102_a', DateTime(2026, 3, 1, 7)),
        );
        await log.upsertScheduled(
          '102',
          _entry('102_b', DateTime(2026, 3, 8, 9)),
        );
        await log.upsertScheduled(
          '1020',
          _entry('1020_x', DateTime(2026, 3, 9)),
        );
        await log.removePending('102');
        expect(log.allEntries.map((e) => e.id).toSet(), {'102_a', '1020_x'});
      },
    );

    test('fireAt survives a reload', () async {
      final log = NotificationLogController.instance;
      await log.upsertScheduled(
        '103',
        _entry('103_a', DateTime(2026, 3, 5, 9)),
      );
      await log.load();
      expect(log.allEntries.single.fireAt, DateTime(2026, 3, 5, 9));
      expect(log.entries, isEmpty);
    });
  });
}
