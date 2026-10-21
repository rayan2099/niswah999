import 'dart:math' as math;

import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/calendar_days.dart';
import '../entities/bleeding_episode.dart';
import '../entities/cycle_log.dart';

enum CycleRegularity { insufficientData, irregular, regular, highlyRegular }

String cycleRegularityLabel(CycleRegularity value, {required bool isArabic}) {
  switch (value) {
    case CycleRegularity.insufficientData:
      return isArabic ? 'بيانات غير كافية' : 'Insufficient data';
    case CycleRegularity.irregular:
      return isArabic ? 'غير منتظم' : 'Irregular';
    case CycleRegularity.regular:
      return isArabic ? 'منتظم' : 'Regular';
    case CycleRegularity.highlyRegular:
      return isArabic ? 'مرتفع' : 'High';
  }
}

/// An episode-level TIMING fact from the canonical bleeding model: "a
/// bleeding episode started on [startDate] and (if it has ended) stopped
/// on [endDate]". Deliberately carries NO flow intensity.
///
/// Why this exists: `record_onboarding_menstrual_history` persists the
/// period a returning user reports during onboarding as a canonical
/// episode whose start observation is `flow = uncertain` (flow is never
/// asked there). `CycleEntriesProjection` correctly never projects an
/// uncertain flow — inventing one would be fabrication — so the legacy
/// flat `cycle_entries` model never learns that period happened, and the
/// Calendar/Insights screens told a woman with real history to "log two
/// cycle starts". The dates themselves ARE safely representable for
/// timing statistics (they are exactly what she reported), so they are
/// supplied here as facts, never as invented daily rows, and
/// `cycle_entries` never becomes authoritative for them.
class CanonicalEpisodeTiming {
  const CanonicalEpisodeTiming({required this.startDate, this.endDate});

  final DateTime startDate;
  final DateTime? endDate;
}

class CycleCalculationResult {
  const CycleCalculationResult({
    required this.haidStarts,
    required this.currentCycleDay,
    required this.averageCycleLength,
    required this.cycleLengths,
    this.averagePeriodLength,
    this.predictedCycleLength,
    this.predictionSpreadDays,
    this.predictionBasis,
    this.predictedPeriodLength,
  });

  final List<DateTime> haidStarts;
  final int? currentCycleDay;
  final int? averageCycleLength;

  /// Average length, in days, of completed bleeding episodes (a logged
  /// start paired with a later logged end). Null when no complete pair
  /// has ever been observed — never fabricated to a placeholder.
  final int? averagePeriodLength;

  /// Raw, unclamped per-cycle interval lengths in days, oldest-to-newest —
  /// the gaps between consecutive [haidStarts]. Never fabricated or
  /// outlier-filtered, consistent with [averageCycleLength].
  final List<int> cycleLengths;

  /// Length, in days, expected for the current cycle — what every forward
  /// prediction (next period, fertile window, reminders) is built from.
  /// Unlike [averageCycleLength], which stays the plain factual mean, this
  /// leaves out intervals that cannot be a single real cycle (outside
  /// [minPlausibleCycleLengthDays]–[maxPredictableCycleLengthDays], or at
  /// least [missedPeriodMedianFactor] times the median of the other
  /// qualifying intervals — almost always a period that was never logged) and weights the most recent cycles more. Null when no
  /// interval qualifies; nothing is predicted then.
  final int? predictedCycleLength;

  /// How much the qualifying cycles vary (weighted standard deviation, in
  /// days), with a floor so a short history never looks more certain than
  /// it is. Drives the late-period tolerance and the fertile-window width.
  /// Null exactly when [predictedCycleLength] is.
  final double? predictionSpreadDays;

  /// What [predictedCycleLength] was built from. Null exactly when it is.
  final PredictionBasis? predictionBasis;

  /// Period length to draw a predicted period with: [averagePeriodLength]
  /// when she has a completed period on record, otherwise her stated
  /// usual bleeding duration, otherwise null.
  final int? predictedPeriodLength;

  static const int _regularityMadCeilingDays = 10;

