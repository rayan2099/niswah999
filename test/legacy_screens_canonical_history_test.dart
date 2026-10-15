import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';

import 'support/parity_test_harness.dart';

class _FakeRepository implements CycleTrackingRepository {
  _FakeRepository(this.logs);
  final List<CycleLog> logs;

  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async => logs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// ParityTestHarness pins AppClock to 2026-08-18 12:00.
final _today = DateTime(2026, 8, 18);

/// A returning user: onboarding recorded a real, ended period 32 -> 27
/// days ago (canonical only — its start observation is flow=uncertain and
/// is never projected), and she then started a period today through the
/// normal flow (projected into cycle_entries).
CycleTrackingViewModel _returningUserViewModel({bool canonicalLoads = true}) =>
    CycleTrackingViewModel(
      repository: _FakeRepository([
        CycleLog(
          id: 'today',
          userId: 'local-user',
          date: _today,
          flow: FlowLevel.medium,
          cycleDay: 1,
        ),
      ]),
      canonicalEpisodeLoader: (_) async => canonicalLoads
          ? [
              CanonicalEpisodeTiming(
                startDate: _today.subtract(const Duration(days: 32)),
                endDate: _today.subtract(const Duration(days: 27)),
              ),
            ]
          : throw StateError('canonical read failed'),
    );

const _insufficientInsights = 'Log two cycle starts to enable predictions.';
const _insufficientCalendar =
    'Log at least two cycle starts to see cycle progress';

void main() {
  testWidgets('Insights no longer tells a woman with two real period starts '
      'to log two cycle starts, and shows the reported period', (tester) async {
    final vm = _returningUserViewModel();
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      size: const Size(390, 4000),
      homeOverride: Scaffold(body: InsightsScreen(viewModel: vm)),
    );
    await vm.loadLogs();
    await tester.pumpAndSettle();

    expect(find.text(_insufficientInsights), findsNothing);
    expect(vm.cycleCalculation.averageCycleLength, 32);
    expect(find.textContaining('32'), findsWidgets);
    // Regularity legitimately still needs a second interval (variance
    // needs two cycles) — the ONLY "Insufficient data" left on screen.
    expect(find.text('Insufficient data'), findsOneWidget);
    // No "No cycle history yet" while a real reported period exists.
    expect(find.text('No cycle history yet'), findsNothing);
    expect(find.textContaining('Reported period'), findsOneWidget);
  });

  testWidgets('Calendar no longer says "log two cycle starts" for the same '
      'account', (tester) async {
    final vm = _returningUserViewModel();
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      size: const Size(390, 4000),
      homeOverride: Scaffold(body: CycleTrackingScreen(viewModel: vm)),
    );
    await vm.loadLogs();
    await tester.pumpAndSettle();

    expect(find.text(_insufficientCalendar), findsNothing);
  });

  testWidgets('a FAILED canonical read degrades to the previous behavior '
      'honestly — no crash, no fabricated history', (tester) async {
    final vm = _returningUserViewModel(canonicalLoads: false);
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      size: const Size(390, 4000),
      homeOverride: Scaffold(body: InsightsScreen(viewModel: vm)),
    );
    await vm.loadLogs();
    await tester.pumpAndSettle();

    expect(vm.cycleCalculation.haidStarts, hasLength(1));
    expect(find.text(_insufficientInsights), findsOneWidget);
  });

  testWidgets('with genuinely no history anywhere the honest empty states '
      'remain', (tester) async {
    final vm = CycleTrackingViewModel(
      repository: _FakeRepository(const []),
      canonicalEpisodeLoader: (_) async => const [],
    );
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      size: const Size(390, 4000),
      homeOverride: Scaffold(body: InsightsScreen(viewModel: vm)),
    );
    await vm.loadLogs();
    await tester.pumpAndSettle();

    expect(find.text('No cycle history yet'), findsOneWidget);
    expect(find.text(_insufficientInsights), findsOneWidget);
  });
}
