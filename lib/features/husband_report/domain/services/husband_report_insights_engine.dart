import 'package:equatable/equatable.dart';

import '../../../cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/domain/services/cycle_segment_planner.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../../fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import '../../../pregnancy_profile/domain/entities/pregnancy_profile.dart';

/// Everything "تقرير الزوج" needs — reuses [FiqhReportInsightsEngine]'s
/// already-tested fiqh-state/nifas classification rather than re-deriving
/// it, so the husband report can never disagree with the fiqh report or
/// the dashboard about which state is current. Adds only what a husband
/// specifically needs beyond that: the next expected period date and the
/// fertile window. Deliberately nothing else — no symptoms, flow color, or
/// notes; that content belongs to the wife's private medical reports
/// ([FiqhReportInsights], the doctor's report), never a husband-facing one.
class HusbandReportInsights extends Equatable {
  const HusbandReportInsights({
    required this.displayName,
    required this.fiqh,
    required this.nextPeriodDate,
    required this.fertileWindowStart,
    required this.fertileWindowEnd,
    this.fertilePeakDay,
    this.segmentPlan,
  });

  final String displayName;
  final FiqhReportInsights fiqh;

  /// Predicted start of the next period — null until two Haid starts have
  /// been logged, same gate as [FiqhReportInsights.hasEnoughForAverages].
  final DateTime? nextPeriodDate;
  final DateTime? fertileWindowStart;
  final DateTime? fertileWindowEnd;

  /// Estimated ovulation day (single most fertile day) — the midpoint the
  /// fertile window is built around.
  final DateTime? fertilePeakDay;

  /// The same haid/tahara/fertile/pre-period/expected breakdown the
  /// dashboard's cycle ring uses, reused here (not recomputed) so the
  /// husband report's fertility timeline can never disagree with the app's
  /// own view of the cycle. Null when there isn't enough history to build
  /// one, same gate as the fertile window itself.
  final CycleSegmentPlan? segmentPlan;

  @override
  List<Object?> get props => [
    displayName,
    fiqh,
    nextPeriodDate,
    fertileWindowStart,
    fertileWindowEnd,
    fertilePeakDay,
    segmentPlan,
  ];
}

class HusbandReportInsightsEngine {
  const HusbandReportInsightsEngine._();

  static HusbandReportInsights analyze({
    required List<CycleLog> cycleLogs,
    required Madhhab? madhhab,
    required String displayName,
    PregnancyProfile? pregnancyProfile,
    required DateTime now,
  }) {
    final fiqh = FiqhReportInsightsEngine.analyze(
      cycleLogs: cycleLogs,
      madhhab: madhhab,
      pregnancyProfile: pregnancyProfile,
      now: now,
    );

    DateTime? nextPeriodDate;
    DateTime? fertileStart;
    DateTime? fertileEnd;
    DateTime? fertilePeakDay;
    CycleSegmentPlan? segmentPlan;
    if (fiqh.mode == FiqhReportMode.cycle) {
      final summary = const CycleTrackingController().summarizeHistory(
        cycleLogs,
        now: now,
      );
      nextPeriodDate = summary.nextPeriodStart;
      fertileStart = summary.fertileWindow.start;
      fertileEnd = summary.fertileWindow.end;
      fertilePeakDay = summary.fertileWindow.peakDay;

      final cycleStart = summary.lastCycleStart;
      final cycleLength = summary.averageCycleLength;
      final periodLength = summary.averagePeriodLength;
      // Fiqh Remediation Wave 1 (Section E): `isBleedingNow` below is
      // fiqh-derived (`FiqhCycleState.haid`) — if the madhhab is
      // UNSET/UNKNOWN, that comparison would silently read as "not
      // bleeding" even while bleeding is actually occurring (false
      // precision, exactly what this wave forbids). The segment plan is
      // simply not computed in that case, mirroring the existing
      // `hasPlausibleAverage` "not enough to show yet" pattern, rather
      // than asserting an unresolvable bleeding state.
      if (cycleStart != null &&
          cycleLength != null &&
          periodLength != null &&
          summary.hasPlausibleAverage &&
          fiqh.cycleState != FiqhCycleState.madhhabUnresolved) {
        final cycleDayEstimate = now.difference(cycleStart).inDays + 1;
        segmentPlan = const CycleSegmentPlanner().plan(
          cycleLength: cycleLength,
          periodLength: periodLength,
          fertileWindow: summary.fertileWindow,
          cycleStart: cycleStart,
          isBleedingNow: fiqh.cycleState == FiqhCycleState.haid,
          cycleDayEstimate: cycleDayEstimate,
        );
      }
    }

    return HusbandReportInsights(
      displayName: displayName,
      fiqh: fiqh,
      nextPeriodDate: nextPeriodDate,
      fertileWindowStart: fertileStart,
      fertileWindowEnd: fertileEnd,
      fertilePeakDay: fertilePeakDay,
      segmentPlan: segmentPlan,
    );
  }
}
