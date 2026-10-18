import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/calendar_day.dart';
import '../entities/cycle_log.dart';
import '../services/cycle_calculation_service.dart';
import '../services/cycle_prediction_service.dart';
import '../entities/period_prediction.dart';
import '../entities/prediction_history_review.dart';

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
    final daysSinceStart = calendarDayDifference(date, cycleStart);
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

  /// One estimate from the last recorded start. An overdue estimate stays
  /// overdue; advancing by whole cycles would invent unrecorded periods.
  DateTime predictNextPeriodStart({
    required DateTime cycleStart,
    required int averageCycleLength,
    required DateTime now,
  }) {
    if (averageCycleLength <= 0) {
      throw ArgumentError.value(averageCycleLength, 'averageCycleLength');
    }
    return addCalendarDays(cycleStart, averageCycleLength);
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
    final today = DateTime(now.year, now.month, now.day);
    if (predictedNextPeriodStart.isBefore(today)) {
      return const FertileWindow(start: null, end: null, peakDay: null);
    }
    final ovulationDay = addCalendarDays(predictedNextPeriodStart, -14);
    final start = addCalendarDays(ovulationDay, -5);
    final end = addCalendarDays(ovulationDay, 1);

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

  CycleTrackingSummary summarizeHistory(
    List<CycleLog> logs, {
    DateTime? now,
    List<CanonicalEpisodeTiming> canonicalEpisodes = const [],
    PeriodPredictionMethod predictionMethod =
        PeriodPredictionMethod.historicalMean,
    List<PredictionHistoryReview> historyReviews = const [],
    bool historyVerified = true,
  }) {
    final effectiveNow = now ?? AppClock.now();
    final calculation = _calculationService.calculate(
      logs,
      asOf: effectiveNow,
      canonicalEpisodes: canonicalEpisodes,
    );
    final lastCycleStart = calculation.lastHaidStart;
    final averageCycleLength = calculation.averageCycleLength;
    final averagePeriodLength = calculation.averagePeriodLength;
    // Forward projections (next period, fertile window) additionally
    // require a *plausible* average — never predict from a degenerate
    // interval like a 2-day "cycle length" just because the arithmetic
    // technically produced a number.
    final prediction = const CyclePredictionService().predict(
      lastStart: lastCycleStart,
      cycleLengths: calculation.cycleLengths,
      now: effectiveNow,
      method: predictionMethod,
      historyReviews: historyReviews,
      historyVerified: historyVerified,
    );
    final canProject = prediction.hasFutureEstimate;
    // Derived phase/fertile dates must use the same eligible intervals as
    // the period estimate, never the old all-history descriptive average.
    final projectedCycleLength =
        prediction.expectedStart == null || lastCycleStart == null
        ? null
        : calendarDayDifference(prediction.expectedStart!, lastCycleStart);
    final currentPhase = canProject
        ? calculatePhase(
            date: effectiveNow,
            cycleStart: lastCycleStart!,
            averageCycleLength: projectedCycleLength!,
          )
        : CyclePhase.follicular;
    final nextPeriodStart = canProject ? prediction.expectedStart : null;
    final fertileWindow = canProject
        ? calculateFertileWindow(
            cycleStart: lastCycleStart!,
            averageCycleLength: projectedCycleLength!,
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
      periodPrediction: prediction,
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
