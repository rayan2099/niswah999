import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';
import 'package:niswah/features/wellbeing/domain/services/wellbeing_trend.dart';

import 'support/parity_test_harness.dart';

/// Testing feedback 2026-10-30: the mood card's "آخر 3 أشهر" was a label,
/// not a control, and the card had no picture of the data. The period is
/// now selectable and recomputes the averages and a chart from real
/// check-ins only. All data here is synthetic.
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

WellbeingLog _log(DateTime day, int mood, int energy, int sleep) =>
    WellbeingLog(
      id: 'w${day.toIso8601String()}',
      userId: 'local-user',
      logDate: day,
      mood: mood,
      energy: energy,
      sleep: sleep,
    );

// ParityTestHarness pins the clock to 2026-08-18. Three months is
// 2026-06-01..08-18; six months starts 2026-03-01.
final _logs = [
  _log(DateTime(2026, 4, 10), 1, 1, 1), // only in 6 and 12 months
  _log(DateTime(2026, 6, 3), 2, 3, 4),
  _log(DateTime(2026, 6, 4), 4, 3, 2),
  _log(DateTime(2026, 8, 10), 5, 4, 3),
  _log(DateTime(2026, 8, 17), 3, 3, 3),
];

Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('screenshot-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<List<DateTime>> _pump(
  WidgetTester tester, {
  bool arabic = false,
  List<WellbeingLog>? logs,
  double textScale = 1,
}) async {
  final requested = <DateTime>[];
  final vm = CycleTrackingViewModel(
    repository: _NoCycleRepository(),
    canonicalEpisodeLoader: (_) async => const [],
  );
  await ParityTestHarness.pump(
    tester,
    arabic: arabic,
    size: const Size(390, 4000),
    homeOverride: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 4000),
        textScaler: TextScaler.linear(textScale),
      ),
      child: RepaintBoundary(
        key: const Key('screenshot-root'),
        child: Directionality(
          textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: InsightsScreen(
              viewModel: vm,
              // Returns everything on purpose: the card itself must keep only
              // the selected period.
              loadWellbeingLogs: (from) async {
                requested.add(from);
                return logs ?? _logs;
              },
            ),
          ),
        ),
      ),
    ),
  );
  await vm.loadLogs();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('insights-wellbeing-range')));
  await tester.pumpAndSettle();
  return requested;
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('insights-wellbeing-range')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The mood card's quick-look line, "Average of N check-ins".
Finder _summary(String count) => find.text('Average of $count');

Future<void> _expand(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('wellbeing-details-toggle')));
  await tester.tap(find.byKey(const Key('wellbeing-details-toggle')));
  await tester.pumpAndSettle();
}

