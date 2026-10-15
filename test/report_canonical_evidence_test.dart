import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_evidence_adapter.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_status_engine.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/domain/services/report_canonical_evidence.dart';
import 'package:niswah/features/doctor_report/domain/services/doctor_report_insights_engine.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import 'package:niswah/features/doctor_report/presentation/pdf/doctor_report_pdf_builder.dart';
import 'package:niswah/features/fiqh_report/presentation/pdf/fiqh_report_pdf_builder.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/husband_report/domain/services/husband_report_insights_engine.dart';

import 'support/pdf_text.dart';

/// D-011 (found live): with Hanafi selected and a bleeding episode recorded in
/// onboarding (open, flow "uncertain" -> never projected to the legacy table)
/// the Fiqh report said "Current state: Tahara" while Today said "Bleeding
/// recorded — Day 4". The reports must rule on the same canonical evidence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 26);

  ReportCanonicalEvidence openUncertain() => ReportCanonicalEvidence(
    effectiveLogs: const [], // uncertain days are (honestly) unrepresentable
    episodes: [CanonicalEpisodeTiming(startDate: DateTime(2026, 9, 22))],
    hasOpenEpisode: true,
    evidenceUnresolved: true,
  );

  test(
    'open episode with unresolved evidence is never reported as Tahara',
    () async {
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: const [], // the legacy table has nothing for it
        madhhab: Madhhab.hanafi,
        now: now,
        canonical: openUncertain(),
      );
      expect(insights.cycleState, FiqhCycleState.insufficientHistory);
      expect(insights.evidenceNote, ReportEvidenceNote.openEpisodeUnresolved);

      final text = PdfText.parse(
        await FiqhReportPdfBuilder.build(
          isArabic: false,
          insights: insights,
          generatedAt: now,
        ),
      );
      expect(text.contains('Current state: Insufficient history'), isTrue);
      expect(text.contains('Current state: Tahara'), isFalse);
      expect(text.contains('bleeding episode is recorded'), isTrue);
    },
  );

  test(
    'the legacy-only path is unchanged: no evidence at all stays Tahara',
    () {
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanafi,
        now: now,
      );
      expect(insights.cycleState, FiqhCycleState.tahara);
      expect(insights.evidenceNote, ReportEvidenceNote.none);
    },
  );

  test(
    'a certain open episode with enough history is ruled on its own evidence',
    () {
      CycleLog log(int month, int d, FlowLevel flow, int cycleDay) => CycleLog(
        id: 'c$month-$d',
        userId: 'u',
        date: DateTime(2026, month, d),
        flow: flow,
        cycleDay: cycleDay,
      );
      final logs = [
        for (var d = 1; d <= 5; d++) log(8, d, FlowLevel.medium, d),
        log(8, 6, FlowLevel.none, 6),
        for (var d = 29; d <= 31; d++) log(8, d, FlowLevel.medium, d - 28),
        log(9, 1, FlowLevel.medium, 4),
        log(9, 2, FlowLevel.none, 5),
        for (var d = 22; d <= 26; d++) log(9, d, FlowLevel.medium, d - 21),
      ];
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanafi,
        now: now,
        canonical: ReportCanonicalEvidence(
          effectiveLogs: logs,
          episodes: [CanonicalEpisodeTiming(startDate: DateTime(2026, 9, 22))],
          hasOpenEpisode: true,
          evidenceUnresolved: false,
        ),
      );
      expect(insights.cycleState, isNot(FiqhCycleState.tahara));
      expect(insights.cycleState, FiqhCycleState.haid);
      expect(insights.evidenceNote, ReportEvidenceNote.none);
    },
  );

  test(
    'an open episode with too little history is "insufficient", never Tahara',
    () {
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanafi,
        now: now,
        canonical: ReportCanonicalEvidence(
          effectiveLogs: [
            for (var d = 22; d <= 26; d++)
              CycleLog(
                id: 'c$d',
                userId: 'u',
                date: DateTime(2026, 9, d),
                flow: FlowLevel.medium,
                cycleDay: d - 21,
              ),
          ],
          episodes: [CanonicalEpisodeTiming(startDate: DateTime(2026, 9, 22))],
          hasOpenEpisode: true,
          evidenceUnresolved: false,
        ),
      );
      expect(insights.cycleState, FiqhCycleState.insufficientHistory);
      expect(insights.evidenceNote, ReportEvidenceNote.openEpisodeUnresolved);
    },
  );

  test('canonical episodes count toward the averages (legacy table empty)', () {
    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanafi,
      now: now,
      canonical: ReportCanonicalEvidence(
        effectiveLogs: const [],
        episodes: [
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 8, 1),
            endDate: DateTime(2026, 8, 6),
          ),
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 8, 29),
            endDate: DateTime(2026, 9, 3),
          ),
        ],
        hasOpenEpisode: false,
        evidenceUnresolved: false,
      ),
    );
    expect(insights.hasEnoughForAverages, isTrue);
    expect(insights.averageCycleLengthDays, 28);
    expect(insights.cycleState, FiqhCycleState.tahara);
  });

  test(
    'an unreadable canonical source is "cannot verify", never Tahara',
    () async {
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanafi,
        now: now,
        canonical: const ReportCanonicalEvidence(
          effectiveLogs: [],
          episodes: [],
          hasOpenEpisode: false,
          evidenceUnresolved: true,
          unavailable: true,
        ),
      );
      expect(insights.cycleState, FiqhCycleState.insufficientHistory);
      expect(insights.evidenceNote, ReportEvidenceNote.recordsUnavailable);
      final text = PdfText.parse(
        await FiqhReportPdfBuilder.build(
          isArabic: false,
          insights: insights,
          generatedAt: now,
        ),
      );
      expect(text.contains("couldn't be verified"), isTrue);
      expect(text.contains('Current state: Tahara'), isFalse);
    },
  );

  test('the Husband and Doctor reports inherit the same state', () {
    final husband = HusbandReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanafi,
      displayName: 'X',
      now: now,
      canonical: openUncertain(),
    );
    expect(husband.fiqh.cycleState, FiqhCycleState.insufficientHistory);

    final doctor = DoctorReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanafi,
      currentWellbeingLogs: const [],
      previousWellbeingLogs: const [],
      recentFlags: const [],
      now: now,
      canonical: openUncertain(),
    );
    expect(
      doctor.cycleAndPregnancy.cycleState,
      FiqhCycleState.insufficientHistory,
    );
    // An open canonical episode is meaningful data even with an empty legacy table.
    expect(doctor.completeness.toString(), isNotEmpty);
  });

  test('a pregnant woman\'s Doctor and Fiqh reports state the pregnancy (found live: they did not)', () async {
    final profile = PregnancyProfile(
      id: 'p',
      userId: 'u',
      trackingBasis: TrackingBasis.manualWeek,
      manualWeekValue: 12,
      manualWeekSetAt: now,
    );
    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanafi,
      pregnancyProfile: profile,
      now: now,
    );
    expect(insights.pregnancy?.week, 12);

    final fiqh = PdfText.parse(
      await FiqhReportPdfBuilder.build(
        isArabic: false,
        insights: insights,
        generatedAt: now,
      ),
    );
    expect(
      fiqh.contains('Pregnancy tracking is active: week 12 (trimester 1)'),
      isTrue,
    );

    final doctorInsights = DoctorReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanafi,
      pregnancyProfile: profile,
      currentWellbeingLogs: const [],
      previousWellbeingLogs: const [],
      recentFlags: const [],
      now: now,
    );
    final doctor = PdfText.parse(
      await DoctorReportPdfBuilder.build(
        isArabic: false,
        insights: doctorInsights,
        generatedAt: now,
      ),
    );
    expect(doctor.contains('Pregnant'), isTrue);
    expect(
      doctor.contains(
        'Week 12 (trimester 1, month 3); about 28 weeks to the due date.',
      ),
      isTrue,
    );

    // Not pregnant: no pregnancy content.
    final none = PdfText.parse(
      await FiqhReportPdfBuilder.build(
        isArabic: false,
        insights: FiqhReportInsightsEngine.analyze(
          cycleLogs: const [],
          madhhab: Madhhab.hanafi,
          now: now,
        ),
        generatedAt: now,
      ),
    );
    expect(none.contains('Pregnancy tracking is active'), isFalse);
  });

  group(
    'Canonical-adapter cycleDay-default regression (fiqh_report_insights_'
    'engine.dart, blocker fix 2026-10-16)',
    () {
      // Builds the SAME production-faithful evidence CanonicalFiqhEvidence
      // Adapter.buildEffectiveLogs actually produces -- real
      // BleedingObservation rows through the real adapter, never a
      // hand-typed CycleLog with an explicit cycleDay. The adapter never
      // sets cycleDay (confirmed: zero occurrences of that identifier in
      // canonical_fiqh_evidence_adapter.dart), so every resulting CycleLog
      // keeps CycleLog's own constructor default of 1 -- exactly the
      // condition that broke `if (log.cycleDay == 1) break;` for every
      // canonical-backed open episode, in both the engine 01ef39e already
      // fixed and the second copy fixed here.
      List<CycleLog> openHanafiInBoundsEpisodeLogs({
        required DateTime now,
        required int daysOpen,
      }) {
        final observations = [
          for (var i = 0; i < daysOpen; i++)
            BleedingObservation(
              userId: 'u1',
              episodeId: 'e1',
              observedDate: now.subtract(Duration(days: daysOpen - 1 - i)),
              precision: ObservationPrecision.dateOnly,
              flow: ObservationFlow.medium,
              source: i == daysOpen - 1
                  ? ObservationSource.userObserved
                  : ObservationSource.userReportedHistorical,
              utcOffsetMinutes: 0,
            ),
        ];
        return CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
          observations: observations,
        );
      }

      final now = DateTime(2026, 10, 16, 12);
      const daysOpen = 7; // Hanafi: min 72h, max 240h -- 7 days is in bounds.
      final logs = openHanafiInBoundsEpisodeLogs(now: now, daysOpen: daysOpen);

      test(
        'sanity: the adapter really does leave every entry at the cycleDay '
        'default (1) -- otherwise this regression test would not be '
        'exercising the real defect at all',
        () {
          expect(logs, isNotEmpty);
          expect(logs.every((log) => log.cycleDay == 1), isTrue);
        },
      );

      test(
        'CycleStatusEngine.evaluate() (fixed in 01ef39e) correctly reports '
        'haid for a 7-day-old, in-bounds-for-Hanafi open episode built from '
        'real canonical evidence',
        () {
          final calculation = const CycleCalculationService().calculate(
            logs,
            asOf: now,
          );
          final snapshot = const CycleStatusEngine().evaluate(
            logs: logs,
            calculation: calculation,
            madhhab: Madhhab.hanafi,
            now: now,
          );
          expect(snapshot.state, FiqhCycleState.haid);
        },
      );

      ReportCanonicalEvidence canonicalEvidence() => ReportCanonicalEvidence(
        effectiveLogs: logs,
        episodes: [
          CanonicalEpisodeTiming(
            startDate: now.subtract(const Duration(days: daysOpen - 1)),
          ),
        ],
        hasOpenEpisode: true,
        evidenceUnresolved: false,
      );

      test(
        'FiqhReportInsightsEngine.analyze() must report the same haid state '
        'as CycleStatusEngine for the identical canonical evidence -- the '
        'actual blocker: before the fix this returned needsAdvisory because '
        "the scan's own cycleDay == 1 check broke on the very first "
        '(latest) entry',
        () {
          final insights = FiqhReportInsightsEngine.analyze(
            cycleLogs: const [],
            madhhab: Madhhab.hanafi,
            now: now,
            canonical: canonicalEvidence(),
          );
          expect(insights.cycleState, FiqhCycleState.haid);
        },
      );

      test(
        'propagates correctly to the Doctor Report, which wraps '
        "FiqhReportInsightsEngine's result directly",
        () {
          final insights = DoctorReportInsightsEngine.analyze(
            cycleLogs: const [],
            madhhab: Madhhab.hanafi,
            currentWellbeingLogs: const [],
            previousWellbeingLogs: const [],
            recentFlags: const [],
            now: now,
            canonical: canonicalEvidence(),
          );
          expect(insights.cycleAndPregnancy.cycleState, FiqhCycleState.haid);
        },
      );

      test(
        'propagates correctly to the Husband Report, whose own '
        'isBleedingNow derivation compares against this same cycleState',
        () {
          final insights = HusbandReportInsightsEngine.analyze(
            cycleLogs: const [],
            madhhab: Madhhab.hanafi,
            displayName: 'Test',
            now: now,
            canonical: canonicalEvidence(),
          );
          expect(insights.fiqh.cycleState, FiqhCycleState.haid);
        },
      );
    },
  );
}
