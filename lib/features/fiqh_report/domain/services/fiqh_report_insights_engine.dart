import 'package:equatable/equatable.dart';

import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../../../cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../../pregnancy_profile/domain/entities/pregnancy_profile.dart';
import '../../../pregnancy_profile/domain/services/pregnancy_status_engine.dart';

enum FiqhReportMode { nifas, cycle }

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
/// stats), and [MadhhabRuleEvaluator] (state classification) — into the
/// fiqh report's insights. No new fiqh-classification rules are introduced
/// here; nifas priority and the current-state derivation mirror exactly
/// what the dashboard already computes (`_currentFiqhState` in
/// dashboard_screen.dart), just made public, pure, and testable.
class FiqhReportInsightsEngine {
  const FiqhReportInsightsEngine._();

  static const minHaidStartsForAverage = 2;

  /// [madhhab]: null whenever the caller's `MadhhabController.state` is
  /// not `selected` — see Fiqh Remediation Wave 1, Section E. The nifas
  /// branch below still runs (postpartum status doesn't depend on
  /// madhhab); the cycle branch returns
  /// [FiqhCycleState.madhhabUnresolved] via [_currentCycleState] instead
  /// of guessing.
  static FiqhReportInsights analyze({
    required List<CycleLog> cycleLogs,
    required Madhhab? madhhab,
    PregnancyProfile? pregnancyProfile,
    required DateTime now,
  }) {
    final pregnancyStatus = PregnancyStatusEngine.getStatus(
      pregnancyProfile,
      now,
    );
    if (pregnancyStatus.mode == PregnancyMode.postpartum) {
      return FiqhReportInsights.nifas(
        madhhab: madhhab,
        daysPostpartum: pregnancyStatus.daysPostpartum!,
        phase: pregnancyStatus.phase!,
        notes: CycleSymptomDecoder.recentNotes(cycleLogs),
      );
    }

    final sorted = [...cycleLogs]..sort((a, b) => a.date.compareTo(b.date));
    final calculation = const CycleCalculationService().calculate(
      sorted,
      asOf: now,
    );

    final episodes = _haidEpisodes(sorted);
    final averageHaidDuration = episodes.isEmpty
        ? null
        : (episodes.map((e) => e.durationDays).reduce((a, b) => a + b) /
                  episodes.length)
              .round();

    return FiqhReportInsights.cycle(
      madhhab: madhhab,
      cycleState: _currentCycleState(
        sortedLogs: sorted,
        madhhab: madhhab,
        hasSufficientHistory: calculation.hasSufficientHistory,
        now: now,
      ),
      hasEnoughForAverages:
          calculation.haidStarts.length >= minHaidStartsForAverage,
      averageCycleLengthDays: calculation.averageCycleLength,
      averageHaidDurationDays: averageHaidDuration,
      haidEpisodeCount: episodes.length,
      totalEntriesLogged: cycleLogs.length,
      lastHaidStart: calculation.lastHaidStart,
      haidDurationsDays: episodes.map((e) => e.durationDays).toList(),
      notes: CycleSymptomDecoder.recentNotes(cycleLogs),
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

  static FiqhCycleState _currentCycleState({
    required List<CycleLog> sortedLogs,
    required Madhhab? madhhab,
    required bool hasSufficientHistory,
    required DateTime now,
  }) {
    if (sortedLogs.isEmpty) return FiqhCycleState.tahara;

    final latest = sortedLogs.last;
    if (latest.flow == FlowLevel.none) return FiqhCycleState.tahara;

    var activeStart = latest.date;
    DateTime? previousPurityStart;
    for (var index = sortedLogs.length - 1; index >= 0; index--) {
      final log = sortedLogs[index];
      if (log.flow == FlowLevel.none) {
        previousPurityStart = log.date;
        break;
      }
      activeStart = log.date;
      if (log.cycleDay == 1) break;
    }

    if (madhhab == null) {
      // Currently bleeding, but no madhhab is SELECTED — never guess one.
      return FiqhCycleState.madhhabUnresolved;
    }

    final result = const MadhhabRuleEvaluator().evaluate(
      madhhab: madhhab,
      hasSufficientHistory: hasSufficientHistory,
      isBleeding: true,
      bleedingDuration: now.difference(activeStart),
      purityBefore: previousPurityStart == null
          ? null
          : activeStart.difference(previousPurityStart),
    );
    return result.state;
  }
}