void main() {
  group('WellbeingTrend', () {
    test('weekly buckets with gaps, never filled in', () {
      final trend = WellbeingTrend.compute(
        logs: _logs,
        from: DateTime(2026, 6, 1),
        today: DateTime(2026, 8, 18),
        months: 3,
      );
      expect(trend.granularity, WellbeingTrendGranularity.week);
      expect(trend.buckets, hasLength(12)); // 79 days in 7-day blocks
      expect(trend.checkIns, 4, reason: 'April is outside the range');
      expect(trend.bucketsWithData, 3);
      final first = trend.buckets.first;
      expect(first.count, 2);
      expect(first.mood, 3.0);
      expect(first.sleep, 3.0);
      final empty = trend.buckets[1];
      expect(empty.count, 0);
      expect(empty.mood, isNull, reason: 'a gap, not a zero');
      expect(trend.buckets.last.end, DateTime(2026, 8, 18));
    });

    test('one bucket per calendar month, partial at the ends', () {
      final trend = WellbeingTrend.computeByMonth(
        logs: _logs,
        from: DateTime(2026, 6, 1),
        today: DateTime(2026, 8, 18),
        monthOf: (day) => day.year * 12 + day.month,
      );
      expect(trend.buckets, hasLength(3));
      expect(trend.buckets.first.mood, 3.0);
      expect(trend.buckets[1].count, 0);
      expect(trend.buckets[1].mood, isNull, reason: 'July: a gap, not zero');
      expect(trend.buckets.last.start, DateTime(2026, 8, 1));
      expect(trend.buckets.last.end, DateTime(2026, 8, 18));
      expect(trend.buckets.last.mood, 4.0);
    });

    test('twelve months group by calendar month', () {
      final trend = WellbeingTrend.compute(
        logs: _logs,
        from: DateTime(2025, 9, 1),
        today: DateTime(2026, 8, 18),
        months: 12,
      );
      expect(trend.granularity, WellbeingTrendGranularity.month);
      expect(trend.buckets, hasLength(12));
      expect(trend.checkIns, 5);
      expect(trend.buckets.last.count, 2);
      expect(trend.buckets.last.mood, 4.0);
    });
  });

  testWidgets('changing the period recomputes averages, chart and counts', (
    tester,
  ) async {
    final requested = await _pump(tester);
    await _expand(tester);
    expect(find.text('Last 3 months'), findsNWidgets(2));
    expect(_summary('4 check-ins'), findsOneWidget);
    expect(find.text('4 check-ins in 2 of 3 months'), findsOneWidget);
    expect(requested.last, DateTime(2026, 6, 1));
    expect(
      tester.getSize(find.byKey(const Key('insights-wellbeing-range'))).height,
      greaterThanOrEqualTo(44),
    );

    await _choose(tester, 'Last 6 months');
    expect(requested.last, DateTime(2026, 3, 1));
    expect(_summary('5 check-ins'), findsOneWidget);
    expect(find.text('5 check-ins in 3 of 6 months'), findsOneWidget);
    // The symptom card keeps its own period.
    expect(
      find.descendant(
        of: find.byKey(const Key('insights-trend-range')),
        matching: find.text('Last 3 months'),
      ),
      findsOneWidget,
    );

    await _choose(tester, 'Last month');
    expect(_summary('2 check-ins'), findsOneWidget);
    expect(find.text('2 check-ins in 1 of 1 month'), findsOneWidget);

    await _choose(tester, 'Last 12 months');
    expect(find.text('5 check-ins in 3 of 12 months'), findsOneWidget);
  });

  testWidgets('a period with no check-ins shows the empty state, no chart', (
    tester,
  ) async {
    await _pump(tester, logs: [_log(DateTime(2026, 4, 10), 3, 3, 3)]);
    expect(find.textContaining('No check-ins in this period'), findsOneWidget);
    expect(find.byKey(const Key('wellbeing-details-toggle')), findsNothing);

    await _choose(tester, 'Last 6 months');
    await _expand(tester);
    expect(find.byKey(const Key('wellbeing-trend-chart')), findsOneWidget);
    expect(find.textContaining('1 check-in in 1 of '), findsOneWidget);
  });

  testWidgets('screen readers get the numbers as text', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await _expand(tester);
    expect(
      tester
          .getSemantics(find.byKey(const Key('wellbeing-details-toggle')))
          .flagsCollection
          .isExpanded,
      ui.Tristate.isTrue,
    );
    final label = tester
        .getSemantics(find.byKey(const Key('wellbeing-trend-chart')))
        .label;
    expect(label, contains('Mood, monthly averages'));
    expect(label, contains('4 check-ins in 2 of 3 months'));
    expect(label, contains('Jun 3.0, Jul no check-ins, Aug 4.0'));
    // One measure at a time: the chips switch it.
    await tester.tap(find.byKey(const Key('wellbeing-measure-sleep')));
    await tester.pumpAndSettle();
    final sleep = tester
        .getSemantics(find.byKey(const Key('wellbeing-trend-chart')))
        .label;
    expect(sleep, contains('Sleep, monthly averages'));
    expect(sleep, contains('Jun 3.0, Jul no check-ins, Aug 3.0'));
    expect(find.bySemanticsLabel('Mood 3.5 out of 5'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('wellbeing-view-all')))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('insights-wellbeing-range')))
          .label,
      'Mood & wellbeing period: Last 3 months',
    );
    semantics.dispose();
  });

  testWidgets('Arabic, right to left, with large text', (tester) async {
    await _pump(tester, arabic: true, textScale: 1.6);
    await _capture(tester, 'after_wellbeing_collapsed_ar');
    await _expand(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('آخر 3 أشهر'), findsNWidgets(2));
    expect(find.text('4 تسجيلات في 2 من 3 أشهر'), findsOneWidget);
    expect(find.text('يوليو'), findsOneWidget);
    expect(find.text('متوسط 4 تسجيلات'), findsOneWidget);
    await _capture(tester, 'after_wellbeing_chart_ar');

    await tester.tap(find.byKey(const Key('insights-wellbeing-range')));
    await tester.pumpAndSettle();
    expect(find.text('آخر شهر'), findsOneWidget);
    expect(find.text('آخر 12 شهرًا'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