  /// Below this, an "average cycle length" is medically implausible for a
  /// real menstrual cycle — almost certainly too little history yet (e.g.
  /// two Haid starts logged only a couple of days apart), not a real
  /// number worth predicting from.
  static const int minPlausibleCycleLengthDays = 15;

  /// Above this, an interval is treated as missed logging rather than one
  /// real cycle, and is left out of [predictedCycleLength].
  static const int maxPredictableCycleLengthDays = 90;

  /// An interval at least this many times the median of the OTHER
  /// qualifying intervals is treated as a period that was never logged
  /// (two cycles summed) and left out of [predictedCycleLength]. Decided
  /// 2026-10-21 (docs/cycle-prediction-model.md): a missed period is two
  /// real cycles summed and, with ordinary variation, often lands just
  /// under 2x (e.g. 69 among 35-day cycles), which skewed predictions by
  /// weeks under the former 2.0 factor.
  static const double missedPeriodMedianFactor = 1.8;

  bool get hasSufficientHistory =>
      haidStarts.length >= 2 &&
      currentCycleDay != null &&
      averageCycleLength != null;

  /// Whether [averageCycleLength] is not just present but large enough to
  /// be believable. Deliberately separate from [hasSufficientHistory]:
  /// fiqh classification, notification scheduling, and simple day-tallies
  /// all remain valid and safety-relevant even when this is false (e.g. an
  /// actively-bleeding user must never be reclassified as "insufficient
  /// history" just because her average happens to be implausible) — only
  /// *forward predictions* (next period, fertile window, the cycle ring)
  /// should gate on this.
  bool get hasPlausibleAverage =>
      averageCycleLength != null &&
      averageCycleLength! >= minPlausibleCycleLengthDays;

  /// Whether forward predictions can be made at all — see
  /// [predictedCycleLength]. Includes a prediction from her stated
  /// estimate alone; see [canPredictFromHistory].
  bool get canPredict => lastHaidStart != null && predictedCycleLength != null;

  /// Whether the prediction rests on at least one cycle she logged, not
  /// only on her stated estimate. Anything presented as "your cycle"
  /// (fertile window, ring, reminders, calendar blocks) needs this.
  ///
  /// Also requires [hasPlausibleAverage], the gate Today and Insights
  /// already applied (proposed, prediction-efficiency audit 2026-10-21):
  /// with starts logged 3 and then 20 days apart the average is 12 days
  /// and Today/Insights showed no prediction, while the Calendar tab, the
  /// canonical calendar, the husband report and the reminder still
  /// predicted from the 20-day interval alone.
  bool get canPredictFromHistory =>
      canPredict &&
      predictionBasis != PredictionBasis.statedEstimate &&
      hasPlausibleAverage;

  /// Whether there are enough logged cycles to compute a meaningful spread.
  /// Stricter than [hasSufficientHistory]: a single interval has no
  /// variance to speak of, so regularity needs one more logged cycle than
  /// the average-length figure does.
  bool get hasRegularityData => cycleLengths.length >= 2;

  double get _preciseMeanCycleLength =>
      cycleLengths.reduce((a, b) => a + b) / cycleLengths.length;

  double get _meanAbsoluteDeviation {
    final mean = _preciseMeanCycleLength;
    return cycleLengths
            .map((length) => (length - mean).abs())
            .reduce((a, b) => a + b) /
        cycleLengths.length;
  }

  /// 0.0 (highly irregular) to 1.0 (perfectly regular), based on the mean
  /// absolute deviation of [cycleLengths]. Null when [hasRegularityData] is
  /// false.
  double? get regularityScore => hasRegularityData
      ? (1 - (_meanAbsoluteDeviation / _regularityMadCeilingDays)).clamp(
          0.0,
          1.0,
        )
      : null;

  CycleRegularity get regularity {
    final score = regularityScore;
    if (score == null) return CycleRegularity.insufficientData;
    if (score >= 0.8) return CycleRegularity.highlyRegular;
    if (score >= 0.5) return CycleRegularity.regular;
    return CycleRegularity.irregular;
  }

