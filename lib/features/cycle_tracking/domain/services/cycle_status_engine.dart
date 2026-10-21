import '../../../../core/utils/calendar_days.dart';
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

    // Symptoms/notes-only rows carry no flow fact (see CycleLog.recordsFlow).
    final flowLogs = logs.where((log) => log.recordsFlow).toList();
    if (flowLogs.isEmpty) return baseline();
    final sorted = [...flowLogs]..sort((a, b) => a.date.compareTo(b.date));
    final latest = sorted.last;
    if (latest.flow == FlowLevel.none) return baseline();

    // Split the history into bleeding runs. `flow == FlowLevel.none` is
    // the sole authoritative boundary signal (an explicit "not bleeding"
    // observation) — deliberately no longer also breaking on
    // `log.cycleDay == 1` (found and fixed via parity_today_lower_test
    // .dart: that check once pinned every canonical episode's start to
    // "today"). A completed run ends on the date of the `none` log that
    // closed it; the current run is the trailing one (still open, since
    // the latest log is bleeding).
    final completedRuns = <_BleedingRun>[];
    CycleLog? runFirstLog;
    for (final log in sorted) {
      if (log.flow == FlowLevel.none) {
        if (runFirstLog != null) {
          completedRuns.add(_BleedingRun(runFirstLog, log.date));
          runFirstLog = null;
        }
      } else {
        runFirstLog ??= log;
      }
    }
    final currentRun = runFirstLog!;
    final activeStart = currentRun.date;

    // Fiqh hardening (2026-10-18), DST: calendar days, never
    // `Duration.inDays` between two local midnights (23h across a
    // spring-forward change, which made "day 2" read as "day 1").
    final daysElapsed = calendarDaysBetween(activeStart, now) + 1;
    final daysIntoCurrentEpisode = daysElapsed > 0 ? daysElapsed : 1;

    if (madhhab == null) {
      // Currently bleeding, but no madhhab is SELECTED — never guess one.
      return baseline(
        state: FiqhCycleState.madhhabUnresolved,
        daysIntoCurrentEpisode: daysIntoCurrentEpisode,
      );
    }

    final minimumHaid = MadhhabRuleEvaluator.minimumHaidFor(madhhab);
    final minimumPurity = MadhhabRuleEvaluator.minimumPurityFor(madhhab);

    // Fiqh hardening (2026-10-18): minimum purity (tuhr) is the interval
    // between two *menstrual* episodes (haidfigh.md §1 "between two
    // distinct menstrual cycles"), so it is measured from the end of the
    // last earlier run that could itself have been haid — never from a
    // run that was definitively too short to be haid under this madhhab
    // (e.g. Hanafi spotting under 72h). That earlier run's length is
    // taken at its most generous (from its start day's midnight, or its
    // exact start time, to the END of the day of its closing `none` log —
    // "it stopped on D" means bleeding may have lasted into D), so a run
    // is only skipped when it is certainly below the minimum; a run that
    // merely might have been haid still counts and keeps the purity
    // short (the conservative direction: needsAdvisory, never a
    // confident fresh haid). Cumulative talfiq across separate runs is
    // NOT modelled here (see docs: such cases fall to needsAdvisory).
    DateTime? stopDay;
    for (final run in completedRuns.reversed) {
      // Calendar days, never wall-clock hours between local midnights: a
      // 3-calendar-day run across a spring-forward change is 71h and was
      // wrongly skipped (round-2 property test R2-2). An exact start time
      // is subtracted only when one is known.
      final firstTime = run.first.observedTime;
      final runLength = firstTime == null
          ? Duration(days: calendarDaysBetween(run.first.date, run.end) + 1)
          : addCalendarDays(run.end, 1).difference(firstTime);
      if (minimumHaid == null || runLength >= minimumHaid) {
        stopDay = run.end;
        break;
      }
    }
    // Round-2 hardening (2026-10-21, proposed): purity is read the same
    // conservative way as the minimum haid duration below. "It stopped on
    // D" says bleeding may have lasted until the END of D (the closing
    // `none` observation never carries an exact time), and a date-only new
    // start may have begun at the START of its day (or exactly at its
    // observed time). The minimum (FD-7: 15 days; Hanbali 13) counts as
    // met only when it holds over that SHORTEST interval; otherwise the
    // evaluator's purity gate returns needsAdvisory. Previously this was
    // `calendarDaysBetween(stopDay, startDay)` — the most generous reading,
    // up to a day longer than the bleeding-free time actually known.
    // Counted in calendar days (DST-safe) unless the new start has an
    // exact time: whole days from the end of the stop day to the start of
    // the new start day.
    final Duration? purityBefore;
    if (stopDay == null) {
      purityBefore = null;
    } else {
      final startTime = currentRun.observedTime;
      final shortestPurity = startTime == null
          ? Duration(days: calendarDaysBetween(stopDay, activeStart) - 1)
          : startTime.difference(addCalendarDays(stopDay, 1));
      purityBefore = shortestPurity.isNegative
          ? Duration.zero
          : shortestPurity;
    }

    // Fiqh hardening (2026-10-18): a date-only start says only that
    // bleeding began at some point on that day. The duration is bounded
    // from both sides — from the day's midnight (longest) and from its
    // end (shortest) — and only a result that holds under BOTH bounds is
    // a confident haid. When the minimum is met only by assuming
    // bleeding began at midnight, the state stays needsAdvisory until it
    // is met under the shortest reading too. An exact observed time
    // (carried through by CanonicalFiqhEvidenceAdapter) collapses both
    // bounds onto that moment.
    final earliestStart = currentRun.observedTime ?? activeStart;
    final latestStart =
        currentRun.observedTime ?? addCalendarDays(activeStart, 1);
    final longestDuration = now.difference(earliestStart);
    final shortestRaw = now.difference(latestStart);
    final shortestDuration = shortestRaw.isNegative
        ? Duration.zero
        : shortestRaw;

    MadhhabRuleResult evaluateWith(Duration duration) =>
        const MadhhabRuleEvaluator().evaluate(
          madhhab: madhhab,
          hasSufficientHistory: calculation.hasSufficientHistory,
          isBleeding: true,
          bleedingDuration: duration,
          purityBefore: purityBefore,
        );
    final fromEarliest = evaluateWith(longestDuration).state;
    final fromLatest = evaluateWith(shortestDuration).state;
    final resultState =
        fromEarliest == FiqhCycleState.haid && fromLatest == FiqhCycleState.haid
        ? FiqhCycleState.haid
        : fromEarliest == FiqhCycleState.insufficientHistory
        ? FiqhCycleState.insufficientHistory
        : FiqhCycleState.needsAdvisory;

    if (resultState != FiqhCycleState.needsAdvisory) {
      final mappedState = resultState == FiqhCycleState.insufficientHistory
          ? FiqhCycleState.tahara
          : resultState;
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

    // A "confirms at" moment exists only when the sole open question is
    // the minimum duration: never for a purity shortfall or the maximum
    // bound (nothing later will turn those into a confirmed haid), and
    // never for Maliki (FD-7, 2026-10-15: no time-based minimum).
    final awaitingMinimumOnly =
        minimumHaid != null &&
        (purityBefore == null || purityBefore >= minimumPurity) &&
        longestDuration <= MadhhabRuleEvaluator.maximumHaidFor(madhhab) &&
        shortestDuration < minimumHaid;
    final confirmAt = awaitingMinimumOnly ? latestStart.add(minimumHaid) : null;
    return baseline(
      state: FiqhCycleState.needsAdvisory,
      confirmAt: confirmAt != null && confirmAt.isAfter(now)
          ? confirmAt
          : null,
      daysIntoCurrentEpisode: daysIntoCurrentEpisode,
    );
  }
}

class _BleedingRun {
  const _BleedingRun(this.first, this.end);

  /// The run's first bleeding log (its date, and exact time if known).
  final CycleLog first;

  /// The date of the `none` log that closed the run.
  final DateTime end;
}
