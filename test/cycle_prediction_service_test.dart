import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_day.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/prediction_history_review.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/period_prediction.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_prediction_service.dart';

void main() {
  const service = CyclePredictionService();
  final start = DateTime(2026, 10, 1);

  test('missing history has no invented dates or sample size', () {
    final prediction = service.predict(
      lastStart: null,
      cycleLengths: [],
      now: start,
    );
    expect(prediction.status, PeriodPredictionStatus.insufficientHistory);
    expect(prediction.expectedStart, isNull);
    expect(prediction.intervalCount, 0);
    expect(prediction.hasHistoricalRange, isFalse);
  });
  test('one interval supports a limited estimate, not a variation range', () {
    final prediction = service.predict(
      lastStart: start,
      cycleLengths: [28],
      now: start,
    );
    expect(prediction.expectedStart, DateTime(2026, 10, 29));
    expect(prediction.intervalCount, 1);
    expect(prediction.hasHistoricalRange, isFalse);
  });
  test('the historical range reflects recorded minimum and maximum', () {
    final prediction = service.predict(
      lastStart: start,
      cycleLengths: [27, 31, 29],
      now: start,
    );
    expect(prediction.expectedStart, DateTime(2026, 10, 30));
    expect(prediction.historicalRangeStart, DateTime(2026, 10, 28));
    expect(prediction.historicalRangeEnd, DateTime(2026, 11, 1));
    expect(prediction.intervalCount, 3);
    expect(prediction.method, PeriodPredictionMethod.historicalMean);
  });
  test('identical past intervals do not get an invented confidence margin', () {
    final prediction = service.predict(
      lastStart: start,
      cycleLengths: [28, 28],
      now: start,
    );
    expect(prediction.historicalRangeStart, prediction.historicalRangeEnd);
    expect(prediction.intervalCount, 2);
  });
  test(
    'overdue retains the original estimate without rolling another cycle',
    () {
      final prediction = service.predict(
        lastStart: start,
        cycleLengths: [28, 30],
        now: DateTime(2026, 12, 1),
      );
      expect(prediction.status, PeriodPredictionStatus.overdue);
      expect(prediction.hasFutureEstimate, isFalse);
      expect(prediction.expectedStart, DateTime(2026, 10, 30));
      expect(prediction.historicalRangeEnd, DateTime(2026, 10, 31));
    },
  );
  test('due today remains estimated at 11pm', () {
    final prediction = service.predict(
      lastStart: start,
      cycleLengths: [28],
      now: DateTime(2026, 10, 29, 23),
    );
    expect(prediction.status, PeriodPredictionStatus.estimated);
  });
  test('future start or unverified history withholds all dates', () {
    for (final prediction in [
      service.predict(
        lastStart: start,
        cycleLengths: [28],
        now: DateTime(2026, 9, 1),
      ),
      service.predict(
        lastStart: start,
        cycleLengths: [28],
        now: start,
        historyVerified: false,
      ),
    ]) {
      expect(prediction.status, PeriodPredictionStatus.historyNeedsReview);
      expect(prediction.expectedStart, isNull);
      expect(prediction.hasHistoricalRange, isFalse);
    }
  });
  for (final invalid in [-1, 0, 14]) {
    test('interval $invalid cannot be hidden by an otherwise usable mean', () {
      final prediction = service.predict(
        lastStart: start,
        cycleLengths: [28, invalid, 32],
        now: start,
      );
      expect(prediction.status, PeriodPredictionStatus.historyNeedsReview);
      expect(prediction.expectedStart, isNull);
    });
  }
  test(
    'each candidate uses its specified formula and leaves inputs intact',
    () {
      final lengths = [27, 27, 45, 28];
      final expected = {
        PeriodPredictionMethod.historicalMean: 32,
        PeriodPredictionMethod.recentMedian: 28,
        PeriodPredictionMethod.recentWeightedMean: 33,
        PeriodPredictionMethod.recentTrimmedMean: 32,
      };
      for (final method in PeriodPredictionMethod.values) {
        final prediction = service.predict(
          lastStart: start,
          cycleLengths: lengths,
          now: start,
          method: method,
        );
        expect(
          calendarDayDifference(prediction.expectedStart!, start),
          expected[method],
        );
        expect(lengths, [27, 27, 45, 28]);
      }
    },
  );
  test('recency methods disclose both selected and full history counts', () {
    final prediction = service.predict(
      lastStart: start,
      cycleLengths: [100, 26, 27, 28, 29, 30, 31],
      now: start,
      method: PeriodPredictionMethod.recentMedian,
    );
    expect(prediction.intervalCount, 6);
    expect(prediction.totalIntervalCount, 7);
    expect(calendarDayDifference(prediction.expectedStart!, start), 29);
    expect(calendarDayDifference(prediction.historicalRangeStart!, start), 26);
  });
  PredictionHistoryReview answer(
    List<int> lengths,
    int index,
    PredictionGapResolution resolution, {
    DateTime? reportedAt,
    int shift = 0,
  }) {
    var end = start;
    for (var i = lengths.length - 1; i > index; i--) {
      end = addCalendarDays(end, -lengths[i]);
    }
    return PredictionHistoryReview(
      start: addCalendarDays(end, -lengths[index] + shift),
      end: end,
      resolution: resolution,
      reportedAt: reportedAt ?? start.toUtc(),
    );
  }

  test('a decades-long gap cannot become a forecast or a broad range', () {
    final result = service.predict(
      lastStart: start,
      cycleLengths: [28, 18000, 29],
      now: start,
    );
    expect(result.reviewReason, PredictionReviewReason.unexplainedGap);
    expect(result.expectedStart, isNull);
    expect(result.hasHistoricalRange, isFalse);
    expect(result.reviewGaps.single.days, 18000);
  });
  test('a gap relative to the person also needs review below the hard cap', () {
    final result = service.predict(
      lastStart: start,
      cycleLengths: [28, 28, 28, 60],
      now: start,
    );
    expect(result.reviewReason, PredictionReviewReason.unexplainedGap);
    expect(result.reviewGaps.single.days, 60);
  });
  for (final resolution in [
    PredictionGapResolution.missedRecords,
    PredictionGapResolution.unsure,
  ]) {
    test(
      '$resolution restarts from actual subsequent starts without inventing periods',
      () {
        final lengths = [28, 28, 28, 200, 28, 29];
        final result = service.predict(
          lastStart: start,
          cycleLengths: lengths,
          now: start,
          historyReviews: [answer(lengths, 3, resolution)],
        );
        expect(result.status, PeriodPredictionStatus.estimated);
        expect(result.intervalCount, 2);
        expect(result.totalIntervalCount, 6);
        expect(result.excludedIntervalCount, 4);
        expect(result.expectedStart, addCalendarDays(start, 29));
        expect(
          calendarDayDifference(
            result.historicalRangeEnd!,
            result.historicalRangeStart!,
          ),
          1,
        );
        expect(lengths, [28, 28, 28, 200, 28, 29]);
      },
    );
  }
  test('one interval after a reviewed break is insufficient to restart', () {
    final lengths = [28, 200, 29];
    final result = service.predict(
      lastStart: start,
      cycleLengths: lengths,
      now: start,
      historyReviews: [
        answer(lengths, 1, PredictionGapResolution.missedRecords),
      ],
    );
    expect(
      result.reviewReason,
      PredictionReviewReason.insufficientRecentHistory,
    );
    expect(result.expectedStart, isNull);
  });
  test(
    'confirmed longer cycles are preserved but cannot override support limits',
    () {
      final lengths = [28, 200, 29];
      final result = service.predict(
        lastStart: start,
        cycleLengths: lengths,
        now: start,
        historyReviews: [
          answer(lengths, 1, PredictionGapResolution.longerCycle),
        ],
      );
      expect(
        result.reviewReason,
        PredictionReviewReason.unsupportedLongInterval,
      );
      expect(result.expectedStart, isNull);
    },
  );
  test('a supported longer-cycle answer does not bypass wide variation', () {
    final lengths = [28, 28, 28, 60];
    final result = service.predict(
      lastStart: start,
      cycleLengths: lengths,
      now: start,
      historyReviews: [answer(lengths, 3, PredictionGapResolution.longerCycle)],
    );
    expect(result.reviewReason, PredictionReviewReason.excessiveVariation);
  });
  test('an edited endpoint invalidates an earlier answer', () {
    final lengths = [28, 200, 29, 28];
    final result = service.predict(
      lastStart: start,
      cycleLengths: lengths,
      now: start,
      historyReviews: [
        answer(lengths, 1, PredictionGapResolution.missedRecords, shift: 1),
      ],
    );
    expect(result.reviewReason, PredictionReviewReason.unexplainedGap);
  });
  test('future answers cannot leak into a historical prediction', () {
    final lengths = [28, 200, 29, 28];
    final result = service.predict(
      lastStart: start,
      cycleLengths: lengths,
      now: start,
      historyReviews: [
        answer(
          lengths,
          1,
          PredictionGapResolution.missedRecords,
          reportedAt: addCalendarDays(start.toUtc(), 1),
        ),
      ],
    );
    expect(result.reviewReason, PredictionReviewReason.unexplainedGap);
  });
  test(
    'current average uses recent records and discloses excluded history',
    () {
      final result = service.predict(
        lastStart: start,
        cycleLengths: [18000, 28, 28, 28, 28, 28, 28],
        now: start,
      );
      expect(result.expectedStart, addCalendarDays(start, 28));
      expect(result.intervalCount, 6);
      expect(result.excludedIntervalCount, 1);
      expect(result.method, PeriodPredictionMethod.historicalMean);
    },
  );
  test(
    'wide variation withholds a date instead of displaying a huge range',
    () {
      final result = service.predict(
        lastStart: start,
        cycleLengths: [20, 45],
        now: start,
      );
      expect(result.reviewReason, PredictionReviewReason.excessiveVariation);
      expect(result.hasHistoricalRange, isFalse);
      expect(result.expectedStart, isNull);
    },
  );
  test('stale history withholds even the previous point and range', () {
    final result = service.predict(
      lastStart: start,
      cycleLengths: [28, 29],
      now: addCalendarDays(start, 91),
    );
    expect(result.reviewReason, PredictionReviewReason.staleHistory);
    expect(result.expectedStart, isNull);
    expect(result.hasHistoricalRange, isFalse);
  });
  test('reviews serialize dates, answers and UTC reporting time exactly', () {
    final review = answer([28, 200, 29], 1, PredictionGapResolution.unsure);
    final decoded = PredictionHistoryReview.fromJson(review.toJson());
    expect(decoded.key, review.key);
    expect(decoded.resolution, review.resolution);
    expect(decoded.reportedAt, review.reportedAt);
    final malformed = {...review.toJson(), 'start': '2026-02-30'};
    expect(
      () => PredictionHistoryReview.fromJson(malformed),
      throwsFormatException,
    );
    expect(
      () => PredictionHistoryReview.fromJson({
        ...review.toJson(),
        'resolution': 'normal',
      }),
      throwsArgumentError,
    );
  });
  test('trimmed candidate changes only its estimator, never the observed range or raw intervals', () {
    final lengths = [25, 27, 28, 29, 30, 40];
    final candidate = service.predict(
      lastStart: start,
      cycleLengths: lengths,
      now: start,
      method: PeriodPredictionMethod.recentTrimmedMean,
    );
    final baseline = service.predict(
      lastStart: start,
      cycleLengths: lengths,
      now: start,
    );
    expect(calendarDayDifference(candidate.expectedStart!, start), 29);
    expect(calendarDayDifference(baseline.expectedStart!, start), 30);
    expect(candidate.intervalCount, 6);
    expect(candidate.historicalRangeStart, addCalendarDays(start, 25));
    expect(candidate.historicalRangeEnd, addCalendarDays(start, 40));
    expect(lengths, [25, 27, 28, 29, 30, 40]);
    expect(baseline.method, PeriodPredictionMethod.historicalMean);
  });
  test(
    'trimmed candidate falls back to mean for fewer than five intervals',
    () {
      final candidate = service.predict(
        lastStart: start,
        cycleLengths: [25, 27, 28, 40],
        now: start,
        method: PeriodPredictionMethod.recentTrimmedMean,
      );
      expect(calendarDayDifference(candidate.expectedStart!, start), 30);
      expect(candidate.intervalCount, 4);
    },
  );
}