  /// Whether a single cycle length falls within the normal spread for this
  /// history — used to color individual cycle markers. False when
  /// [hasRegularityData] is false.
  bool isCycleLengthWithinNormalRange(int length) {
    if (!hasRegularityData) return false;
    final mean = _preciseMeanCycleLength;
    final mad = _meanAbsoluteDeviation;
    final threshold = mad > 3 ? mad : 3;
    return (length - mean).abs() <= threshold;
  }

  DateTime? get lastHaidStart => haidStarts.isEmpty ? null : haidStarts.last;
}

/// Calculates factual cycle values from confirmed, stored Haid-start logs.
///
/// Fiqh classification is intentionally outside this service pending review of
/// the madhhab rule matrix. No cycle length or cycle day is fabricated when
/// fewer than two distinct Haid starts have been logged.
class CycleCalculationService {
  const CycleCalculationService();

  /// How many of her most recent `cycle_entries` rows every prediction
  /// reads (Today, Insights, the Calendar tab, the reminder and the
  /// reports), so they all see the same history. Large enough (about
  /// three years of daily logging) that the cut never lands in the
  /// cycles a prediction uses: with 200 rows it could fall mid-period,
  /// turning a period's third day into a "cycle start", and the reminder
  /// (which read 1,000) could disagree with Today (proposed,
  /// prediction-efficiency audit 2026-10-21).
  static const int historyLogLimit = 1000;

  /// The correct `cycleDay` for a brand-new log at [date] with [flow],
  /// given every other already-stored log ([existingLogs]) — day 1 if this
  /// genuinely starts a new Haid episode, otherwise the real day count
  /// continuing from whichever episode was active on [date].
  ///
  /// `cycleDay == 1` is a load-bearing signal read elsewhere in this class
  /// (and by other domain services) as "a new Haid episode starts here," so
  /// it must never be hardcoded for every new entry — that would make every
  /// logged day look like a fresh cycle start.
  int computeCycleDayForNewEntry({
    required List<CycleLog> existingLogs,
    required DateTime date,
    required FlowLevel flow,
  }) {
    final priorLogs = existingLogs
        .where((log) => !log.date.isAfter(date))
        .toList();
    final candidate = CycleLog(
      id: '__candidate__',
      userId: '__candidate__',
      date: date,
      flow: flow,
      // Deliberately not 1: cycleDay == 1 would short-circuit this
      // candidate's own (correct) transition-based start detection below.
      cycleDay: 2,
    );
    final sorted = [...priorLogs, candidate]
      ..sort((a, b) => a.date.compareTo(b.date));
    final starts = _detectEpisodes(sorted).starts;
    if (starts.isEmpty) return 1;
    return calendarDaysBetween(starts.last, date) + 1;
  }

  /// Starts detected from flat logs, and each completed period's length
  /// keyed by the start it belongs to (so a merge with canonical episodes
  /// can withdraw exactly the periods it replaces).
  ({List<DateTime> starts, List<({DateTime start, int length})> periods})
  _detectEpisodes(List<CycleLog> sortedLogs) {
    final starts = <DateTime>[];
    final periods = <({DateTime start, int length})>[];
    FlowLevel? previousFlow;
    DateTime? currentEpisodeStart;

    for (final log in sortedLogs) {
      // A symptoms/notes-only row states nothing about bleeding; reading
      // its placeholder `none` would end the period mid-way and turn the
      // next bleeding day into a new "cycle start" (round-2 hardening).
      if (!log.recordsFlow) continue;
      final isBleeding = log.flow != FlowLevel.none;
      final date = calendarDay(log.date);
      // A cycleDay == 1 log only counts as a genuine new episode if it's
      // more than a day after the previous one — no real menstrual cycle
      // starts 0-1 days after the last one started, so a log this close is
      // almost certainly a re-tap/correction of the same start rather than
      // a second distinct episode. This intentionally does NOT require an
      // explicit logged end in between: many users only ever log day 1 of
      // each period without logging every Tahara day, and that must keep
      // working (existing multi-cycle history relies on it).
      final explicitlyLoggedStart =
          isBleeding &&
          log.cycleDay == 1 &&
          (starts.isEmpty || calendarDaysBetween(starts.last, date) > 1);
      final transitionedToBleeding =
          isBleeding && previousFlow == FlowLevel.none;
      final firstRecordedBleeding = isBleeding && previousFlow == null;

      if (explicitlyLoggedStart ||
          transitionedToBleeding ||
          firstRecordedBleeding) {
        if (starts.isEmpty || starts.last != date) starts.add(date);
        currentEpisodeStart ??= date;
      } else if (!isBleeding &&
          previousFlow != null &&
          previousFlow != FlowLevel.none &&
          currentEpisodeStart != null) {
        final length = calendarDaysBetween(currentEpisodeStart, date);
        if (length > 0) {
          periods.add((start: currentEpisodeStart, length: length));
        }
        currentEpisodeStart = null;
      }
      previousFlow = log.flow;
    }

    return (starts: starts, periods: periods);
  }

