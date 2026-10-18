import 'dart:math' as math;

import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/calendar_days.dart';
import '../entities/bleeding_episode.dart';
import '../entities/cycle_log.dart';
import '../services/cycle_calculation_service.dart';

class CycleTrackingController {
  const CycleTrackingController({
    this._calculationService = const CycleCalculationService(),
  });

  final CycleCalculationService _calculationService;

  /// Standard luteal phase: ovulation is about 14 days before the next
  /// period, whatever the cycle length.
  static const lutealPhaseDays = 14;

  /// Ovulation is not predicted for cycles shorter or longer than this —
  /// a fixed luteal phase says little about cycles outside it.
  static const minOvulationCycleDays = 21;
  static const maxOvulationCycleDays = 60;

  /// Upper bound on the late-period tolerance window, so a very irregular
  /// history cannot hide a real delay for weeks.
  static const maxLateToleranceDays = 10;

  /// Phase of [date] in a cycle that began on [cycleStart], using the same
  /// ovulation and fertile-window rule as [calculateFertileWindow]:
  /// menstrual for the period's days, ovulation across the fertile window,
  /// follicular before it and luteal after it.
  CyclePhase calculatePhase({
    required DateTime date,
    required DateTime cycleStart,
    required int averageCycleLength,
    int periodLength = 5,
  }) {
    final dayIndex = calendarDaysBetween(cycleStart, date);
    if (dayIndex < 0) {
      return CyclePhase.follicular;
    }
    if (dayIndex < periodLength) {
      return CyclePhase.menstrual;
    }

    final ovulationIndex = averageCycleLength - lutealPhaseDays;
    if (dayIndex >= ovulationIndex - 5 && dayIndex <= ovulationIndex + 1) {
      return CyclePhase.ovulation;
    }
    return dayIndex < ovulationIndex
        ? CyclePhase.follicular
        : CyclePhase.luteal;
  }

  /// Expected start of the period that ends the cycle begun on
  /// [cycleStart]. Pure calendar arithmetic: never rolled forward when the
  /// date has passed — a late period is reported as late by
  /// [summarizeHistory], not silently replaced by next month's date.
  DateTime predictNextPeriodStart({
    required DateTime cycleStart,
    required int averageCycleLength,
  }) => addCalendarDays(cycleStart, averageCycleLength);

  /// Days a period may run past its expected date before it is called
  /// late — wider for cycles that vary more (Flo-style probability window).
  static int lateToleranceDays(double spreadDays) =>
      math.min(maxLateToleranceDays, (1.5 * spreadDays).ceil());

  /// Days the period expected on [expected] is most likely to start on:
  /// from `ceil(spread)` days early to `ceil(1.5 × spread)` days late
  /// (cycles run late more often than early), never starting before
  /// [today]. Null once [today] is past the late end — she is then
  /// clearly late and nothing is predicted.
  static PredictedDateRange? nextPeriodRange({
    required DateTime expected,
    required double spreadDays,
    required DateTime today,
  }) {
    final day = calendarDay(today);
    final earliest = addCalendarDays(expected, -spreadDays.ceil());
    final latest = addCalendarDays(expected, (1.5 * spreadDays).ceil());
    if (latest.isBefore(day)) return null;
    return PredictedDateRange(
      earliest: earliest.isBefore(day) ? day : earliest,
      latest: latest,
    );
  }

