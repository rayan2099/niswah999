import '../entities/cycle_log.dart';
import '../../../../core/utils/calendar_day.dart';
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

    if (logs.isEmpty) {
      return baseline(state: FiqhCycleState.insufficientHistory);
    }
    if (logs.any((log) => log.date.isAfter(now))) {
      return baseline(state: FiqhCycleState.insufficientHistory);
    }
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
    }
    // Deliberately no longer also breaking on `log.cycleDay == 1`: that
    // field defaults to 1 (CycleLog's own constructor default) and is
    // never set at all by CanonicalFiqhEvidenceAdapter.buildEffectiveLogs,
    // which builds every canonical-evidence-derived log this engine now
    // receives. With that check still present, the scan broke on the very
    // first (latest) entry for ANY canonical-backed episode, pinning
    // activeStart to "today" regardless of the episode's true start date
    // — bleedingDuration then collapsed to just the current day's own
    // elapsed hours, which is below every madhhab's minimum, so a
    // genuinely-open, well-within-bounds Haid episode always misclassified
    // as needsAdvisory. `flow == FlowLevel.none` is the correct, sole
    // authoritative boundary signal (an explicit "not bleeding"
    // observation) — found and fixed via parity_today_lower_test.dart.

    final bleedingDuration = now.difference(activeStart);
    final calendarDays = calendarDayDifference(now, activeStart) + 1;
    final daysIntoCurrentEpisode = calendarDays > 0 ? calendarDays : 1;

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
      return baseline(
        state: result.state,
        // A factual day count is safe even when a ruling is unavailable.
        daysIntoCurrentEpisode: daysIntoCurrentEpisode,
      );
    }

    // result.minimumHaid is null for Maliki (FD-7, 2026-10-15: no
    // time-based minimum) — needsAdvisory can then only be reached via
    // the maximum bound, for which there is no future "will become
    // confirmed Haid" date to show (she already would have been, from
    // the very start, were a minimum to apply at all).
    final minimumHaid = result.minimumHaid;
    final confirmAt = minimumHaid == null || !result.minimumOnlyPending
        ? null
        : activeStart.add(minimumHaid);
    return baseline(
      state: FiqhCycleState.needsAdvisory,
      confirmAt: confirmAt != null && confirmAt.isAfter(now) ? confirmAt : null,
      daysIntoCurrentEpisode: daysIntoCurrentEpisode,
    );
  }
}
