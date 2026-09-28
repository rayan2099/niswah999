import '../../../../core/utils/app_clock.dart';
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

  static const int _regularityMadCeilingDays = 10;

  /// Below this, an "average cycle length" is medically implausible for a
  /// real menstrual cycle — almost certainly too little history yet (e.g.
  /// two Haid starts logged only a couple of days apart), not a real
  /// number worth predicting from.
  static const int minPlausibleCycleLengthDays = 15;

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
    return _dateOnly(date).difference(starts.last).inDays + 1;
  }

  ({List<DateTime> starts, List<int> periodLengths}) _detectEpisodes(
    List<CycleLog> sortedLogs,
  ) {
    final starts = <DateTime>[];
    final periodLengths = <int>[];
    FlowLevel? previousFlow;
    DateTime? currentEpisodeStart;

    for (final log in sortedLogs) {
      final isBleeding = log.flow != FlowLevel.none;
      final date = _dateOnly(log.date);
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
          (starts.isEmpty || date.difference(starts.last).inDays > 1);
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
        final length = date.difference(currentEpisodeStart).inDays;
        if (length > 0) periodLengths.add(length);
        currentEpisodeStart = null;
      }
      previousFlow = log.flow;
    }

    return (starts: starts, periodLengths: periodLengths);
  }

  /// Merges canonical episode start dates into the starts detected from
  /// flat logs. A canonical start within 1 day of an already-detected
  /// start is the SAME episode (the flat-log rule above: no real cycle
  /// starts 0-1 days after the last one) and is dropped — so an episode
  /// that was also projected into `cycle_entries` is never counted twice.
  /// A canonical ended episode contributes its length only when it
  /// survived as a distinct start (log-derived pairing already covers the
  /// rest), so no period is averaged twice.
  ({List<DateTime> starts, List<int> periodLengths}) _mergeCanonical(
    ({List<DateTime> starts, List<int> periodLengths}) fromLogs,
    List<CanonicalEpisodeTiming> canonical,
  ) {
    if (canonical.isEmpty) return fromLogs;
    final candidates =
        <({DateTime date, bool fromCanonical, DateTime? end})>[
          for (final start in fromLogs.starts)
            (date: start, fromCanonical: false, end: null),
          for (final episode in canonical)
            (
              date: _dateOnly(episode.startDate),
              fromCanonical: true,
              end: episode.endDate == null ? null : _dateOnly(episode.endDate!),
            ),
        ]..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          if (byDate != 0) return byDate;
          // Same day: prefer the log-derived start (it carries the
          // richer, already-paired period length).
          return (a.fromCanonical ? 1 : 0) - (b.fromCanonical ? 1 : 0);
        });

    final starts = <DateTime>[];
    final periodLengths = [...fromLogs.periodLengths];
    // Length this loop added for the most recently kept CANONICAL start,
    // so it can be withdrawn if a log-derived start for the same episode
    // (within 1 day, and sorted just after it) replaces it.
    int? lastCanonicalLength;
    var lastKeptWasCanonical = false;
    for (final candidate in candidates) {
      if (starts.isNotEmpty &&
          candidate.date.difference(starts.last).inDays <= 1) {
        if (lastKeptWasCanonical && !candidate.fromCanonical) {
          // Same episode; the log-derived start is authoritative for it.
          starts[starts.length - 1] = candidate.date;
          if (lastCanonicalLength != null) {
            periodLengths.remove(lastCanonicalLength);
          }
          lastKeptWasCanonical = false;
          lastCanonicalLength = null;
        }
        continue;
      }
      starts.add(candidate.date);
      lastKeptWasCanonical = candidate.fromCanonical;
      lastCanonicalLength = null;
      if (candidate.fromCanonical && candidate.end != null) {
        final length = candidate.end!.difference(candidate.date).inDays;
        if (length > 0) {
          periodLengths.add(length);
          lastCanonicalLength = length;
        }
      }
    }
    return (starts: starts, periodLengths: periodLengths);
  }

  CycleCalculationResult calculate(
    List<CycleLog> logs, {
    DateTime? asOf,
    List<CanonicalEpisodeTiming> canonicalEpisodes = const [],
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

    if (starts.length < 2) {
      return CycleCalculationResult(
        haidStarts: List.unmodifiable(starts),
        currentCycleDay: null,
        averageCycleLength: null,
        cycleLengths: const [],
        averagePeriodLength: averagePeriodLength,
      );
    }

    final intervals = <int>[];
    for (var index = 1; index < starts.length; index++) {
      final days = starts[index].difference(starts[index - 1]).inDays;
      if (days > 0) intervals.add(days);
    }

    if (intervals.isEmpty) {
      return CycleCalculationResult(
        haidStarts: List.unmodifiable(starts),
        currentCycleDay: null,
        averageCycleLength: null,
        cycleLengths: List.unmodifiable(intervals),
        averagePeriodLength: averagePeriodLength,
      );
    }

    final today = _dateOnly(asOf ?? AppClock.now());
    final currentDay = today.difference(starts.last).inDays + 1;
    return CycleCalculationResult(
      haidStarts: List.unmodifiable(starts),
      currentCycleDay: currentDay > 0 ? currentDay : null,
      averageCycleLength: (intervals.reduce((a, b) => a + b) / intervals.length)
          .round(),
      cycleLengths: List.unmodifiable(intervals),
      averagePeriodLength: averagePeriodLength,
    );
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
