import '../entities/cycle_log.dart';
import 'cycle_calculation_service.dart';
import 'madhhab_rule_evaluator.dart';

/// A single, shared computation of "where is the user right now" — the
/// authoritative source for every part of the dashboard's cycle ring and
/// phase stepper, so they can never disagree with each other the way they
/// used to when each widget derived its own numbers independently.
class CycleStatusSnapshot {
  const CycleStatusSnapshot({
    required this.state,
    required this.confirmAt,
    required this.daysIntoCurrentEpisode,
    required this.cycleDayEstimate,
    required this.averageCycleLength,
    required this.averagePeriodLength,
  });

  /// The real, flow-aware fiqh state — derived from the most recent log's
  /// actual `flow` value, never from a statistical prediction.
  final FiqhCycleState state;

  /// Set only while [state] is `needsAdvisory` for the "not enough time
  /// has passed yet" reason — the moment bleeding duration will reach the
  /// selected madhhab's minimum for haid.
  final DateTime? confirmAt;

  /// Real elapsed days into the current bleeding episode, grounded in the
  /// actual logged start date. Null when not currently bleeding. This is
  /// what the stepper's Haid node must use for a "day X of Y" progress
  /// format — never the flow-blind [cycleDayEstimate].
  final int? daysIntoCurrentEpisode;

  /// Pure elapsed days since the last recorded period *start*, blind to
  /// whether bleeding has since stopped. Legitimate only for forward-
  /// looking predictions (e.g. "days until next expected period") — never
  /// for describing the current episode's progress.
  final int? cycleDayEstimate;

  final int? averageCycleLength;

  /// Null whenever no complete start+end pair has ever been observed —
  /// never fabricated to a placeholder like the old hardcoded "5".
  final int? averagePeriodLength;
}

/// Pure engine composing [CycleCalculationService] (statistical timing)
/// with [MadhhabRuleEvaluator] (fiqh classification) into one snapshot, so
/// every UI surface reads the same numbers instead of two independently
/// derived views that can drift out of sync.
class CycleStatusEngine {
  const CycleStatusEngine();

  /// [madhhab]: null whenever the caller's `MadhhabController.state` is not
  /// `selected` (i.e. UNSET or UNKNOWN) — see Fiqh Remediation Wave 1,
  /// Section E. A null madhhab never blocks a `tahara` (not currently
  /// bleeding) determination, since that holds regardless of madhhab, but
  /// gates every classification that would otherwise require one:
  /// [FiqhCycleState.madhhabUnresolved] is returned instead of guessing.
  CycleStatusSnapshot evaluate({
    required List<CycleLog> logs,
    required CycleCalculationResult calculation,
    required Madhhab? madhhab,
    required DateTime now,
  }) {
    CycleStatusSnapshot baseline({
      FiqhCycleState state = FiqhCycleState.tahara,
      DateTime? confirmAt,
      int? daysIntoCurrentEpisode,
    }) => CycleStatusSnapshot(
      state: state,
      confirmAt: confirmAt,
      daysIntoCurrentEpisode: daysIntoCurrentEpisode,
      cycleDayEstimate: calculation.currentCycleDay,
      averageCycleLength: calculation.averageCycleLength,
      averagePeriodLength: calculation.averagePeriodLength,
    );

    if (logs.isEmpty) return baseline();
    final sorted = [...logs]..sort((a, b) => a.date.compareTo(b.date));
    final latest = sorted.last;
    if (latest.flow == FlowLevel.none) return baseline();

    var activeStart = latest.date;
    DateTime? previousPurityStart;
    for (var index = sorted.length - 1; index >= 0; index--) {
      final log = sorted[index];
      if (log.flow == FlowLevel.none) {
        previousPurityStart = log.date;
        break;
      }
      activeStart = log.date;
      if (log.cycleDay == 1) break;
    }

    final bleedingDuration = now.difference(activeStart);
    final daysIntoCurrentEpisode = bleedingDuration.inDays + 1 > 0
        ? bleedingDuration.inDays + 1
        : 1;

    if (madhhab == null) {
      // Currently bleeding, but no madhhab is SELECTED — never guess one.
      return baseline(
        state: FiqhCycleState.madhhabUnresolved,
        daysIntoCurrentEpisode: daysIntoCurrentEpisode,
      );
    }

    final result = const MadhhabRuleEvaluator().evaluate(
      madhhab: madhhab,
      hasSufficientHistory: calculation.hasSufficientHistory,
      isBleeding: true,
      bleedingDuration: bleedingDuration,
      purityBefore: previousPurityStart == null
          ? null
          : activeStart.difference(previousPurityStart),
    );

    if (result.state != FiqhCycleState.needsAdvisory) {
      final mappedState = result.state == FiqhCycleState.insufficientHistory
          ? FiqhCycleState.tahara
          : result.state;
      // Only haid/needsAdvisory ever mean "currently bleeding" for display
      // purposes — if the fiqh evaluator falls back to insufficientHistory
      // (mapped to tahara) despite the latest log technically being
      // bleeding, daysIntoCurrentEpisode must not leak through, or state
      // and daysIntoCurrentEpisode would disagree the same way this whole
      // fix exists to prevent.
      return baseline(
        state: mappedState,
        daysIntoCurrentEpisode: mappedState == FiqhCycleState.haid
            ? daysIntoCurrentEpisode
            : null,
      );
    }

    final confirmAt = activeStart.add(result.minimumHaid);
    return baseline(
      state: FiqhCycleState.needsAdvisory,
      confirmAt: confirmAt.isAfter(now) ? confirmAt : null,
      daysIntoCurrentEpisode: daysIntoCurrentEpisode,
    );
  }
}
