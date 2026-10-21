import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart';
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';

import '../support/parity_test_harness.dart';

/// Screens hardening — "next period" countdown must agree across screens for the
/// same logs. AppClock is pinned to 2026-08-18 12:00.
///
/// Two regular 28-day cycles: starts Jul 1 and Jul 29. Next period is
/// expected Aug 26 => 8 days from Aug 18 (cycle day 21).
Map<String, Object?> _log(String id, String date, String flow) => {
  'id': id,
  'user_id': 'local-user',
  'date': '${date}T08:00:00.000',
  'flow': flow,
  'cycle_day': 1,
  'sync_status': 'synced',
};

final _logs = [
  _log('1', '2026-06-03', 'medium'),
  _log('2', '2026-06-07', 'none'),
  _log('3', '2026-07-01', 'medium'),
  _log('4', '2026-07-05', 'none'),
  _log('5', '2026-07-29', 'medium'),
  _log('6', '2026-08-02', 'none'),
];

Future<List<String>> _textsOf(WidgetTester tester, Widget screen) async {
  final logsJson = jsonEncode(_logs);
  await ParityTestHarness.pump(
    tester,
    arabic: false,
    size: const Size(390, 3000),
    extraPrefs: {
      'niswah_cycle_tracking_logs': logsJson,
      'flutter.niswah_cycle_tracking_logs': logsJson,
    },
    homeOverride: screen,
  );
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .where((s) => s.trim().isNotEmpty)
      .toList();
}

void main() {
  testWidgets('Insights says next period in about 8 days', (tester) async {
    final texts = await _textsOf(tester, const InsightsScreen());
    expect(texts, contains('In about 8 days'));
  });

  testWidgets('Calendar month summary NEXT PERIOD must also say 8 days left', (
    tester,
  ) async {
    final texts = await _textsOf(tester, const CycleTrackingScreen());
    final i = texts.indexOf('NEXT PERIOD');
    expect(texts.sublist(i + 1, i + 3), ['8', 'days left']);
  });
}
