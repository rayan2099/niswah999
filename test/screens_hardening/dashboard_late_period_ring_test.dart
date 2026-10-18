import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import '../support/parity_test_harness.dart';

/// Screens hardening — the dashboard ring/pill when the period is LATE (or when the
/// predictor refused to predict at all). AppClock is pinned to 2026-08-18.
class _EmptyCanonicalRepository extends BleedingEpisodeRepositoryImpl {
  _EmptyCanonicalRepository() : super(client: null);

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async => const LoadSuccess(<BleedingEpisode>[]);

  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String userId,
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

Future<void> _pump(WidgetTester tester, List<Map<String, Object?>> logs) async {
  final logsJson = jsonEncode(logs);
  await ParityTestHarness.pump(
    tester,
    arabic: false,
    extraPrefs: {
      'niswah_cycle_tracking_logs': logsJson,
      'flutter.niswah_cycle_tracking_logs': logsJson,
    },
    homeOverride: DashboardScreen(
      canonicalRepositoryOverride: _EmptyCanonicalRepository(),
      canonicalUserIdOverride: 'user-1',
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .toList();

void main() {
  testWidgets(
    'a period 18 days late (30-day cycles, last start Jul 1, today Aug 18) '
    'must not be told "Pre-Period in 1 days"',
    (tester) async {
      await _pump(tester, [
        _log('1', '2026-06-01', 'medium'),
        _log('2', '2026-06-05', 'none'),
        _log('3', '2026-07-01', 'medium'),
        _log('4', '2026-07-05', 'none'),
      ]);
      final texts = _texts(tester);
      expect(
        texts.where((t) => RegExp(r'Pre-Period in \d+ days').hasMatch(t)),
        isEmpty,
        reason:
            'cycle day 49 of a 30-day predicted cycle is 18 days late; the '
            'Insights screen says "Late by 18 days" for the same data, the '
            'dashboard must not promise the pre-period phase is 1 day away',
      );
      expect(texts, contains('Your period is 18 days late'));
      expect(
        texts,
        isNot(contains('of 22')),
        reason: 'no frozen "22 of 22" day count while she is late',
      );
    },
  );

  testWidgets(
    'on the expected day itself (28-day cycles, last start Jul 21) the '
    'pill agrees with the next-period line',
    (tester) async {
      await _pump(tester, [
        _log('1', '2026-06-23', 'medium'),
        _log('2', '2026-06-27', 'none'),
        _log('3', '2026-07-21', 'medium'),
        _log('4', '2026-07-25', 'none'),
      ]);
      final texts = _texts(tester);
      expect(texts, contains('Your period is expected today'));
      expect(
        texts.where((t) => RegExp(r'Pre-Period in \d+ days').hasMatch(t)),
        isEmpty,
      );
    },
  );

  testWidgets(
    'when the predictor refuses to predict (only interval is 141 days, '
    'outside the 90-day predictable range) the dashboard must not show a '
    'forward "<phase> in N days" countdown',
    (tester) async {
      await _pump(tester, [
        _log('1', '2026-03-01', 'medium'),
        _log('2', '2026-03-05', 'none'),
        _log('3', '2026-07-20', 'medium'),
        _log('4', '2026-07-24', 'none'),
      ]);
      final texts = _texts(tester);
      expect(
        texts.where(
          (t) => RegExp(
            r'^(Pre-Period|Expected Period|Fertile|Tahara|Haid) in \d+ days$',
          ).hasMatch(t),
        ),
        isEmpty,
        reason:
            'summary.canPredict is false (no next period, no fertile window '
            'anywhere else in the app) yet the ring lays the cycle out on '
            'the raw 141-day average and counts down to a phase',
      );
    },
  );
}
