import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/features/pregnancy_tracking/domain/entities/pregnancy_milestone.dart';
import 'package:niswah/features/pregnancy_tracking/domain/controllers/pregnancy_calculator.dart';
import 'package:niswah/features/pregnancy_tracking/data/repositories/pregnancy_tracking_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('PregnancyCalculator', () {
    test('calculates the current pregnancy week from LMP', () {
      final lmp = DateTime(2026, 1, 10);
      final now = DateTime(2026, 8, 18);

      final week = PregnancyCalculator.currentWeekFromLmp(lmp: lmp, now: now);
      expect(week, 31);
    });

    test('builds trimester and milestone info for an expected due date', () {
      final dueDate = DateTime(2026, 10, 15);
      final milestone = PregnancyCalculator.milestoneForDueDate(
        dueDate: dueDate,
        now: DateTime(2026, 8, 18),
      );

      expect(milestone.trimester, PregnancyTrimester.third);
      expect(milestone.week, greaterThanOrEqualTo(28));
      expect(milestone.label, isNotEmpty);
    });
  });

  group('PregnancyTrackingRepositoryImpl', () {
    test('persists and reads pregnancy milestones for a user', () async {
      final repository = PregnancyTrackingRepositoryImpl();
      final now = DateTime(2026, 8, 18);

      final milestone = PregnancyMilestone(
        id: 'milestone-1',
        userId: 'user-1',
        week: 28,
        trimester: PregnancyTrimester.second,
        label: 'Baby is developing rapidly',
        summary: 'Your baby is growing steadily at this stage.',
        date: now,
      );

      await repository.saveMilestone(milestone);
      final entries = await repository.getMilestonesForUser('user-1');

      expect(entries.length, 1);
      expect(entries.first.id, 'milestone-1');
      expect(entries.first.label, 'Baby is developing rapidly');
    });
  });
}
