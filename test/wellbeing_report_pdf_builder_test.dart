import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';
import 'package:niswah/features/wellbeing/domain/services/wellbeing_insights_engine.dart';
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

  test('renders the full report with charts, sleep pattern, and escalation', () async {
    final logs = [
      for (var i = 0; i < 5; i++) _log(i + 1, mood: 2, sleep: 1),
      for (var i = 5; i < 12; i++) _log(i + 1, mood: 4, sleep: 4),
    ];
    final previous = List.generate(
      6,
      (i) => _log(i + 1, month: 7, mood: 3),
    );

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
  });

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
}
