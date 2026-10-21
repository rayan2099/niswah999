import 'package:equatable/equatable.dart';

import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/domain/services/canonical_fiqh_assessment.dart';
import '../../../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../../../cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../../cycle_tracking/domain/services/report_canonical_evidence.dart';
import '../../../pregnancy_profile/domain/entities/pregnancy_profile.dart';
import '../../../pregnancy_profile/domain/services/pregnancy_status_engine.dart';

enum FiqhReportMode { nifas, cycle }

/// Why a report cannot state a definite current state even though the woman
/// may be bleeding right now — printed as an honest explanation, never
/// replaced by a confident "Tahara".
enum ReportEvidenceNote {
  none,

  /// An episode is open but its evidence has a material gap ("I'm not sure"
  /// days, a quarantined row): a ruling would be unsupported.
  openEpisodeUnresolved,

  /// The canonical records could not be read at all.
  recordsUnavailable,

  /// No episode is open, but the evidence still could not be verified (a
  /// quarantined row, or a logged bleeding day after the latest episode's
  /// stop date) — the same "Unable to verify" Today shows.
  evidenceUnverified,
}

/// Everything the fiqh report PDF needs — pre-computed and gated so the
/// report never fabricates an average from too little history.
class FiqhReportInsights extends Equatable {
  const FiqhReportInsights.nifas({
    required this.madhhab,
    required this.daysPostpartum,
    required String phase,
    this.notes = const [],
  }) : mode = FiqhReportMode.nifas,
       nifasPhase = phase,
       cycleState = null,
       hasEnoughForAverages = false,
       averageCycleLengthDays = null,
       averageHaidDurationDays = null,
       haidEpisodeCount = 0,
       totalEntriesLogged = 0,
       lastHaidStart = null,
       evidenceNote = ReportEvidenceNote.none,
       pregnancy = null,
       haidDurationsDays = const [];

  const FiqhReportInsights.cycle({
    required this.madhhab,
    required this.cycleState,
    required this.hasEnoughForAverages,
    required this.averageCycleLengthDays,
    required this.averageHaidDurationDays,
    required this.haidEpisodeCount,
    required this.totalEntriesLogged,
    required this.lastHaidStart,
    this.haidDurationsDays = const [],
    this.notes = const [],
    this.evidenceNote = ReportEvidenceNote.none,
    this.pregnancy,
  }) : mode = FiqhReportMode.cycle,
       daysPostpartum = null,
       nifasPhase = null;

  final FiqhReportMode mode;

  /// Null whenever the caller's `MadhhabController.state` is not
  /// `selected` (UNSET or UNKNOWN) — Fiqh Remediation Wave 1. The report
  /// screen/PDF builder must render an explicit "select your Madhhab
  /// first" state rather than assume one.
  final Madhhab? madhhab;

  // Nifas fields (mode == nifas)
  final int? daysPostpartum;
  final String? nifasPhase;

  // Cycle fields (mode == cycle)
  final FiqhCycleState? cycleState;

  /// Mirrors the report's existing "Two Haid starts are required to
  /// calculate a personal average" microcopy — a sparse-data user sees an
  /// honest "not enough history yet" state, never a fabricated average.
  final bool hasEnoughForAverages;
  final int? averageCycleLengthDays;
  final int? averageHaidDurationDays;
  final int haidEpisodeCount;
  final int totalEntriesLogged;
  final DateTime? lastHaidStart;

  /// Duration in days of each logged haid episode, oldest first — real
  /// history for a small chart, not a fabricated distribution.
  final List<int> haidDurationsDays;

  /// Recent non-empty notes across the same logs, newest first.
  final List<NotedEntry> notes;

  /// See [ReportEvidenceNote].
  final ReportEvidenceNote evidenceNote;

  /// Non-null while pregnancy tracking is active (mode == pregnant) — the
  /// reports state it instead of silently ignoring it (found live: a 12-week
  /// pregnant woman's Doctor report had no pregnancy content at all).
  final PregnancyStatus? pregnancy;

