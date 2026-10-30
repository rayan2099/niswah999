// PT-079: when a prediction cannot be supported, Insights says so in the
// agreed wording and shows no date.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';

import '../support/parity_test_harness.dart';

class _FakeRepository implements CycleTrackingRepository {
  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final arabic in [true, false]) {
    testWidgets('PT-079 (${arabic ? 'ar' : 'en'}): no history means the '
        'expected-period card says there is not enough data, with no date', (
      tester,
    ) async {
      final vm = CycleTrackingViewModel(
        repository: _FakeRepository(),
        canonicalEpisodeLoader: (_) async => const [],
      );
      await ParityTestHarness.pump(
        tester,
        arabic: arabic,
        size: const Size(390, 4000),
        homeOverride: Scaffold(body: InsightsScreen(viewModel: vm)),
      );
      await vm.loadLogs();
      await tester.pumpAndSettle();

      expect(
        find.text(
          arabic
              ? 'لا تتوفر بيانات كافية للتوقع'
              : 'Not enough data for a prediction',
        ),
        findsOneWidget,
      );
      // No fabricated date anywhere on the card (d/m/yyyy).
      expect(
        find.textContaining(RegExp(r'\d{1,2}/\d{1,2}/\d{4}')),
        findsNothing,
      );
    });
  }
}