  /// Fertile window for the cycle begun on [cycleStart]: ovulation 14
  /// days before the expected next period, and the window from 5 days
  /// before ovulation to 1 day after. When the cycles vary by more than 2
  /// days ([spreadDays]), the window widens on both sides by up to 3 days
  /// so the uncertainty is shown rather than hidden. Empty when the cycle
  /// is too short or long for the luteal-phase rule.
  FertileWindow calculateFertileWindow({
    required DateTime cycleStart,
    required int averageCycleLength,
    double spreadDays = 0,
  }) {
    if (averageCycleLength < minOvulationCycleDays ||
        averageCycleLength > maxOvulationCycleDays) {
      return const FertileWindow(start: null, end: null, peakDay: null);
    }
    final ovulationDay = addCalendarDays(
      cycleStart,
      averageCycleLength - lutealPhaseDays,
    );
    final widen = spreadDays <= 2 ? 0 : math.min(3, spreadDays.ceil());
    final start = addCalendarDays(ovulationDay, -5 - widen);
    final end = addCalendarDays(ovulationDay, 1 + widen);

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
    CycleBaseline? statedBaseline,
  }) {
    final today = calendarDay(now ?? AppClock.now());
    final calculation = _calculationService.calculate(
      logs,
      asOf: today,
      canonicalEpisodes: canonicalEpisodes,
      statedBaseline: statedBaseline,
    );
    final lastCycleStart = calculation.lastHaidStart;
    final averageCycleLength = calculation.averageCycleLength;
    final averagePeriodLength = calculation.averagePeriodLength;
    final predictedLength = calculation.predictedCycleLength;
    // Forward projections (next period, fertile window) require a
    // predictable cycle length — never predict from a degenerate interval
    // like a 2-day "cycle length", or from a gap that is really a missed
    // log, just because the arithmetic technically produced a number.
    if (!calculation.canPredict) {
      return _unpredicted(calculation);
    }

    final cycleStart = lastCycleStart!;
    final spreadDays = calculation.predictionSpreadDays!;
    final expected = predictNextPeriodStart(
      cycleStart: cycleStart,
      averageCycleLength: predictedLength!,
    );
    final range = nextPeriodRange(
      expected: expected,
      spreadDays: spreadDays,
      today: today,
    );

    if (!calculation.canPredictFromHistory) {
      // Her stated estimate and one logged start, nothing more (charter
      // F5/F6): only the labeled range is offered. No single "next period"
      // date, fertile window, phase or ring, which would present an
      // estimate as her own observed pattern.
      return _unpredicted(calculation, statedEstimateRange: range);
    }

    final daysLate = math.max(0, calendarDaysBetween(expected, today));
    final tolerance = lateToleranceDays(spreadDays);
    // On time: the expected date. Late but inside the tolerance window:
    // "today" — it can start any day now, and a date in the past is never
    // shown as "next". Past the window: no date at all; [daysLate] says
    // how late it is and nothing further is predicted until she logs.
    final DateTime? nextPeriodStart = daysLate == 0
        ? expected
        : daysLate <= tolerance
        ? today
        : null;
    final fertileWindow = daysLate == 0
        ? calculateFertileWindow(
            cycleStart: cycleStart,
            averageCycleLength: predictedLength,
            spreadDays: spreadDays,
          )
        : const FertileWindow(start: null, end: null, peakDay: null);

    return CycleTrackingSummary(
      averageCycleLength: averageCycleLength,
      averagePeriodLength: averagePeriodLength,
      lastCycleStart: lastCycleStart,
      currentPhase: calculatePhase(
        date: today,
        cycleStart: cycleStart,
        averageCycleLength: predictedLength,
        periodLength: calculation.predictedPeriodLength ?? 5,
      ),
      fertileWindow: fertileWindow,
      nextPeriodStart: nextPeriodStart,
      hasPlausibleAverage: true,
      predictedCycleLength: predictedLength,
      daysLate: daysLate,
      nextPeriodRange: range,
      predictionBasis: calculation.predictionBasis,
    );
  }

  static CycleTrackingSummary _unpredicted(
    CycleCalculationResult calculation, {
    PredictedDateRange? statedEstimateRange,
  }) => CycleTrackingSummary(
    averageCycleLength: calculation.averageCycleLength,
    averagePeriodLength: calculation.averagePeriodLength,
    lastCycleStart: calculation.lastHaidStart,
    currentPhase: CyclePhase.follicular,
    fertileWindow: const FertileWindow(start: null, end: null, peakDay: null),
    hasPlausibleAverage: false,
    nextPeriodRange: statedEstimateRange,
    predictionBasis: statedEstimateRange == null
        ? null
        : PredictionBasis.statedEstimate,
  );

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
