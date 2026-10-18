import 'package:equatable/equatable.dart';

import 'prediction_history_review.dart';

enum PeriodPredictionMethod {
  historicalMean,
  recentMedian,
  recentWeightedMean,
  // Research candidate only; never selected automatically for a user.
  recentTrimmedMean,
}

enum PeriodPredictionStatus {
  insufficientHistory,
  historyNeedsReview,
  estimated,
  overdue,
}

enum PredictionReviewReason {
  unverifiedHistory,
  invalidHistory,
  unexplainedGap,
  insufficientRecentHistory,
  excessiveVariation,
  unsupportedLongInterval,
  staleHistory,
}

/// An estimate from recorded biological cycle intervals, never a fiqh state.
/// The range is the observed minimum/maximum interval projected once from the
/// last start. It is NOT a calibrated prediction/confidence interval.
class PeriodPrediction extends Equatable {
  const PeriodPrediction({
    required this.status,
    this.method = PeriodPredictionMethod.historicalMean,
    this.intervalCount = 0,
    this.totalIntervalCount = 0,
    this.expectedStart,
    this.historicalRangeStart,
    this.historicalRangeEnd,
    this.reviewReason,
    this.reviewGaps = const [],
    this.excludedIntervalCount = 0,
  });

  final PeriodPredictionStatus status;
  final PeriodPredictionMethod method;
  final int intervalCount;
  final int totalIntervalCount;
  final DateTime? expectedStart;
  final DateTime? historicalRangeStart;
  final DateTime? historicalRangeEnd;
  final PredictionReviewReason? reviewReason;
  final List<PredictionHistoryGap> reviewGaps;
  final int excludedIntervalCount;
  static const version = 'cycle-prediction-v2-history-review-2026-10-17';

  bool get hasFutureEstimate => status == PeriodPredictionStatus.estimated;
  bool get hasHistoricalRange =>
      historicalRangeStart != null && historicalRangeEnd != null;

  @override
  List<Object?> get props => [
    status,
    method,
    intervalCount,
    totalIntervalCount,
    expectedStart,
    historicalRangeStart,
    historicalRangeEnd,
    reviewReason,
    reviewGaps.map((g) => [g.key, g.resolution]).toList(),
    excludedIntervalCount,
  ];
}
