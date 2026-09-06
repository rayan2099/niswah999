import 'package:equatable/equatable.dart';

import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../../fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import '../../../pregnancy_profile/domain/entities/pregnancy_profile.dart';
import '../../../wellbeing/domain/entities/wellbeing_log.dart';
import '../../../wellbeing/domain/services/wellbeing_insights_engine.dart';
import '../entities/flagged_conversation.dart';
import '../entities/report_completeness.dart';
import '../entities/report_source_status.dart';
import '../../../cycle_tracking/domain/services/cycle_symptom_decoder.dart';

/// Everything the comprehensive Doctor's Report needs. A thin composition
/// of three already-tested engines — [FiqhReportInsightsEngine] (cycle/
/// pregnancy/nifas), [WellbeingInsightsEngine] (mood/sleep), and
/// [CycleSymptomDecoder] (symptom history) — plus recent flagged chat
/// concerns. No new classification rules are introduced here.
class DoctorReportInsights extends Equatable {
  const DoctorReportInsights({
    required this.cycleAndPregnancy,
    required this.wellbeing,
    required this.topSymptoms,
    required this.recentNotes,
    required this.recentBloodColors,
    required this.recentFlags,
    this.highRiskFlags = const [],
    this.completeness = ReportCompleteness.complete,
    this.cycleStatus = ReportSourceStatus.available,
    this.pregnancyStatus = ReportSourceStatus.unavailable,
    this.wellbeingStatus = ReportSourceStatus.available,
    this.flagsStatus = ReportSourceStatus.available,
  });

  final FiqhReportInsights cycleAndPregnancy;
  final WellbeingInsights wellbeing;
  final List<SymptomAggregate> topSymptoms;
  final List<NotedEntry> recentNotes;

  /// Recent blood/discharge color entries — preset (red/dark/brown/pink)
  /// or the free-text description entered when "Other" was selected.
  final List<NotedEntry> recentBloodColors;
  final List<FlaggedConversation> recentFlags;

  /// Sourced directly from [PregnancyProfile.highRiskFlags] — carried
  /// separately from [cycleAndPregnancy] because [FiqhReportInsights]
  /// doesn't forward this field (it's not needed for fiqh classification,
  /// but it's exactly what a doctor's report should surface).
  final List<String> highRiskFlags;

  /// Report-level completeness state (PJ-006) — must travel with this
  /// object everywhere it goes, including into the PDF, so a partial or
  /// load-failed report can never be silently presented as complete.
  final ReportCompleteness completeness;
  final ReportSourceStatus cycleStatus;
  final ReportSourceStatus pregnancyStatus;
  final ReportSourceStatus wellbeingStatus;
  final ReportSourceStatus flagsStatus;

  @override
  List<Object?> get props => [
    cycleAndPregnancy,
    wellbeing,
    topSymptoms,
    recentNotes,
    recentBloodColors,
    recentFlags,
    highRiskFlags,
    completeness,
    cycleStatus,
    pregnancyStatus,
    wellbeingStatus,
    flagsStatus,
  ];
}

class DoctorReportInsightsEngine {
  const DoctorReportInsightsEngine._();

  static DoctorReportInsights analyze({
    required List<CycleLog> cycleLogs,
    required Madhhab madhhab,
    PregnancyProfile? pregnancyProfile,
    required List<WellbeingLog> currentWellbeingLogs,
    required List<WellbeingLog> previousWellbeingLogs,
    required List<FlaggedConversation> recentFlags,
    required DateTime now,
    ReportSourceStatus cycleStatus = ReportSourceStatus.available,
    ReportSourceStatus pregnancyStatus = ReportSourceStatus.unavailable,
    ReportSourceStatus wellbeingStatus = ReportSourceStatus.available,
    ReportSourceStatus flagsStatus = ReportSourceStatus.available,
  }) {
    final cycleAndPregnancy = FiqhReportInsightsEngine.analyze(
      cycleLogs: cycleLogs,
      madhhab: madhhab,
      pregnancyProfile: pregnancyProfile,
      now: now,
    );

    final wellbeing = WellbeingInsightsEngine.analyze(
      currentPeriodLogs: currentWellbeingLogs,
      previousPeriodLogs: previousWellbeingLogs,
      daysElapsedInPeriod: now.day,
    );

    final topSymptoms = CycleSymptomDecoder.aggregateSymptoms(cycleLogs);
    final recentNotes = CycleSymptomDecoder.recentNotes(cycleLogs);
    final recentBloodColors = CycleSymptomDecoder.recentBloodColors(
      cycleLogs,
    );

    final hasAnyMeaningfulData =
        cycleLogs.isNotEmpty ||
        pregnancyProfile != null ||
        currentWellbeingLogs.isNotEmpty ||
        previousWellbeingLogs.isNotEmpty ||
        recentFlags.isNotEmpty;

    final completeness = computeReportCompleteness(
      cycleStatus: cycleStatus,
      pregnancyStatus: pregnancyStatus,
      wellbeingStatus: wellbeingStatus,
      flagsStatus: flagsStatus,
      hasAnyMeaningfulData: hasAnyMeaningfulData,
    );

    return DoctorReportInsights(
      cycleAndPregnancy: cycleAndPregnancy,
      wellbeing: wellbeing,
      topSymptoms: topSymptoms,
      recentNotes: recentNotes,
      recentBloodColors: recentBloodColors,
      recentFlags: recentFlags,
      highRiskFlags: pregnancyProfile?.highRiskFlags ?? const [],
      completeness: completeness,
      cycleStatus: cycleStatus,
      pregnancyStatus: pregnancyStatus,
      wellbeingStatus: wellbeingStatus,
      flagsStatus: flagsStatus,
    );
  }
}
