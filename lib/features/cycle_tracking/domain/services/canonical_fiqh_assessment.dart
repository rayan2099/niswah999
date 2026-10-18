import '../entities/cycle_log.dart';
import 'cycle_calculation_service.dart';
import 'cycle_status_engine.dart';
import 'madhhab_rule_evaluator.dart';

/// Whether a Fiqh state may be presented from the evidence at all.
enum CanonicalFiqhVerdict {
  /// The engine's own state stands (see [CanonicalFiqhAssessment.snapshot]).
  /// That state may itself be a non-ruling (`needsAdvisory`,
  /// `madhhabUnresolved`), which every consumer must present as such.
  evaluated,

  /// The evidence cannot be verified: the canonical read failed, a row was
  /// quarantined, an "I'm not sure" day falls inside the open episode, or
  /// the effective observations contradict the canonical episode status
  /// (the latest effective day is bleeding although no episode is open).
  /// No ruling — positive or negative — may be shown.
  evidenceUnresolved,

  /// An episode is factually open, but fewer than two cycles are recorded,
  /// so nothing can be worked out yet. Never a confident Tahara.
  insufficientHistory,
}

/// The one combination of canonical episode status with
/// [CycleStatusEngine] that the Today dashboard, the Fiqh/Doctor/Husband
/// reports and the AI advisor's `clientFiqhState` all share (Fiqh
/// hardening, 2026-10-18). Before this existed each surface combined them
/// separately and they disagreed (the report ignored a quarantined row
/// without an open episode; the AI advisor read legacy `cycle_entries` and
/// told the model "tahara" for a woman bleeding for the first time).
class CanonicalFiqhAssessment {
  const CanonicalFiqhAssessment._({
    required this.verdict,
    required this.calculation,
    required this.snapshot,
  });

  final CanonicalFiqhVerdict verdict;
  final CycleCalculationResult calculation;

  /// Always computed (the ring's day counts read it), but its `state` is
  /// only a presentable conclusion when [verdict] is
  /// [CanonicalFiqhVerdict.evaluated] — use [state].
  final CycleStatusSnapshot snapshot;

  /// The engine's state when [verdict] is evaluated, otherwise null.
  FiqhCycleState? get state =>
      verdict == CanonicalFiqhVerdict.evaluated ? snapshot.state : null;

  /// [effectiveLogs]: `CanonicalFiqhEvidenceAdapter.buildEffectiveLogs`.
  /// [hasOpenEpisode]: from the canonical episode status; null when that
  /// read failed (never "no open episode").
  /// [evidenceUnresolved]: observations unreadable, quarantined rows, or a
  /// material "I'm not sure" gap (see `ReportCanonicalEvidence`).
  static CanonicalFiqhAssessment assess({
    required List<CycleLog> effectiveLogs,
    required bool? hasOpenEpisode,
    required bool evidenceUnresolved,
    required Madhhab? madhhab,
    required DateTime now,
    List<CanonicalEpisodeTiming> canonicalEpisodes = const [],
  }) {
    final calculation = const CycleCalculationService().calculate(
      effectiveLogs,
      asOf: now,
      canonicalEpisodes: canonicalEpisodes,
    );
    final snapshot = calculation.hasSufficientHistory
        ? const CycleStatusEngine().evaluate(
            logs: effectiveLogs,
            calculation: calculation,
            madhhab: madhhab,
            now: now,
          )
        : const CycleStatusSnapshot(
            state: FiqhCycleState.tahara,
            confirmAt: null,
            daysIntoCurrentEpisode: null,
            cycleDayEstimate: null,
            averageCycleLength: null,
            averagePeriodLength: null,
          );

    CanonicalFiqhAssessment result(CanonicalFiqhVerdict verdict) =>
        CanonicalFiqhAssessment._(
          verdict: verdict,
          calculation: calculation,
          snapshot: snapshot,
        );

    if (evidenceUnresolved || hasOpenEpisode == null) {
      return result(CanonicalFiqhVerdict.evidenceUnresolved);
    }
    if (hasOpenEpisode && !calculation.hasSufficientHistory) {
      return result(CanonicalFiqhVerdict.insufficientHistory);
    }
    // No open episode, yet the latest effective day is bleeding: an
    // episode was closed with a stop date before a later logged bleeding
    // day. The engine would keep saying "currently bleeding" (haid) from
    // those logs, while the factual record says nothing is open. Neither
    // reading can be confirmed, so no ruling is shown.
    final latestIsBleeding =
        effectiveLogs.isNotEmpty &&
        effectiveLogs.reduce((a, b) => b.date.isBefore(a.date) ? a : b).flow !=
            FlowLevel.none;
    if (!hasOpenEpisode && latestIsBleeding) {
      return result(CanonicalFiqhVerdict.evidenceUnresolved);
    }
    return result(CanonicalFiqhVerdict.evaluated);
  }
}
