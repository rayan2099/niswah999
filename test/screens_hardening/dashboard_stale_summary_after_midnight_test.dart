import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import '../support/parity_test_harness.dart';

/// Screens hardening — the dashboard re-reads the clock every minute (the fiqh
/// refresh timer) and the cycle DAY follows it, but the CycleTrackingSummary
/// (next-period range, late status, fertile window) is computed only inside
/// loadLogs(). Nothing reloads it when the date changes (app resume only
/// reloads when a pending sync actually synced). After the app sits in
/// memory across days, Today shows a "next period" range that is already
/// in the past next to a cycle day that has moved on.
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

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.trim().isNotEmpty)
    .toList();

void main() {
  testWidgets('next-period line follows the clock like the cycle day does', (
    tester,
  ) async {
    final logsJson = jsonEncode([
      _log('1', '2026-06-23', 'medium'),
      _log('2', '2026-06-27', 'none'),
      _log('3', '2026-07-21', 'medium'),
      _log('4', '2026-07-25', 'none'),
    ]);
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

    // The app stays in memory; 12 days pass. The minute timer rebuilds.
    AppClock.now = () => DateTime(2026, 8, 30, 12);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    final after = _texts(tester);

    expect(
      after.where((t) => t.startsWith('Next period likely')),
      isEmpty,
      reason:
          'on Aug 30 she is 12 days past the expected Aug 18 start (past the '
          'late tolerance) — a fresh summary has no next-period range, but '
          'the stale one still offers the old range',
    );
  });
}
