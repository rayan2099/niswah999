import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/husband_report/domain/services/husband_report_insights_engine.dart';
import 'package:niswah/features/husband_report/presentation/pdf/husband_report_pdf_builder.dart';

import '../support/pdf_text.dart';

CycleLog _log(int month, int day, FlowLevel flow) => CycleLog(
  id: 'log-$month-$day',
  userId: 'user-1',
  date: DateTime(2026, month, day),
  flow: flow,
  cycleDay: 1,
);

/// Screens hardening — the husband report's "Current State" card used to label the NEXT
/// period's START date as "Expected End" ("متى تنتهي الدورة المتوقع").
/// A husband reading `State: Haid / Expected End: <date ~4 weeks out>`
/// was told the current haid lasts until then.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Current State card never labels the next period start as the '
      'expected END', () async {
    final now = DateTime(2026, 3, 1, 12);
    final insights = HusbandReportInsightsEngine.analyze(
      cycleLogs: [
        _log(1, 3, FlowLevel.medium),
        _log(1, 7, FlowLevel.none),
        _log(1, 31, FlowLevel.medium),
        _log(2, 4, FlowLevel.none),
      ],
      madhhab: Madhhab.hanbali,
      displayName: 'Umm Muhammad',
      now: now,
    );
    expect(insights.nextPeriodDate, isNotNull);

    final text = PdfText.parse(
      await HusbandReportPdfBuilder.build(
        isArabic: false,
        insights: insights,
        generatedAt: now,
      ),
    );
    expect(
      text.contains('Expected End'),
      isFalse,
      reason:
          'the value printed after "Expected End" is nextPeriodDate (the '
          'START of the next period), not the end of anything',
    );
  });
}
