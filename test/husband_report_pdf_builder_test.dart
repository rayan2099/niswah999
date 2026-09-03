import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import 'package:niswah/features/husband_report/domain/services/husband_report_insights_engine.dart';
import 'package:niswah/features/husband_report/presentation/pdf/husband_report_pdf_builder.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

CycleLog _log(int day, {required FlowLevel flow, int cycleDay = 1}) {
  return CycleLog(
    id: 'log-$day',
    userId: 'user-1',
    date: DateTime(2026, 1, day),
    flow: flow,
    cycleDay: cycleDay,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders the sparse-history state without throwing', () async {
    final insights = HusbandReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanbali,
      displayName: 'أم محمد',
      now: DateTime(2026, 1, 20),
    );

    final bytesAr = await HusbandReportPdfBuilder.build(
      isArabic: true,
      insights: insights,
      generatedAt: DateTime(2026, 1, 20),
    );
    final bytesEn = await HusbandReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      generatedAt: DateTime(2026, 1, 20),
    );

    expect(bytesAr.isNotEmpty, isTrue);
    expect(bytesEn.isNotEmpty, isTrue);
  });

  test(
    'renders the full report with next-period and fertility-window stat '
    'tiles without throwing — this is the exact layout that crashed with '
    '"Widget won\'t fit into the page... height (Infinity)"',
    () async {
      final logs = [
        _log(1, flow: FlowLevel.medium, cycleDay: 1),
        _log(4, flow: FlowLevel.none, cycleDay: 4),
        _log(29, flow: FlowLevel.medium, cycleDay: 1),
        _log(32, flow: FlowLevel.none, cycleDay: 4),
      ];

      final insights = HusbandReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        displayName: 'أم محمد',
        now: DateTime(2026, 2, 1),
      );

      expect(insights.nextPeriodDate, isNotNull);
      expect(insights.fertileWindowStart, isNotNull);

      final bytesAr = await HusbandReportPdfBuilder.build(
        isArabic: true,
        insights: insights,
        generatedAt: DateTime(2026, 2, 1),
      );
      final bytesEn = await HusbandReportPdfBuilder.build(
        isArabic: false,
        insights: insights,
        generatedAt: DateTime(2026, 2, 1),
      );

      expect(bytesAr.isNotEmpty, isTrue);
      expect(bytesEn.isNotEmpty, isTrue);
    },
  );

  test('renders the overdue (rolled-forward) prediction without throwing', () async {
    final logs = [
      _log(1, flow: FlowLevel.medium, cycleDay: 1),
      _log(4, flow: FlowLevel.none, cycleDay: 4),
      _log(29, flow: FlowLevel.medium, cycleDay: 1),
      _log(32, flow: FlowLevel.none, cycleDay: 4),
    ];

    final insights = HusbandReportInsightsEngine.analyze(
      cycleLogs: logs,
      madhhab: Madhhab.hanbali,
      displayName: 'أم محمد',
      now: DateTime(2026, 3, 1),
    );

    final bytes = await HusbandReportPdfBuilder.build(
      isArabic: true,
      insights: insights,
      generatedAt: DateTime(2026, 3, 1),
    );

    expect(bytes.isNotEmpty, isTrue);
  });

  test('renders the nifas state without throwing', () async {
    final profile = PregnancyProfile(
      id: 'p1',
      userId: 'user-1',
      isPostpartum: true,
      postpartumStartDate: DateTime(2026, 1, 1),
    );
    final logs = [_log(15, flow: FlowLevel.medium, cycleDay: 1)];

    final insights = HusbandReportInsightsEngine.analyze(
      cycleLogs: logs,
      madhhab: Madhhab.hanbali,
      displayName: 'أم محمد',
      pregnancyProfile: profile,
      now: DateTime(2026, 1, 20),
    );

    expect(insights.fiqh.mode, FiqhReportMode.nifas);

    final bytesAr = await HusbandReportPdfBuilder.build(
      isArabic: true,
      insights: insights,
      generatedAt: DateTime(2026, 1, 20),
    );
    final bytesEn = await HusbandReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      generatedAt: DateTime(2026, 1, 20),
    );

    expect(bytesAr.isNotEmpty, isTrue);
    expect(bytesEn.isNotEmpty, isTrue);
  });
}
