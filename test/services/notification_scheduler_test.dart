import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

void main() {
  group('NotificationScheduler.planCycleReminder', () {
    test('insufficient history plans nothing', () {
      const calculation = CycleCalculationResult(
        haidStarts: [],
        currentCycleDay: null,
        averageCycleLength: null,
        cycleLengths: [],
      );

      final plan = NotificationScheduler.planCycleReminder(
        calculation: calculation,
        now: DateTime(2026, 1, 10),
      );

      expect(plan, isNull);
    });

    test('plans a reminder 3 days before the predicted next start', () {
      final calculation = CycleCalculationResult(
        haidStarts: [DateTime(2026, 1, 1), DateTime(2026, 1, 29)],
        currentCycleDay: 5,
        averageCycleLength: 28,
        cycleLengths: const [28],
      );

      final plan = NotificationScheduler.planCycleReminder(
        calculation: calculation,
        now: DateTime(2026, 1, 10),
      );

      // predicted next start = Jan 29 + 28 = Feb 26; lead day = Feb 23.
      expect(plan, isNotNull);
      expect(plan!.fireAt, DateTime(2026, 2, 23, 9));
    });

    test('a predicted date already in the past plans nothing', () {
      final calculation = CycleCalculationResult(
        haidStarts: [DateTime(2026, 1, 1), DateTime(2026, 1, 5)],
        currentCycleDay: 1,
        averageCycleLength: 4,
        cycleLengths: const [4],
      );

      final plan = NotificationScheduler.planCycleReminder(
        calculation: calculation,
        now: DateTime(2026, 6, 1),
      );

      expect(plan, isNull);
    });
  });

  group('NotificationScheduler.planPregnancyMilestone', () {
    test('not pregnant plans nothing', () {
      final plan = NotificationScheduler.planPregnancyMilestone(
        profile: null,
        now: DateTime(2026, 1, 10),
      );
      expect(plan, isNull);
    });

    test('finds the next weekly boundary within 7 days', () {
      // week = floor(daysSinceLmp / 7). lmp = Jan 1 => "now" Jan 10 is
      // 9 days in => week 1 (floor(9/7)=1). Week becomes 2 at day 14 =>
      // Jan 15, 4 days from "now".
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'u1',
        trackingBasis: TrackingBasis.lmp,
        referenceDate: DateTime(2026, 1, 1),
      );

      final plan = NotificationScheduler.planPregnancyMilestone(
        profile: profile,
        now: DateTime(2026, 1, 10),
      );

      expect(plan, isNotNull);
      expect(plan!.fireAt, DateTime(2026, 1, 15, 9));
      expect(plan.bodyAr, contains('2'));
    });

    test('postpartum profile plans nothing here (handled by nifas planner)', () {
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'u1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 1, 1),
      );

      final plan = NotificationScheduler.planPregnancyMilestone(
        profile: profile,
        now: DateTime(2026, 1, 10),
      );

      expect(plan, isNull);
    });
  });

  group('NotificationScheduler.planNifasCountdown', () {
    test('not postpartum plans nothing', () {
      final plan = NotificationScheduler.planNifasCountdown(
        profile: null,
        now: DateTime(2026, 1, 10),
      );
      expect(plan, isNull);
    });

    test('plans a warning for day 35 when currently before it', () {
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'u1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 1, 1),
      );

      // now (Jan 10) - start (Jan 1) = 9 days postpartum (date difference,
      // not calendar day count). 35 - 9 = 26 more days => Feb 5.
      final plan = NotificationScheduler.planNifasCountdown(
        profile: profile,
        now: DateTime(2026, 1, 10),
      );

      expect(plan, isNotNull);
      expect(plan!.fireAt, DateTime(2026, 2, 5, 9));
    });

    test('past the warning day plans nothing', () {
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'u1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 1, 1),
      );

      // day 38 postpartum — already past the day-35 warning threshold.
      final plan = NotificationScheduler.planNifasCountdown(
        profile: profile,
        now: DateTime(2026, 2, 7),
      );

      expect(plan, isNull);
    });
  });
}
