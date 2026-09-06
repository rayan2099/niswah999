import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/doctor_report/domain/entities/report_completeness.dart';
import 'package:niswah/features/doctor_report/domain/entities/report_source_status.dart';

void main() {
  group('computeReportCompleteness (PJ-006)', () {
    test(
      'every source available/empty with real data → complete',
      () {
        final result = computeReportCompleteness(
          cycleStatus: ReportSourceStatus.available,
          pregnancyStatus: ReportSourceStatus.unavailable,
          wellbeingStatus: ReportSourceStatus.available,
          flagsStatus: ReportSourceStatus.empty,
          hasAnyMeaningfulData: true,
        );

        expect(result, ReportCompleteness.complete);
      },
    );

    test(
      'the required source (cycle) failing → loadFailure, regardless of '
      'other sources',
      () {
        final result = computeReportCompleteness(
          cycleStatus: ReportSourceStatus.failed,
          pregnancyStatus: ReportSourceStatus.available,
          wellbeingStatus: ReportSourceStatus.available,
          flagsStatus: ReportSourceStatus.available,
          hasAnyMeaningfulData: true,
        );

        expect(result, ReportCompleteness.loadFailure);
      },
    );

    test(
      'an optional source (pregnancy) failing while cycle succeeds → '
      'partial, not loadFailure',
      () {
        final result = computeReportCompleteness(
          cycleStatus: ReportSourceStatus.available,
          pregnancyStatus: ReportSourceStatus.failed,
          wellbeingStatus: ReportSourceStatus.available,
          flagsStatus: ReportSourceStatus.available,
          hasAnyMeaningfulData: true,
        );

        expect(result, ReportCompleteness.partial);
      },
    );

    test('wellbeing failing alone → partial', () {
      final result = computeReportCompleteness(
        cycleStatus: ReportSourceStatus.available,
        pregnancyStatus: ReportSourceStatus.unavailable,
        wellbeingStatus: ReportSourceStatus.failed,
        flagsStatus: ReportSourceStatus.empty,
        hasAnyMeaningfulData: true,
      );

      expect(result, ReportCompleteness.partial);
    });

    test(
      'the flagged-conversations source failing alone → partial — this is '
      'the exact PJ-006 path, now distinguishable from a genuine empty '
      'result',
      () {
        final result = computeReportCompleteness(
          cycleStatus: ReportSourceStatus.available,
          pregnancyStatus: ReportSourceStatus.unavailable,
          wellbeingStatus: ReportSourceStatus.empty,
          flagsStatus: ReportSourceStatus.failed,
          hasAnyMeaningfulData: true,
        );

        expect(result, ReportCompleteness.partial);
      },
    );

    test(
      'everything resolves successfully but there is genuinely no data '
      'anywhere → insufficient, not complete — a brand-new account must '
      'not be told its (nonexistent) report is complete',
      () {
        final result = computeReportCompleteness(
          cycleStatus: ReportSourceStatus.empty,
          pregnancyStatus: ReportSourceStatus.unavailable,
          wellbeingStatus: ReportSourceStatus.empty,
          flagsStatus: ReportSourceStatus.empty,
          hasAnyMeaningfulData: false,
        );

        expect(result, ReportCompleteness.insufficient);
      },
    );

    test(
      'multiple optional sources failing at once is still partial, not '
      'escalated to loadFailure',
      () {
        final result = computeReportCompleteness(
          cycleStatus: ReportSourceStatus.available,
          pregnancyStatus: ReportSourceStatus.failed,
          wellbeingStatus: ReportSourceStatus.failed,
          flagsStatus: ReportSourceStatus.failed,
          hasAnyMeaningfulData: true,
        );

        expect(result, ReportCompleteness.partial);
      },
    );

    test(
      'cycle failing takes priority over insufficient-data classification '
      'even when nothing else has data either',
      () {
        final result = computeReportCompleteness(
          cycleStatus: ReportSourceStatus.failed,
          pregnancyStatus: ReportSourceStatus.unavailable,
          wellbeingStatus: ReportSourceStatus.empty,
          flagsStatus: ReportSourceStatus.empty,
          hasAnyMeaningfulData: false,
        );

        expect(result, ReportCompleteness.loadFailure);
      },
    );
  });
}
