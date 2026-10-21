import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import '../support/parity_test_harness.dart';

/// Screens hardening — the Today ring used to open the LEGACY log sheet in
/// period mode (initialFlow medium). Saving it wrote bleeding only to
/// cycle_entries, which Today's Fiqh state never reads, so right after she
/// logged bleeding Today still said "Day 1 of Tahara", "Fertile in 3 days"
/// and "Salah is obligatory". The ring now asks what she is logging:
/// bleeding goes to the canonical start/check-in sheets, symptoms and notes
/// to the legacy sheet in symptoms-only mode (no flow is recorded there).
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

Map<String, Object?> _log(String id, String date, String flow) => {
  'id': id,
  'user_id': 'local-user',
  'date': '${date}T08:00:00.000',
  'flow': flow,
  'cycle_day': 1,
  'sync_status': 'synced',
};

Future<CycleTrackingViewModel> _pump(WidgetTester tester) async {
  final logsJson = jsonEncode([
    _log('1', '2026-06-20', 'medium'),
    _log('2', '2026-06-25', 'none'),
    _log('3', '2026-07-18', 'medium'),
    _log('4', '2026-07-23', 'none'),
  ]);
  final vm = CycleTrackingViewModel();
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
  return vm;
}

void main() {
  testWidgets('choosing "Bleeding" from the ring opens the canonical '
      'start-bleeding sheet, not the legacy log sheet', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('today-cycle-ring')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-day-choice-bleeding')));
    await tester.pumpAndSettle();

    expect(find.text('Bleeding started'), findsOneWidget);
    expect(find.text('Save log'), findsNothing);
  });

  testWidgets('choosing "Symptoms & notes" from the ring never records '
      'bleeding in the legacy table', (tester) async {
    final vm = await _pump(tester);
    final before = vm.logs.length;
    await tester.tap(find.byKey(const Key('today-cycle-ring')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-day-choice-symptoms')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save log'));
    await tester.tap(find.text('Save log'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final added = vm.logs.skip(before).toList();
    expect(added, hasLength(1), reason: 'precondition: the entry was saved');
    expect(added.single.flow, FlowLevel.none);
    expect(vm.cycleCalculation.haidStarts, hasLength(2));
  });

  testWidgets('a Calendar-tab day tap routes bleeding to the canonical '
      'sheet too', (tester) async {
    final logsJson = jsonEncode([_log('1', '2026-07-18', 'medium')]);
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      size: const Size(390, 2400),
      extraPrefs: {
        'niswah_cycle_tracking_logs': logsJson,
        'flutter.niswah_cycle_tracking_logs': logsJson,
      },
      homeOverride: const CycleTrackingScreen(),
    );
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel(RegExp(r'^18, ')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('log-day-choice-symptoms')), findsOneWidget);
    await tester.tap(find.byKey(const Key('log-day-choice-bleeding')));
    await tester.pumpAndSettle();

    expect(find.text('Bleeding started'), findsOneWidget);
    expect(find.text('Save log'), findsNothing);
  });
}
