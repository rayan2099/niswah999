import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import 'package:niswah/features/fiqh_report/presentation/pdf/fiqh_report_pdf_builder.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

CycleLog _log(
  int day, {
  required FlowLevel flow,
  int cycleDay = 1,
  String? notes,
}) {
  return CycleLog(
    id: 'log-$day',
    userId: 'user-1',
    date: DateTime(2026, 1, day),
    flow: flow,
    cycleDay: cycleDay,
    notes: notes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders the sparse-history (not enough for averages) state', () async {
    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanbali,
      now: DateTime(2026, 1, 20),
    );

    final bytesAr = await FiqhReportPdfBuilder.build(
      isArabic: true,
      insights: insights,
      generatedAt: DateTime(2026, 1, 20),
    );
    final bytesEn = await FiqhReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      generatedAt: DateTime(2026, 1, 20),
    );

    expect(bytesAr.isNotEmpty, isTrue);
    expect(bytesEn.isNotEmpty, isTrue);
  });

  test('renders the full report with averages and the episode chart', () async {
    final logs = [
      _log(1, flow: FlowLevel.medium, cycleDay: 1, notes: 'heavier than usual'),
      _log(2, flow: FlowLevel.medium, cycleDay: 2),
      _log(3, flow: FlowLevel.none, cycleDay: 3),
      _log(29, flow: FlowLevel.medium, cycleDay: 1),
      _log(30, flow: FlowLevel.medium, cycleDay: 2),
      _log(31, flow: FlowLevel.none, cycleDay: 3),
    ];

    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: logs,
      madhhab: Madhhab.hanbali,
      now: DateTime(2026, 2, 5),
    );

    expect(insights.hasEnoughForAverages, isTrue);
    expect(insights.notes, isNotEmpty);

    final bytes = await FiqhReportPdfBuilder.build(
      isArabic: true,
      insights: insights,
      generatedAt: DateTime(2026, 2, 5),
    );

    expect(bytes.isNotEmpty, isTrue);
  });

  test('renders the needsAdvisory card', () async {
    final logs = [
      _log(1, flow: FlowLevel.medium, cycleDay: 1),
      _log(2, flow: FlowLevel.none, cycleDay: 2),
      for (var day = 15; day <= 27; day++)
        _log(day, flow: FlowLevel.medium, cycleDay: day - 14),
    ];

    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: logs,
      madhhab: Madhhab.hanafi,
      now: DateTime(2026, 1, 27),
    );

    expect(insights.cycleState, FiqhCycleState.needsAdvisory);

    final bytes = await FiqhReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      generatedAt: DateTime(2026, 1, 27),
    );

    expect(bytes.isNotEmpty, isTrue);
  });

  test('renders the nifas state', () async {
    final profile = PregnancyProfile(
      id: 'p1',
      userId: 'user-1',
      isPostpartum: true,
      postpartumStartDate: DateTime(2026, 1, 1),
    );

    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.shafii,
      pregnancyProfile: profile,
      now: DateTime(2026, 1, 15),
    );

    expect(insights.mode, FiqhReportMode.nifas);

    final bytesAr = await FiqhReportPdfBuilder.build(
      isArabic: true,
      insights: insights,
      generatedAt: DateTime(2026, 1, 15),
    );
    final bytesEn = await FiqhReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      generatedAt: DateTime(2026, 1, 15),
    );

    expect(bytesAr.isNotEmpty, isTrue);
    expect(bytesEn.isNotEmpty, isTrue);
  });
}
