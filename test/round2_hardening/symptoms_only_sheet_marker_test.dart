// Round-2 hardening (2026-10-21, proposed): a "Symptoms & notes" entry for
// a day with no row records no flow fact (CycleLog.symptomsOnlyMarker), so
// it never ends a period in the legacy statistics.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import '../support/parity_test_harness.dart';

class _EmptyCanonicalRepository extends BleedingEpisodeRepositoryImpl {
  _EmptyCanonicalRepository() : super(client: null);
  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String u,
  ) async => const LoadSuccess(<BleedingEpisode>[]);
  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String u,
  ) async => const LoadSuccess(<BleedingObservation>[]);
}

Map<String, Object?> _log(String id, String date, String flow, int day) => {
  'id': id,
  'user_id': 'local-user',
  'date': '${date}T00:00:00.000',
  'flow': flow,
  'cycle_day': day,
  'sync_status': 'synced',
};

void main() {
  testWidgets('Today ring -> "Symptoms & notes" on a bleeding day with no '
      'row yet does not end the period in the legacy statistics', (
    tester,
  ) async {
    // Bleeding Aug 16-17 (harness clock: Aug 18, 12:00); nothing logged
    // for Aug 18 yet. Two earlier periods so the ring branch renders.
    final logsJson = jsonEncode([
      _log('a', '2026-06-20', 'medium', 1),
      _log('b', '2026-06-25', 'none', 6),
      _log('c', '2026-07-18', 'medium', 1),
      _log('d', '2026-07-23', 'none', 6),
      _log('e', '2026-08-16', 'medium', 1),
      _log('f', '2026-08-17', 'medium', 2),
    ]);
    final vm = CycleTrackingViewModel(
      canonicalEpisodeLoader: (_) async => const [],
      statedBaselineLoader: (_) async => null,
    );
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      size: const Size(390, 2400),
      extraPrefs: {
        'niswah_cycle_tracking_logs': logsJson,
        'flutter.niswah_cycle_tracking_logs': logsJson,
      },
      homeOverride: DashboardScreen(
        viewModel: vm,
        canonicalRepositoryOverride: _EmptyCanonicalRepository(),
        canonicalUserIdOverride: 'user-1',
      ),
    );
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
    await tester.pumpAndSettle();
    final startsBefore = vm.cycleCalculation.haidStarts;

    await tester.tap(find.byKey(const Key('today-cycle-ring')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-day-choice-symptoms')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save log'));
    await tester.tap(find.text('Save log'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final saved = vm.logs.where(
      (log) => DateUtils.isSameDay(log.date, DateTime(2026, 8, 18)),
    );
    expect(saved, hasLength(1), reason: 'precondition: the entry was saved');
    expect(saved.single.recordsFlow, isFalse);
    expect(saved.single.symptoms, contains(CycleLog.symptomsOnlyMarker));

    // Aug 19: still bleeding (the check-in's mirror row).
    final withNextDay = [
      ...vm.logs,
      CycleLog(
        id: 'g',
        userId: 'local-user',
        date: DateTime(2026, 8, 19),
        flow: FlowLevel.medium,
        cycleDay: 4,
      ),
    ];
    expect(
      vm.cycleCalculation.haidStarts,
      startsBefore,
      reason: 'the symptoms-only row must not add or end a period',
    );
    expect(
      const CycleCalculationService()
          .calculate(withNextDay, asOf: DateTime(2026, 8, 19, 12))
          .haidStarts,
      startsBefore,
      reason: 'Aug 19 bleeding continues the Aug 16 period',
    );
  });
}
