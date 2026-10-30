import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';
import 'package:niswah/features/wellbeing/domain/services/wellbeing_insights_engine.dart';
import 'package:niswah/features/wellbeing/domain/services/wellbeing_period_split.dart';
import 'package:niswah/features/wellbeing/domain/services/wellbeing_trend.dart';
import 'package:niswah/features/wellbeing/presentation/pdf/wellbeing_report_pdf_builder.dart';

WellbeingLog _log(
  int day, {
  required int mood,
  int month = 8,
  int energy = 3,
  int sleep = 3,
}) {
  return WellbeingLog(
    id: 'log-$month-$day',
    userId: 'user-1',
    logDate: DateTime(2026, month, day),
    mood: mood,
    energy: energy,
    sleep: sleep,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders the sparse-data (building your picture) state', () async {
    final insights = WellbeingInsightsEngine.analyze(
      currentPeriodLogs: [_log(1, mood: 3), _log(2, mood: 4)],
      previousPeriodLogs: const [],
      daysElapsedInPeriod: 3,
    );

    final bytesAr = await WellbeingReportPdfBuilder.build(
      isArabic: true,
      insights: insights,
      periodStart: DateTime(2026, 8, 1),
      generatedAt: DateTime(2026, 8, 25),
    );
    final bytesEn = await WellbeingReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      periodStart: DateTime(2026, 8, 1),
      generatedAt: DateTime(2026, 8, 25),
    );

    expect(bytesAr.isNotEmpty, isTrue);
    expect(bytesEn.isNotEmpty, isTrue);
  });

  test(
    'renders the full report with charts, sleep pattern, and escalation',
    () async {
      final logs = [
        for (var i = 0; i < 5; i++) _log(i + 1, mood: 2, sleep: 1),
        for (var i = 5; i < 12; i++) _log(i + 1, mood: 4, sleep: 4),
      ];
      final previous = List.generate(6, (i) => _log(i + 1, month: 7, mood: 3));

      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: previous,
        daysElapsedInPeriod: 12,
      );

      final bytes = await WellbeingReportPdfBuilder.build(
        isArabic: true,
        insights: insights,
        periodStart: DateTime(2026, 8, 1),
        generatedAt: DateTime(2026, 8, 25),
      );

      expect(bytes.isNotEmpty, isTrue);
    },
  );

  test('renders the escalation card when mood is sustained-low', () async {
    final logs = List.generate(10, (i) => _log(i + 1, mood: 1));
    final insights = WellbeingInsightsEngine.analyze(
      currentPeriodLogs: logs,
      previousPeriodLogs: const [],
      daysElapsedInPeriod: 10,
    );

    expect(insights.escalationRecommended, isTrue);

    final bytes = await WellbeingReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      periodStart: DateTime(2026, 8, 1),
      generatedAt: DateTime(2026, 8, 25),
    );

    expect(bytes.isNotEmpty, isTrue);
  });

  test('renders the notes section when notes are provided', () async {
    final insights = WellbeingInsightsEngine.analyze(
      currentPeriodLogs: [_log(1, mood: 3), _log(2, mood: 4)],
      previousPeriodLogs: const [],
      daysElapsedInPeriod: 3,
    );

    final bytes = await WellbeingReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      periodStart: DateTime(2026, 8, 1),
      generatedAt: DateTime(2026, 8, 25),
      notes: [
        NotedEntry(date: DateTime(2026, 8, 2), text: 'felt anxious today'),
      ],
    );

    expect(bytes.isNotEmpty, isTrue);
  });

  test('renders the period / no-period split note in both languages', () async {
    final logs = List.generate(6, (i) => _log(i + 1, mood: 3));
    final insights = WellbeingInsightsEngine.analyze(
      currentPeriodLogs: logs,
      previousPeriodLogs: const [],
      daysElapsedInPeriod: 12,
    );
    final split = WellbeingPeriodSplit.compute(
      logs: logs,
      today: DateTime(2026, 8, 25),
    );
    for (final isArabic in [true, false]) {
      final bytes = await WellbeingReportPdfBuilder.build(
        isArabic: isArabic,
        insights: insights,
        periodStart: DateTime(2026, 8, 1),
        generatedAt: DateTime(2026, 8, 25),
        periodSplit: split,
      );
      expect(bytes.isNotEmpty, isTrue);
    }
  });

  test('the split table matches the Insights views', () {
    final logs = [_log(1, mood: 4), _log(2, mood: 2)];
    final split = WellbeingPeriodSplit.compute(
      logs: logs,
      today: DateTime(2026, 8, 25),
    );
    final rows = WellbeingReportPdfBuilder.periodSplitRows(true, split);
    expect(rows.first, ['', 'كل الأيام', 'أيام الدورة', 'بقية الأيام']);
    expect(rows[1], ['المزاج', '3.0/5', '—', '3.0/5']);
    expect(rows.last, ['التسجيلات', '2', '0', '2']);
  });

  test('includes the weekly trend from the Insights card', () async {
    // Synthetic: two June weeks, a gap, then August.
    final logs = [
      _log(3, month: 6, mood: 2, energy: 3, sleep: 4),
      _log(4, month: 6, mood: 4, energy: 3, sleep: 2),
      _log(9, month: 6, mood: 3, energy: 2, sleep: 3),
      _log(10, month: 8, mood: 5, energy: 4, sleep: 3),
      _log(17, month: 8, mood: 3, energy: 3, sleep: 3),
      _log(18, month: 8, mood: 4, energy: 4, sleep: 4),
    ];
    final august = logs.where((log) => log.logDate.month == 8).toList();
    final insights = WellbeingInsightsEngine.analyze(
      currentPeriodLogs: august,
      previousPeriodLogs: const [],
      daysElapsedInPeriod: 18,
    );
    final trend = WellbeingTrend.compute(
      logs: logs,
      from: DateTime(2026, 6, 1),
      today: DateTime(2026, 8, 18),
      months: 3,
    );
    expect(trend.bucketsWithData, 4);
    for (final isArabic in [true, false]) {
      final bytes = await WellbeingReportPdfBuilder.build(
        isArabic: isArabic,
        insights: insights,
        periodStart: DateTime(2026, 8, 1),
        generatedAt: DateTime(2026, 8, 18),
        periodSplit: WellbeingPeriodSplit.compute(
          logs: august,
          today: DateTime(2026, 8, 18),
        ),
        trend: trend,
      );
      expect(bytes.isNotEmpty, isTrue);
      // Set PDF_OUT to look at the page.
      final out = Platform.environment['PDF_OUT'];
      if (out != null && out.isNotEmpty) {
        await File('$out/wellbeing_trend_${isArabic ? 'ar' : 'en'}.pdf')
            .writeAsBytes(bytes);
      }
    }
  });
}