  @override
  List<Object?> get props => [
    mode,
    madhhab,
    daysPostpartum,
    nifasPhase,
    cycleState,
    hasEnoughForAverages,
    averageCycleLengthDays,
    averageHaidDurationDays,
    haidEpisodeCount,
    totalEntriesLogged,
    lastHaidStart,
    haidDurationsDays,
    notes,
    evidenceNote,
    pregnancy,
  ];
}

class _HaidEpisode {
  const _HaidEpisode({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
  int get durationDays => end.difference(start).inDays + 1;
}

/// Composes three existing, already-tested pieces of domain logic —
/// [PregnancyStatusEngine] (nifas), [CycleCalculationService] (cycle
/// stats), and [CanonicalFiqhAssessment] (state classification, the same
/// one the dashboard uses) — into the fiqh report's insights. No new
/// fiqh-classification rules are introduced here.
class FiqhReportInsightsEngine {
  const FiqhReportInsightsEngine._();

  static const minHaidStartsForAverage = 2;

  /// [madhhab]: null whenever the caller's `MadhhabController.state` is
  /// not `selected` — see Fiqh Remediation Wave 1, Section E. The nifas
  /// branch below still runs (postpartum status doesn't depend on
  /// madhhab); the cycle branch returns
  /// [FiqhCycleState.madhhabUnresolved] (via [CanonicalFiqhAssessment])
  /// instead of guessing.
  static FiqhReportInsights analyze({
    required List<CycleLog> cycleLogs,
    required Madhhab? madhhab,
    PregnancyProfile? pregnancyProfile,
    required DateTime now,

    /// The canonical evidence Today rules on. When supplied, the current
    /// state and the cycle statistics come from it; [cycleLogs] (the legacy
    /// table) then only supplies notes/symptoms. When null (no signed-in
    /// user / legacy callers) the previous legacy-only behaviour applies.
    ReportCanonicalEvidence? canonical,
  }) {
    final pregnancyStatus = PregnancyStatusEngine.getStatus(
      pregnancyProfile,
      now,
    );
    // Pregnancy/nifas hardening (2026-10-21, proposed): the nifas branch
    // applies only INSIDE the engine's nifas phase. Before, any postpartum
    // profile — 200 days after birth, cycles long back — kept every report
    // on "Current state: Nifas" forever and never computed her real
    // Haid/Tahara state again. After the phase, fall through to the cycle
    // branch. (The window itself is the engine's, unchanged; it is an open
    // owner decision.)
    if (pregnancyStatus.mode == PregnancyMode.postpartum &&
        pregnancyStatus.phase == PregnancyStatusEngine.nifasPhase) {
      return FiqhReportInsights.nifas(
        madhhab: madhhab,
        daysPostpartum: pregnancyStatus.daysPostpartum!,
        phase: pregnancyStatus.phase!,
        notes: CycleSymptomDecoder.recentNotes(cycleLogs),
      );
    }

    if (canonical != null && canonical.unavailable) {
      return FiqhReportInsights.cycle(
        madhhab: madhhab,
        cycleState: FiqhCycleState.insufficientHistory,
        hasEnoughForAverages: false,
        averageCycleLengthDays: null,
        averageHaidDurationDays: null,
        haidEpisodeCount: 0,
        totalEntriesLogged: cycleLogs.length,
        lastHaidStart: null,
        notes: CycleSymptomDecoder.recentNotes(cycleLogs),
        evidenceNote: ReportEvidenceNote.recordsUnavailable,
        pregnancy: pregnancyStatus.mode == PregnancyMode.pregnant
            ? pregnancyStatus
            : null,
      );
    }

    // Evidence for the STATE and the statistics: canonical when available.
    final evidenceLogs = canonical?.effectiveLogs ?? cycleLogs;
    // Symptoms/notes-only legacy rows carry no flow fact
    // (CycleLog.recordsFlow); canonical logs always record one.
    final sorted = [...evidenceLogs.where((log) => log.recordsFlow)]
      ..sort((a, b) => a.date.compareTo(b.date));

    // Fiqh hardening (2026-10-18): the current state comes from the SAME
    // combination of canonical status and CycleStatusEngine the Today
    // dashboard uses (CanonicalFiqhAssessment) — no second copy of the
    // engine's scan lives here any more. Without canonical evidence
    // (legacy callers) "an episode is open" is read from the logs
    // themselves, as before.
    final assessment = CanonicalFiqhAssessment.assess(
      effectiveLogs: sorted,
      hasOpenEpisode:
          canonical?.hasOpenEpisode ??
          (sorted.isNotEmpty && sorted.last.flow != FlowLevel.none),
      evidenceUnresolved: canonical?.evidenceUnresolved ?? false,
      madhhab: madhhab,
      now: now,
      canonicalEpisodes: canonical?.episodes ?? const [],
    );
    final calculation = assessment.calculation;

    final episodes = _haidEpisodes(sorted);
    final averageHaidDuration = episodes.isEmpty
        ? null
        : (episodes.map((e) => e.durationDays).reduce((a, b) => a + b) /
                  episodes.length)
              .round();

    // Neither unverifiable evidence nor too little history while bleeding
    // is ever reported as Tahara (the same rule Today applies): the report
    // says "insufficient" and explains why.
    final cycleState = assessment.state ?? FiqhCycleState.insufficientHistory;
    final evidenceNote = canonical == null
        ? ReportEvidenceNote.none
        : switch (assessment.verdict) {
            CanonicalFiqhVerdict.evaluated => ReportEvidenceNote.none,
            CanonicalFiqhVerdict.insufficientHistory =>
              ReportEvidenceNote.openEpisodeUnresolved,
            CanonicalFiqhVerdict.evidenceUnresolved =>
              canonical.hasOpenEpisode
                  ? ReportEvidenceNote.openEpisodeUnresolved
                  : ReportEvidenceNote.evidenceUnverified,
          };

    return FiqhReportInsights.cycle(
      madhhab: madhhab,
      cycleState: cycleState,
      hasEnoughForAverages:
          calculation.haidStarts.length >= minHaidStartsForAverage,
      averageCycleLengthDays: calculation.averageCycleLength,
      averageHaidDurationDays: averageHaidDuration,
      haidEpisodeCount: episodes.length,
      totalEntriesLogged: cycleLogs.length,
      lastHaidStart: calculation.lastHaidStart,
      haidDurationsDays: episodes.map((e) => e.durationDays).toList(),
      notes: CycleSymptomDecoder.recentNotes(cycleLogs),
      // A bleeding episode that cannot be ruled on (unresolved evidence, or
      // simply too little history) is explained in the report, never left as
      // an unexplained label.
      evidenceNote: evidenceNote,
      pregnancy: pregnancyStatus.mode == PregnancyMode.pregnant
          ? pregnancyStatus
          : null,
    );
  }

  static List<_HaidEpisode> _haidEpisodes(List<CycleLog> sortedLogs) {
    final episodes = <_HaidEpisode>[];
    DateTime? episodeStart;
    DateTime? episodeEnd;

    for (final log in sortedLogs) {
      if (log.flow != FlowLevel.none) {
        episodeStart ??= log.date;
        episodeEnd = log.date;
      } else if (episodeStart != null && episodeEnd != null) {
        episodes.add(_HaidEpisode(start: episodeStart, end: episodeEnd));
        episodeStart = null;
        episodeEnd = null;
      }
    }
    if (episodeStart != null && episodeEnd != null) {
      episodes.add(_HaidEpisode(start: episodeStart, end: episodeEnd));
    }
    return episodes;
  }
}