  /// Merges canonical episode start dates into the starts detected from
  /// flat logs, so an episode that was also projected into `cycle_entries`
  /// is never counted twice:
  ///
  /// * A log-derived start that falls inside a canonical episode's span
  ///   (from its start to its end date, or anywhere after the start while
  ///   it is still open) is that same episode. The canonical start is kept
  ///   (it is what she reported; its first day may be "I'm not sure", which
  ///   is never projected) and the log-derived start and its paired period
  ///   length are dropped. Proposed, round-2 property tests (2026-10-21):
  ///   before this, a projection that began two or more days after the
  ///   canonical start counted one period as two cycles, and one a day later
  ///   moved the start by a day.
  /// * A log-derived start one day before a canonical start is also the
  ///   same episode (no real cycle starts 0-1 days after the last one); the
  ///   log-derived start is kept with its paired length, as before.
  /// * A canonical ended episode contributes its own length whenever its
  ///   start is kept.
  ({List<DateTime> starts, List<int> periodLengths}) _mergeCanonical(
    ({List<DateTime> starts, List<({DateTime start, int length})> periods})
    fromLogs,
    List<CanonicalEpisodeTiming> canonical,
  ) {
    if (canonical.isEmpty) {
      return (
        starts: fromLogs.starts,
        periodLengths: [for (final p in fromLogs.periods) p.length],
      );
    }
    final spans = [
      for (final episode in canonical)
        (
          start: calendarDay(episode.startDate),
          end: episode.endDate == null ? null : calendarDay(episode.endDate!),
        ),
    ];
    bool insideCanonicalSpan(DateTime day) => spans.any(
      (span) =>
          calendarDaysBetween(span.start, day) >= 0 &&
          (span.end == null || calendarDaysBetween(day, span.end!) >= 0),
    );
    final logLengths = <DateTime, List<int>>{};
    for (final period in fromLogs.periods) {
      logLengths.putIfAbsent(period.start, () => []).add(period.length);
    }

    final candidates =
        <({DateTime date, bool fromCanonical, List<int> lengths})>[
          for (final start in fromLogs.starts)
            if (!insideCanonicalSpan(start))
              (
                date: start,
                fromCanonical: false,
                lengths: logLengths[start] ?? const [],
              ),
          for (final span in spans)
            (
              date: span.start,
              fromCanonical: true,
              lengths: [
                if (span.end != null &&
                    calendarDaysBetween(span.start, span.end!) > 0)
                  calendarDaysBetween(span.start, span.end!),
              ],
            ),
        ]..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          if (byDate != 0) return byDate;
          // Same day: prefer the log-derived start (it carries the
          // already-paired period length).
          return (a.fromCanonical ? 1 : 0) - (b.fromCanonical ? 1 : 0);
        });

    final kept = <({DateTime date, bool fromCanonical, List<int> lengths})>[];
    for (final candidate in candidates) {
      if (kept.isNotEmpty &&
          calendarDaysBetween(kept.last.date, candidate.date) <= 1) {
        if (kept.last.fromCanonical && !candidate.fromCanonical) {
          // Only reachable for a zero-length canonical span: the log-derived
          // start of the same episode, the next day, replaces it.
          kept[kept.length - 1] = candidate;
        }
        continue;
      }
      kept.add(candidate);
    }
    return (
      starts: [for (final k in kept) k.date],
      periodLengths: [for (final k in kept) ...k.lengths],
    );
  }

  /// [statedBaseline] is her own onboarding estimate of her usual cycle
  /// and period length. It never becomes a statistic of its own
  /// ([averageCycleLength], [cycleLengths] and [averagePeriodLength] stay
  /// purely logged facts); it only informs the forward prediction fields.
  CycleCalculationResult calculate(
    List<CycleLog> logs, {
    DateTime? asOf,
    List<CanonicalEpisodeTiming> canonicalEpisodes = const [],
    CycleBaseline? statedBaseline,
  }) {
    final sorted = [...logs]..sort((a, b) => a.date.compareTo(b.date));
    final episodes = _mergeCanonical(
      _detectEpisodes(sorted),
      canonicalEpisodes,
    );
    final starts = episodes.starts;
    final periodLengths = episodes.periodLengths;

    final averagePeriodLength = periodLengths.isEmpty
        ? null
        : (periodLengths.reduce((a, b) => a + b) / periodLengths.length)
              .round();
    final predictedPeriodLength =
        averagePeriodLength ?? statedPeriodLength(statedBaseline);
    final statedCycle = statedCycleLength(statedBaseline);

    if (starts.length < 2) {
      final prediction = starts.isEmpty
          ? null
          : predictFromIntervals(const [], statedCycleLength: statedCycle);
      return CycleCalculationResult(
        haidStarts: List.unmodifiable(starts),
        currentCycleDay: null,
        averageCycleLength: null,
        cycleLengths: const [],
        averagePeriodLength: averagePeriodLength,
        predictedCycleLength: prediction?.length,
        predictionSpreadDays: prediction?.spreadDays,
        predictionBasis: prediction?.basis,
        predictedPeriodLength: predictedPeriodLength,
      );
    }

    final intervals = <int>[];
    for (var index = 1; index < starts.length; index++) {
      final days = calendarDaysBetween(starts[index - 1], starts[index]);
      if (days > 0) intervals.add(days);
    }

    if (intervals.isEmpty) {
      final prediction = predictFromIntervals(
        const [],
        statedCycleLength: statedCycle,
      );
      return CycleCalculationResult(
        haidStarts: List.unmodifiable(starts),
        currentCycleDay: null,
        averageCycleLength: null,
        cycleLengths: List.unmodifiable(intervals),
        averagePeriodLength: averagePeriodLength,
        predictedCycleLength: prediction?.length,
        predictionSpreadDays: prediction?.spreadDays,
        predictionBasis: prediction?.basis,
        predictedPeriodLength: predictedPeriodLength,
      );
    }

    final currentDay =
        calendarDaysBetween(starts.last, asOf ?? AppClock.now()) + 1;
    final prediction = predictFromIntervals(
      intervals,
      statedCycleLength: statedCycle,
    );
    return CycleCalculationResult(
      haidStarts: List.unmodifiable(starts),
      currentCycleDay: currentDay > 0 ? currentDay : null,
      averageCycleLength: (intervals.reduce((a, b) => a + b) / intervals.length)
          .round(),
      cycleLengths: List.unmodifiable(intervals),
      averagePeriodLength: averagePeriodLength,
      predictedCycleLength: prediction?.length,
      predictionSpreadDays: prediction?.spreadDays,
      predictionBasis: prediction?.basis,
      predictedPeriodLength: predictedPeriodLength,
    );
  }

  /// Her stated usual cycle length, when it is one a prediction can use.
  static int? statedCycleLength(CycleBaseline? baseline) {
    final days = baseline?.usualCycleLengthDays;
    if (days == null ||
        days < CycleCalculationResult.minPlausibleCycleLengthDays ||
        days > CycleCalculationResult.maxPredictableCycleLengthDays) {
      return null;
    }
    return days;
  }

  /// Her stated usual bleeding duration, when it is a believable one.
  static int? statedPeriodLength(CycleBaseline? baseline) {
    final days = baseline?.usualBleedingDurationDays;
    if (days == null || days < 1 || days > _maxStatedPeriodDays) return null;
    return days;
  }

  static const int _maxStatedPeriodDays = 15;

  /// Only the most recent cycles inform a prediction; older ones describe
  /// a body that may have changed.
  static const int _recentCycleCount = 6;

  /// Each step back in time counts this much less than the cycle after it.
  static const double _recencyDecay = 0.8;

  /// Floor on [CycleCalculationResult.predictionSpreadDays]: no history is
  /// ever treated as more precise than this.
  static const double _minSpreadDays = 1.5;

  /// Spread assumed while fewer than three cycles qualify — two points say
  /// almost nothing about how much a cycle varies.
  static const double _sparseHistorySpreadDays = 3;

  /// Spread assumed for a prediction from her stated estimate alone. Wider
  /// than [_sparseHistorySpreadDays]: a remembered "usually about 28 days"
  /// is less exact than even one logged cycle.
  static const double _statedEstimateSpreadDays = 4;

  /// Prior weight of her stated cycle length, in cycles: with n logged
  /// cycles the logged mean counts n/(n+2) and the estimate 2/(n+2)
  /// (Flo's outline). Once [_recentCycleCount] cycles are logged the
  /// estimate is dropped entirely, so a wrong guess cannot bias a
  /// well-established history forever.
  static const double _statedEstimateWeightCycles = 2;

  /// Predicted next-cycle length and its spread from raw, oldest-to-newest
  /// cycle [intervals] (see [CycleCalculationResult.predictedCycleLength]),
  /// optionally informed by her [statedCycleLength] (see
  /// [_statedEstimateWeightCycles]). Shared by every screen that predicts,
  /// so they never disagree.
  static double _median(List<int> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle].toDouble()
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static ({int length, double spreadDays, PredictionBasis basis})?
  predictFromIntervals(List<int> intervals, {int? statedCycleLength}) {
    final plausible = intervals
        .where(
          (days) =>
              days >= CycleCalculationResult.minPlausibleCycleLengthDays &&
              days <= CycleCalculationResult.maxPredictableCycleLengthDays,
        )
        .toList();
    if (plausible.isEmpty) {
      if (statedCycleLength == null) return null;
      return (
        length: statedCycleLength,
        spreadDays: _statedEstimateSpreadDays,
        basis: PredictionBasis.statedEstimate,
      );
    }
    // Leave-one-out (decided 2026-10-21): an interval is a missed log when
    // it is at least [CycleCalculationResult.missedPeriodMedianFactor]
    // times the median of the OTHER qualifying intervals. A median that
    // included the gap itself let [35, 70] (one period never logged)
    // through and moved the prediction from 35 to 51 days. A lone interval
    // is always kept, and the rule never drops every interval.
    const factor = CycleCalculationResult.missedPeriodMedianFactor;
    final filtered = [
      for (var i = 0; i < plausible.length; i++)
        if (plausible.length == 1 ||
            plausible[i] < factor * _median([...plausible]..removeAt(i)))
          plausible[i],
    ];
    final valid = filtered.isEmpty ? plausible : filtered;
    final recent = valid.reversed.take(_recentCycleCount).toList();

    var weightSum = 0.0;
    var weightedSum = 0.0;
    for (var k = 0; k < recent.length; k++) {
      final weight = math.pow(_recencyDecay, k).toDouble();
      weightSum += weight;
      weightedSum += weight * recent[k];
    }
    final historyMean = weightedSum / weightSum;
    final useEstimate =
        statedCycleLength != null && valid.length < _recentCycleCount;
    final historyWeight =
        valid.length / (valid.length + _statedEstimateWeightCycles);
    final mean = useEstimate
        ? historyWeight * historyMean + (1 - historyWeight) * statedCycleLength
        : historyMean;

    double spread;
    if (recent.length < 3) {
      spread = _sparseHistorySpreadDays;
    } else {
      var weightedSquares = 0.0;
      for (var k = 0; k < recent.length; k++) {
        final weight = math.pow(_recencyDecay, k).toDouble();
        weightedSquares += weight * math.pow(recent[k] - historyMean, 2);
      }
      spread = math.sqrt(weightedSquares / weightSum);
    }
    return (
      length: mean.round(),
      spreadDays: math.max(spread, _minSpreadDays),
      basis: useEstimate
          ? PredictionBasis.historyAndEstimate
          : PredictionBasis.history,
    );
  }
}
