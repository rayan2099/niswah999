// Pregnancy/notifications hardening (2026-10-21) — regression test: the
// Nifas card counts elapsed days since the logged birth date (the same
// count as the reports and the reminder copy). Elapsed day 0 reads "Birth
// day", then "Day 1/40" … "Day 40/40"; it can never read "Day 41/40", and
// on elapsed day 41 the card is gone. Proposed default pending the owner's
// numbering decision.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import '../support/parity_test_harness.dart';

class _EmptyRepo extends BleedingEpisodeRepositoryImpl {
  _EmptyRepo() : super(client: null);
  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String u,
  ) async => const LoadSuccess([]);
  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String u,
  ) async => const LoadSuccess([]);
}

/// Harness clock: 2026-08-18 12:00. Birth logged [elapsed] days earlier.
Future<void> _pumpWithBirth(
  WidgetTester tester,
  int elapsed, {
  bool arabic = false,
}) async {
  final birth = DateTime(2026, 8, 18 - elapsed);
  await ParityTestHarness.pump(
    tester,
    arabic: arabic,
    extraPrefs: {'niswah_nifas_started_at': birth.toIso8601String()},
    homeOverride: DashboardScreen(
      canonicalRepositoryOverride: _EmptyRepo(),
      canonicalUserIdOverride: 'user-1',
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inCard(String text) => find.descendant(
  of: find.byKey(const Key('nifas-status')),
  matching: find.text(text),
);

void main() {
  testWidgets('elapsed day 0 reads "Birth day", 40 days remaining', (
    tester,
  ) async {
    await _pumpWithBirth(tester, 0);
    expect(_inCard('Birth day'), findsOneWidget);
    expect(_inCard('Up to 40 days remaining'), findsOneWidget);
    expect(find.textContaining('/40'), findsNothing);
  });

  testWidgets('elapsed day 0 in Arabic reads "يوم الولادة"', (tester) async {
    await _pumpWithBirth(tester, 0, arabic: true);
    expect(_inCard('يوم الولادة'), findsOneWidget);
  });

  testWidgets('elapsed day 1 reads "Day 1/40", 39 remaining', (tester) async {
    await _pumpWithBirth(tester, 1);
    expect(_inCard('Day 1/40'), findsOneWidget);
    expect(_inCard('Up to 39 days remaining'), findsOneWidget);
  });

  testWidgets('elapsed day 40 reads "Day 40/40", never "Day 41/40"', (
    tester,
  ) async {
    await _pumpWithBirth(tester, 40);
    expect(_inCard('Day 40/40'), findsOneWidget);
    expect(_inCard('Up to 0 days remaining'), findsOneWidget);
    expect(find.text('Day 41/40'), findsNothing);
  });

  testWidgets('elapsed day 41: the Nifas card is gone', (tester) async {
    await _pumpWithBirth(tester, 41);
    expect(find.byKey(const Key('nifas-status')), findsNothing);
  });

  test('label helper never exceeds the window denominator', () {
    expect(nifasDayLabel(0), 'Birth day');
    for (var d = 1; d <= 40; d++) {
      expect(nifasDayLabel(d), 'Day $d/40');
    }
  });
}
