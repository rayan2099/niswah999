import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/features/pregnancy_tracking/domain/entities/pregnancy_milestone.dart';
import 'package:niswah/features/pregnancy_tracking/domain/controllers/pregnancy_calculator.dart';
import 'package:niswah/features/pregnancy_tracking/data/repositories/pregnancy_tracking_repository_impl.dart';
import 'package:niswah/features/pregnancy_tracking/presentation/viewmodels/pregnancy_tracking_view_model.dart';

import 'support/secure_storage_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
  });

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

  group('PregnancyTrackingRepositoryImpl (W0-002)', () {
    test(
      'persists and reads pregnancy milestones for a user (local-authoritative)',
      () async {
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

        final status = await repository.saveMilestone(milestone);
        final entries = await repository.getMilestonesForUser('user-1');

        expect(entries.length, 1);
        expect(entries.first.id, 'milestone-1');
        expect(entries.first.label, 'Baby is developing rapidly');
        // No Supabase client configured in this test environment — matches
        // CycleTrackingRepositoryImpl's own established "no client means
        // nothing to sync to" contract, not a new judgment call.
        expect(status, PregnancySyncStatus.synced);
      },
    );

    test(
      'syncPendingMilestones is a safe no-op with no client configured',
      () async {
        final repository = PregnancyTrackingRepositoryImpl();
        final result = await repository.syncPendingMilestones();

        expect(result.synced, 0);
        expect(result.stillPending, 0);
        expect(result.permanentlyFailed, 0);
        expect(result.hadWork, isFalse);
      },
    );

    test('deleting one entry leaves other entries intact', () async {
      final repository = PregnancyTrackingRepositoryImpl();
      await repository.saveMilestone(
        PregnancyMilestone(
          id: 'm1',
          userId: 'user-1',
          week: 10,
          trimester: PregnancyTrimester.first,
          label: 'A',
          summary: 'A',
          date: DateTime(2026, 8, 1),
        ),
      );
      await repository.saveMilestone(
        PregnancyMilestone(
          id: 'm2',
          userId: 'user-1',
          week: 11,
          trimester: PregnancyTrimester.first,
          label: 'B',
          summary: 'B',
          date: DateTime(2026, 8, 8),
        ),
      );

      await repository.deleteMilestone('m1');
      final remaining = await repository.getMilestonesForUser('user-1');

      expect(remaining.length, 1);
      expect(remaining.single.id, 'm2');
    });
  });

  group('PregnancyTrackingViewModel — real data, not fabricated (W0-002)', () {
    test(
      'isTrackingPregnancy is false and no week is fabricated when the '
      'user has never activated pregnancy tracking',
      () async {
        await PregnancyStatusController.instance.deactivate();
        final viewModel = PregnancyTrackingViewModel(
          repository: PregnancyTrackingRepositoryImpl(),
        );
        await viewModel.loadMilestones();

        expect(
          viewModel.isTrackingPregnancy,
          isFalse,
          reason:
              'previously this ViewModel always showed a fabricated week '
              'regardless of real pregnancy-tracking state',
        );
      },
    );

    test(
      'currentWeek reflects the real PregnancyStatusController activation, '
      'not a hardcoded constant',
      () async {
        await PregnancyStatusController.instance.activate(startWeek: 15);
        final viewModel = PregnancyTrackingViewModel(
          repository: PregnancyTrackingRepositoryImpl(),
        );
        await viewModel.loadMilestones();

        expect(viewModel.isTrackingPregnancy, isTrue);
        expect(
          viewModel.currentWeek,
          15,
          reason:
              'must match the real activated week, not the previous '
              'hardcoded "30 weeks before now" fake LMP',
        );

        await PregnancyStatusController.instance.deactivate();
      },
    );
  });
}
