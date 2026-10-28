import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';
import 'package:niswah/features/wellbeing/data/repositories/wellbeing_repository.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';

import 'support/parity_test_harness.dart';

class _NoCycleRepository implements CycleTrackingRepository {
  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<WellbeingLog> _logs(int count) => [
  for (var day = 1; day <= count; day++)
    WellbeingLog(
      id: 'w$day',
      userId: 'local-user',
      logDate: DateTime(2026, 8, day),
      mood: 4,
      energy: 3,
      sleep: 2,
    ),
];

Future<void> _pumpInsights(
  WidgetTester tester,
  Future<List<WellbeingLog>> Function(DateTime from) load, {
  bool settle = true,
}) async {
  final vm = CycleTrackingViewModel(
    repository: _NoCycleRepository(),
    canonicalEpisodeLoader: (_) async => const [],
  );
  await ParityTestHarness.pump(
    tester,
    arabic: false,
    size: const Size(390, 4000),
    homeOverride: Scaffold(
      body: InsightsScreen(viewModel: vm, loadWellbeingLogs: load),
    ),
  );
  await vm.loadLogs();
  // A pending load shows a spinner, which never settles.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  // Device run 2026-10-28: mood check-ins never reached Insights, and
  // nothing showed without a period. With no period logged at all they
  // must still show, counted as days without a period.
  testWidgets('mood check-ins show in Insights with no period logged', (
    tester,
  ) async {
    final vm = CycleTrackingViewModel(
      repository: _NoCycleRepository(),
      canonicalEpisodeLoader: (_) async => const [],
    );
    // ParityTestHarness pins AppClock to 2026-08-18.
    final logs = [
      for (var day = 10; day <= 12; day++)
        WellbeingLog(
          id: 'w$day',
          userId: 'local-user',
          logDate: DateTime(2026, 8, day),
          mood: 4,
          energy: 3,
          sleep: 2,
        ),
    ];
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      size: const Size(390, 4000),
      homeOverride: Scaffold(
        body: InsightsScreen(
          viewModel: vm,
          loadWellbeingLogs: (_) async => logs,
        ),
      ),
    );
    await vm.loadLogs();
    await tester.pumpAndSettle();

    expect(find.text('Mood & wellbeing'), findsOneWidget);
    expect(find.text('All days · 3 check-ins'), findsOneWidget);
    expect(find.text('Period days · 0 check-ins'), findsOneWidget);
    expect(find.text('Days without a period · 3 check-ins'), findsOneWidget);
    expect(find.textContaining('Mood 4.0/5'), findsNWidgets(2));
  });

  testWidgets('a new check-in shows without leaving the screen', (
    tester,
  ) async {
    var stored = _logs(2);
    await _pumpInsights(tester, (_) async => stored);
    expect(find.text('All days · 2 check-ins'), findsOneWidget);

    stored = _logs(3);
    WellbeingRepository.revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('All days · 3 check-ins'), findsOneWidget);
  });

  testWidgets('an older request finishing last does not replace newer '
      'results', (tester) async {
    final pending = <Completer<List<WellbeingLog>>>[];
    await _pumpInsights(tester, (_) {
      final completer = Completer<List<WellbeingLog>>();
      pending.add(completer);
      return completer.future;
    }, settle: false);
    pending.removeAt(0).complete(_logs(1));
    await tester.pumpAndSettle();

    WellbeingRepository.revision.value++; // older request
    WellbeingRepository.revision.value++; // newer request
    await tester.pump();
    expect(pending, hasLength(2));
    pending[1].complete(_logs(2));
    await tester.pumpAndSettle();
    pending[0].complete(_logs(5));
    await tester.pumpAndSettle();

    expect(find.text('All days · 2 check-ins'), findsOneWidget);
  });
}
