import '../../../../core/utils/app_clock.dart';
import '../entities/cycle_log.dart';
import '../services/cycle_calculation_service.dart';

class CycleTrackingController {
  const CycleTrackingController({
    this._calculationService = const CycleCalculationService(),
  });

  final CycleCalculationService _calculationService;

  CyclePhase calculatePhase({
    required DateTime date,
    required DateTime cycleStart,
    required int averageCycleLength,
  }) {
    final daysSinceStart = date.difference(cycleStart).inDays;
    if (daysSinceStart < 0) {
      return CyclePhase.follicular;
    }

    final cycleLength = averageCycleLength;
    final menstrualWindowEnd = (cycleLength * 0.2).round();
    final ovulationWindowStart = (cycleLength * 0.5).round();
    final ovulationWindowEnd = (cycleLength * 0.6).round();

    if (daysSinceStart < menstrualWindowEnd) {
      return CyclePhase.menstrual;
    }

    if (daysSinceStart >= ovulationWindowStart &&
        daysSinceStart <= ovulationWindowEnd) {
      return CyclePhase.ovulation;
    }

    if (daysSinceStart < cycleLength * 0.75) {
      return CyclePhase.follicular;
    }

    return CyclePhase.luteal;
  }

  /// Projects [cycleStart] forward by whole cycle lengths until the result
  /// is no longer in the past relative to [now] — a naive single addition
  /// silently lands in the past the moment a period is even one day late,
  /// which is exactly the bug this guards against. A projection landing
  /// exactly on [now] is left alone: being due *today* is correct, not
  /// overdue.
  DateTime predictNextPeriodStart({
    required DateTime cycleStart,
    required int averageCycleLength,
    required DateTime now,
  }) {
    var next = cycleStart.add(Duration(days: averageCycleLength));
    while (next.isBefore(now)) {
      next = next.add(Duration(days: averageCycleLength));
    }
    return next;
  }

  /// Standard "luteal phase = 14 days" heuristic: ovulation is estimated
  /// 14 days before the *next* predicted period, not the midpoint of the
  /// current cycle — matches the reference web app's predictOvulation.
  FertileWindow calculateFertileWindow({
    required DateTime cycleStart,
    required int averageCycleLength,
    required DateTime now,
  }) {
    final predictedNextPeriodStart = predictNextPeriodStart(
      cycleStart: cycleStart,
      averageCycleLength: averageCycleLength,
      now: now,
    );
    final ovulationDay = predictedNextPeriodStart.subtract(
      const Duration(days: 14),
    );
    final start = ovulationDay.subtract(const Duration(days: 5));
    final end = ovulationDay.add(const Duration(days: 1));

    return FertileWindow(start: start, end: end, peakDay: ovulationDay);
  }

  List<CycleLog> filterLogsByPhase(List<CycleLog> logs, CyclePhase? phase) {
    if (phase == null) {
      return logs;
    }

    return logs.where((log) {
      final phaseForLog = _phaseForCycleDay(log.cycleDay);
      return phaseForLog == phase;
    }).toList();
  }

  CycleTrackingSummary summarizeHistory(List<CycleLog> logs, {DateTime? now}) {
    final effectiveNow = now ?? AppClock.now();
    final calculation = _calculationService.calculate(
      logs,
      asOf: effectiveNow,
    );
    final lastCycleStart = calculation.lastHaidStart;
    final averageCycleLength = calculation.averageCycleLength;
    final averagePeriodLength = calculation.averagePeriodLength;
    // Forward projections (next period, fertile window) additionally
    // require a *plausible* average — never predict from a degenerate
    // interval like a 2-day "cycle length" just because the arithmetic
    // technically produced a number.
    final canProject =
        lastCycleStart != null && calculation.hasPlausibleAverage;
    final currentPhase = canProject
        ? calculatePhase(
            date: effectiveNow,
            cycleStart: lastCycleStart,
            averageCycleLength: averageCycleLength!,
          )
        : CyclePhase.follicular;
    final nextPeriodStart = canProject
        ? predictNextPeriodStart(
            cycleStart: lastCycleStart,
            averageCycleLength: averageCycleLength!,
            now: effectiveNow,
          )
        : null;
    final fertileWindow = canProject
        ? calculateFertileWindow(
            cycleStart: lastCycleStart,
            averageCycleLength: averageCycleLength!,
            now: effectiveNow,
          )
        : const FertileWindow(start: null, end: null, peakDay: null);

    return CycleTrackingSummary(
      averageCycleLength: averageCycleLength,
      averagePeriodLength: averagePeriodLength,
      lastCycleStart: lastCycleStart,
      currentPhase: currentPhase,
      fertileWindow: fertileWindow,
      nextPeriodStart: nextPeriodStart,
      hasPlausibleAverage: calculation.hasPlausibleAverage,
    );
  }

  CyclePhase _phaseForCycleDay(int cycleDay) {
    final normalizedCycleDay = cycleDay.clamp(1, 40);
    if (normalizedCycleDay <= 5) {
      return CyclePhase.menstrual;
    }
    if (normalizedCycleDay <= 12) {
      return CyclePhase.follicular;
    }
    if (normalizedCycleDay <= 18) {
      return CyclePhase.ovulation;
    }
    return CyclePhase.luteal;
  }
}
