import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/doctor_report/domain/entities/flagged_conversation.dart';
import 'package:niswah/features/doctor_report/domain/entities/report_completeness.dart';
import 'package:niswah/features/doctor_report/domain/entities/report_source_status.dart';
import 'package:niswah/features/doctor_report/domain/services/doctor_report_insights_engine.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';

CycleLog _cycleLog(
  int day, {
  required FlowLevel flow,
  int cycleDay = 1,
  List<String> symptoms = const [],
  String? notes,
}) {
  return CycleLog(
    id: 'cycle-$day',
    userId: 'user-1',
    date: DateTime(2026, 1, day),
    flow: flow,
    cycleDay: cycleDay,
    symptoms: symptoms,
    notes: notes,
  );
}

WellbeingLog _wellbeingLog(int day, {required int mood, int month = 1}) {
  return WellbeingLog(
    id: 'wb-$month-$day',
    userId: 'user-1',
    logDate: DateTime(2026, month, day),
    mood: mood,
    energy: 3,
    sleep: 3,
  );
}

void main() {
  group('DoctorReportInsightsEngine.analyze', () {
    test('composes cycle/pregnancy, wellbeing, and symptom sections independently', () {
      final insights = DoctorReportInsightsEngine.analyze(
        cycleLogs: [
          _cycleLog(1, flow: FlowLevel.medium, cycleDay: 1, symptoms: ['Cramps:2']),
          _cycleLog(2, flow: FlowLevel.none, cycleDay: 2),
        ],
        madhhab: Madhhab.hanbali,
        currentWellbeingLogs: [_wellbeingLog(1, mood: 4)],
        previousWellbeingLogs: const [],
        recentFlags: const [],
        now: DateTime(2026, 1, 10),
      );

      expect(insights.cycleAndPregnancy.mode, FiqhReportMode.cycle);
      expect(insights.wellbeing.currentCount, 1);
      expect(insights.topSymptoms.single.name, 'Cramps');
    });

    test('recent notes flow through from cycle logs', () {
      final insights = DoctorReportInsightsEngine.analyze(
        cycleLogs: [
          _cycleLog(1, flow: FlowLevel.medium, notes: 'felt dizzy, took Panadol'),
          _cycleLog(2, flow: FlowLevel.none),
        ],
        madhhab: Madhhab.hanbali,
        currentWellbeingLogs: const [],
        previousWellbeingLogs: const [],
        recentFlags: const [],
        now: DateTime(2026, 1, 10),
      );

      expect(insights.recentNotes.single.text, 'felt dizzy, took Panadol');
      expect(insights.recentNotes.single.date, DateTime(2026, 1, 1));
    });

    test(
      'recent blood colors flow through, including a custom "Other" description',
      () {
        final insights = DoctorReportInsightsEngine.analyze(
          cycleLogs: [
            _cycleLog(
              1,
              flow: FlowLevel.medium,
              symptoms: ['color:أحمر داكن مع خيوط بنية'],
            ),
            _cycleLog(2, flow: FlowLevel.none),
          ],
          madhhab: Madhhab.hanbali,
          currentWellbeingLogs: const [],
          previousWellbeingLogs: const [],
          recentFlags: const [],
          now: DateTime(2026, 1, 10),
        );

        expect(
          insights.recentBloodColors.single.text,
          'أحمر داكن مع خيوط بنية',
        );
        expect(insights.recentBloodColors.single.date, DateTime(2026, 1, 1));
      },
    );

    test('postpartum profile flows through to the cycle/pregnancy section as nifas', () {
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'user-1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 1, 1),
      );

      final insights = DoctorReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.shafii,
        pregnancyProfile: profile,
        currentWellbeingLogs: const [],
        previousWellbeingLogs: const [],
        recentFlags: const [],
        now: DateTime(2026, 1, 10),
      );

      expect(insights.cycleAndPregnancy.mode, FiqhReportMode.nifas);
    });

    test('recent flagged concerns pass through untouched', () {
      final flags = [
        FlaggedConversation(
          id: 'flag-1',
          threadId: 'thread-1',
          messageExcerpt: 'عندي نزيف الآن',
          matchedCategories: const ['bleeding'],
          createdAt: DateTime(2026, 1, 5),
        ),
      ];

      final insights = DoctorReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanbali,
        currentWellbeingLogs: const [],
        previousWellbeingLogs: const [],
        recentFlags: flags,
        now: DateTime(2026, 1, 10),
      );

      expect(insights.recentFlags, flags);
    });

    test('no data anywhere produces an empty-but-valid report', () {
      final insights = DoctorReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanbali,
        currentWellbeingLogs: const [],
        previousWellbeingLogs: const [],
        recentFlags: const [],
        now: DateTime(2026, 1, 10),
      );

      expect(insights.cycleAndPregnancy.mode, FiqhReportMode.cycle);
      expect(insights.cycleAndPregnancy.hasEnoughForAverages, isFalse);
      expect(insights.wellbeing.hasEnoughForCharts, isFalse);
      expect(insights.topSymptoms, isEmpty);
      expect(insights.recentNotes, isEmpty);
      expect(insights.recentFlags, isEmpty);
    });
  });

  group('DoctorReportInsightsEngine.analyze completeness (PJ-006)', () {
    test(
      'no data anywhere, but every source resolved successfully → '
      'insufficient, not complete',
      () {
        final insights = DoctorReportInsightsEngine.analyze(
          cycleLogs: const [],
          madhhab: Madhhab.hanbali,
          currentWellbeingLogs: const [],
          previousWellbeingLogs: const [],
          recentFlags: const [],
          now: DateTime(2026, 1, 10),
          cycleStatus: ReportSourceStatus.empty,
          wellbeingStatus: ReportSourceStatus.empty,
          flagsStatus: ReportSourceStatus.empty,
        );

        expect(insights.completeness, ReportCompleteness.insufficient);
      },
    );

    test('real cycle data with everything else resolved → complete', () {
      final insights = DoctorReportInsightsEngine.analyze(
        cycleLogs: [_cycleLog(1, flow: FlowLevel.medium)],
        madhhab: Madhhab.hanbali,
        currentWellbeingLogs: const [],
        previousWellbeingLogs: const [],
        recentFlags: const [],
        now: DateTime(2026, 1, 10),
        wellbeingStatus: ReportSourceStatus.empty,
        flagsStatus: ReportSourceStatus.empty,
      );

      expect(insights.completeness, ReportCompleteness.complete);
    });

    test(
      'the flagged-conversations source failing to load produces a '
      'partial report, carrying the failure status through to the '
      'rendered insights — the exact PJ-006 architectural gap, now '
      'distinguishable end-to-end from a genuinely empty result',
      () {
        final insights = DoctorReportInsightsEngine.analyze(
          cycleLogs: [_cycleLog(1, flow: FlowLevel.medium)],
          madhhab: Madhhab.hanbali,
          currentWellbeingLogs: const [],
          previousWellbeingLogs: const [],
          recentFlags: const [],
          now: DateTime(2026, 1, 10),
          wellbeingStatus: ReportSourceStatus.empty,
          flagsStatus: ReportSourceStatus.failed,
        );

        expect(insights.completeness, ReportCompleteness.partial);
        expect(insights.flagsStatus, ReportSourceStatus.failed);
        expect(
          insights.recentFlags,
          isEmpty,
          reason: 'the data itself is still an empty list (a safe '
              'fallback) — completeness/status is what actually carries '
              'the "this failed" signal, not a fabricated non-empty value',
        );
      },
    );

    test(
      'cycle logs failing to load produces loadFailure even when other '
      'sources are fine',
      () {
        final insights = DoctorReportInsightsEngine.analyze(
          cycleLogs: const [],
          madhhab: Madhhab.hanbali,
          currentWellbeingLogs: const [],
          previousWellbeingLogs: const [],
          recentFlags: const [],
          now: DateTime(2026, 1, 10),
          cycleStatus: ReportSourceStatus.failed,
          wellbeingStatus: ReportSourceStatus.empty,
          flagsStatus: ReportSourceStatus.empty,
        );

        expect(insights.completeness, ReportCompleteness.loadFailure);
      },
    );
  });
}
