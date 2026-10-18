import '../../../../core/utils/calendar_day.dart';
import '../entities/period_prediction.dart';
import '../entities/prediction_history_review.dart';

/// Recent, per-person estimates. Eligibility limits below are conservative
/// product policies, not medical normality thresholds or calibrated accuracy.
/// The default formula remains a mean; candidate methods are not auto-promoted.
class CyclePredictionService {
  const CyclePredictionService();
  static const candidateRecentIntervalCount = 6;
  static const minimumUsableIntervalDays = 15;
  static const maximumSupportedIntervalDays = 90;
  static const maximumHistoricalRangeWidthDays = 21;
  static const minimumIntervalsAfterBreak = 2;

  PeriodPrediction predict({
    required DateTime? lastStart,
    required List<int> cycleLengths,
    required DateTime now,
    PeriodPredictionMethod method = PeriodPredictionMethod.historicalMean,
    bool historyVerified = true,
    List<PredictionHistoryReview> historyReviews = const [],
  }) {
    final gaps = <PredictionHistoryGap>[];
    var selectedStart = cycleLengths.length > candidateRecentIntervalCount
        ? cycleLengths.length - candidateRecentIntervalCount
        : 0;
    PeriodPrediction withhold(PredictionReviewReason reason) =>
        PeriodPrediction(
          status: PeriodPredictionStatus.historyNeedsReview,
          method: method,
          totalIntervalCount: cycleLengths.length,
          reviewReason: reason,
          reviewGaps: List.unmodifiable(gaps),
          excludedIntervalCount: selectedStart,
        );
    if (!historyVerified) {
      return withhold(PredictionReviewReason.unverifiedHistory);
    }
    if ((lastStart != null && calendarDayDifference(lastStart, now) > 0) ||
        cycleLengths.any((length) => length < minimumUsableIntervalDays)) {
      return withhold(PredictionReviewReason.invalidHistory);
    }
    if (lastStart == null || cycleLengths.isEmpty) {
      return PeriodPrediction(
        status: PeriodPredictionStatus.insufficientHistory,
        method: method,
        totalIntervalCount: cycleLengths.length,
      );
    }
    if (calendarDayDifference(now, lastStart) > maximumSupportedIntervalDays) {
      return withhold(PredictionReviewReason.staleHistory);
    }

    // Reconstruct endpoint pairs without using future records or mutating input.
    final starts = List<DateTime>.filled(cycleLengths.length + 1, lastStart);
    for (var i = cycleLengths.length - 1; i >= 0; i--) {
      starts[i] = addCalendarDays(starts[i + 1], -cycleLengths[i]);
    }
    final reviews = <String, PredictionHistoryReview>{};
    for (final review in historyReviews) {
      // A backdated evaluation must not see answers submitted later.
      if (review.reportedAt.isAfter(now)) continue;
      final existing = reviews[review.key];
      if (existing == null || review.reportedAt.isAfter(existing.reportedAt)) {
        reviews[review.key] = review;
      }
    }
    final windowStart = selectedStart;
    var resetAfterBreak = false;
    var unsupported = false;
    for (var i = windowStart; i < cycleLengths.length; i++) {
      final length = cycleLengths[i];
      final prior =
          cycleLengths
              .sublist(
                i > candidateRecentIntervalCount
                    ? i - candidateRecentIntervalCount
                    : 0,
                i,
              )
              .where(
                (x) =>
                    x >= minimumUsableIntervalDays &&
                    x <= maximumSupportedIntervalDays,
              )
              .toList()
            ..sort();
      final baseline = prior.isEmpty ? null : _median(prior);
      final unusual =
          length > maximumSupportedIntervalDays ||
          (prior.length >= 3 &&
              length > baseline! * 2 &&
              length - baseline >= 14);
      if (!unusual) continue;
      final key = PredictionHistoryReview.intervalKey(starts[i], starts[i + 1]);
      final resolution = reviews[key]?.resolution;
      gaps.add(
        PredictionHistoryGap(
          start: starts[i],
          end: starts[i + 1],
          resolution: resolution,
        ),
      );
      if (resolution == PredictionGapResolution.missedRecords ||
          resolution == PredictionGapResolution.unsure) {
        // Never split this gap into made-up cycles. Resume only from real
        // later starts, with two new observed intervals after the boundary.
        selectedStart = i + 1;
        resetAfterBreak = true;
      } else if (resolution == PredictionGapResolution.longerCycle &&
          length > maximumSupportedIntervalDays) {
        unsupported = true;
      }
    }
    if (gaps.any((g) => g.resolution == null)) {
      return withhold(PredictionReviewReason.unexplainedGap);
    }
    if (unsupported) {
      return withhold(PredictionReviewReason.unsupportedLongInterval);
    }
    if (resetAfterBreak &&
        cycleLengths.length - selectedStart < minimumIntervalsAfterBreak) {
      return withhold(PredictionReviewReason.insufficientRecentHistory);
    }
    final selected = cycleLengths.sublist(selectedStart);
    final sorted = [...selected]..sort();
    if (sorted.last - sorted.first > maximumHistoricalRangeWidthDays) {
      return withhold(PredictionReviewReason.excessiveVariation);
    }
    final double estimate;
    switch (method) {
      case PeriodPredictionMethod.historicalMean:
        estimate = selected.reduce((a, b) => a + b) / selected.length;
      case PeriodPredictionMethod.recentMedian:
        estimate = _median(sorted);
      case PeriodPredictionMethod.recentWeightedMean:
        var numerator = 0;
        var denominator = 0;
        for (var i = 0; i < selected.length; i++) {
          numerator += selected[i] * (i + 1);
          denominator += i + 1;
        }
        estimate = numerator / denominator;
      case PeriodPredictionMethod.recentTrimmedMean:
        final central = sorted.length >= 5
            ? sorted.sublist(1, sorted.length - 1)
            : selected;
        estimate = central.reduce((a, b) => a + b) / central.length;
    }
    final expected = addCalendarDays(lastStart, estimate.round());
    return PeriodPrediction(
      status: calendarDayDifference(expected, now) < 0
          ? PeriodPredictionStatus.overdue
          : PeriodPredictionStatus.estimated,
      method: method,
      intervalCount: selected.length,
      totalIntervalCount: cycleLengths.length,
      excludedIntervalCount: selectedStart,
      reviewGaps: List.unmodifiable(gaps),
      expectedStart: expected,
      historicalRangeStart: selected.length < 2
          ? null
          : addCalendarDays(lastStart, sorted.first),
      historicalRangeEnd: selected.length < 2
          ? null
          : addCalendarDays(lastStart, sorted.last),
    );
  }

  static double _median(List<int> sorted) => sorted.length.isOdd
      ? sorted[sorted.length ~/ 2].toDouble()
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
}
