import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import 'package:niswah/features/fiqh_report/presentation/pdf/fiqh_report_pdf_builder.dart';

import 'support/pdf_text.dart';

/// The acceptance suite reads generated reports with test/support/pdf_text.dart.
/// Prove the reader itself is faithful: a report built from KNOWN logs must
/// yield exactly the figures those logs imply, and a different madhhab / state
/// must change the text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CycleLog log(int day, FlowLevel flow) => CycleLog(
    id: 'l$day',
    userId: 'u',
    date: DateTime(2026, 1, day),
    flow: flow,
    cycleDay: 1,
  );

  test('extracts the report title, madhhab and computed figures', () async {
    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: [
        log(1, FlowLevel.medium),
        log(2, FlowLevel.medium),
        log(3, FlowLevel.none),
        log(29, FlowLevel.medium),
        log(30, FlowLevel.medium),
        log(31, FlowLevel.none),
      ],
      madhhab: Madhhab.hanafi,
      now: DateTime(2026, 2, 5),
    );
    final text = PdfText.parse(
      await FiqhReportPdfBuilder.build(
        isArabic: false,
        insights: insights,
        generatedAt: DateTime(2026, 2, 5),
      ),
    );
    expect(text.pageCount, 1);
    expect(text.contains('Fiqh Report'), isTrue);
    expect(text.contains('Selected madhhab: Hanafi'), isTrue);
    expect(text.contains('Current state: Tahara'), isTrue);
    expect(text.contains('28 days'), isTrue); // 1 Jan -> 29 Jan
    expect(text.contains('Episodes logged'), isTrue);
    expect(text.contains('Maliki'), isFalse);
  });

  test(
    'sparse history is reported honestly, and the madhhab changes the text',
    () async {
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanbali,
        now: DateTime(2026, 2, 5),
      );
      final text = PdfText.parse(
        await FiqhReportPdfBuilder.build(
          isArabic: false,
          insights: insights,
          generatedAt: DateTime(2026, 2, 5),
        ),
      );
      expect(text.contains('Hanbali'), isTrue);
      expect(text.contains('Hanafi'), isFalse);
      expect(text.contains('28 days'), isFalse);
    },
  );

  test(
    'Arabic output contains Arabic letters and no English report title',
    () async {
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.shafii,
        now: DateTime(2026, 2, 5),
      );
      final text = PdfText.parse(
        await FiqhReportPdfBuilder.build(
          isArabic: true,
          insights: insights,
          generatedAt: DateTime(2026, 2, 5),
        ),
      );
      expect(RegExp(r'[؀-ۿﭐ-﻿]').hasMatch(text.all), isTrue);
      expect(text.contains('Fiqh Report'), isFalse);
    },
  );
}
