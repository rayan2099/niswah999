import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/domain/services/report_canonical_evidence.dart';
import 'package:niswah/features/doctor_report/domain/services/doctor_report_insights_engine.dart';
import 'package:niswah/features/doctor_report/presentation/pdf/doctor_report_pdf_builder.dart';
import 'package:niswah/features/fiqh_report/presentation/pdf/fiqh_report_pdf_builder.dart';

import '../support/pdf_text.dart';

/// Screens hardening — a returning user whose history came from onboarding (canonical
/// episodes whose observations are flow "uncertain", so they never become
/// effective logs). The episodes give two haid starts (hasEnoughForAverages)
/// but no logged haid episode to average, so averageHaidDurationDays is null.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'doctor and fiqh reports never print "null days" for bleeding duration',
    () async {
      final now = DateTime(2026, 8, 18, 12);
      final insights = DoctorReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanbali,
        currentWellbeingLogs: const [],
        previousWellbeingLogs: const [],
        recentFlags: const [],
        now: now,
        canonical: ReportCanonicalEvidence(
          effectiveLogs: const [],
          episodes: [
            CanonicalEpisodeTiming(
              startDate: DateTime(2026, 6, 20),
              endDate: DateTime(2026, 6, 26),
            ),
            CanonicalEpisodeTiming(
              startDate: DateTime(2026, 7, 18),
              endDate: DateTime(2026, 7, 24),
            ),
          ],
          hasOpenEpisode: false,
          evidenceUnresolved: false,
        ),
      );
      final c = insights.cycleAndPregnancy;

      for (final arabic in [false, true]) {
        final text = PdfText.parse(
          await DoctorReportPdfBuilder.build(
            isArabic: arabic,
            insights: insights,
            generatedAt: now,
          ),
        );
        expect(
          text.squashed.contains('null'),
          isFalse,
          reason: 'arabic=$arabic: a missing average must not print as "null"',
        );
        final fiqhText = PdfText.parse(
          await FiqhReportPdfBuilder.build(
            isArabic: arabic,
            insights: c,
            generatedAt: now,
          ),
        );
        expect(
          fiqhText.squashed.contains('null'),
          isFalse,
          reason: 'fiqh report, arabic=$arabic',
        );
      }
    },
  );
}
