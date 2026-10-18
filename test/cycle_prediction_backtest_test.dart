import 'package:flutter_test/flutter_test.dart';

import '../scripts/backtest_cycle_predictions.dart';

import 'package:niswah/features/cycle_tracking/domain/entities/period_prediction.dart';

void main() {
  test('held-out changed cycle is never used to predict itself', () {
    final result = backtestHistories([
      [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 29),
        DateTime.utc(2026, 2, 26),
        DateTime.utc(2026, 3, 29),
      ],
    ]);
    expect(result['evaluatedPredictions'], 2);
    expect(result['meanAbsoluteErrorDays'], 1.5);
    expect(result['medianAbsoluteErrorDays'], 1.5);
    expect(result['fractionWithin1Day'], 0.5);
    expect(result['fractionWithin3Days'], 1.0);
    expect(result['predictionsWithHistoricalRange'], 1);
    expect(result['empiricalRangeCoverage'], 0.0);
    expect(result['meanHistoricalRangeWidthDays'], 0.0);
  });
  test(
    'candidate comparison does not automatically replace the shipping method',
    () {
      final result = comparePredictionMethods([
        [
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 29),
          DateTime.utc(2026, 2, 26),
          DateTime.utc(2026, 3, 29),
        ],
      ]);
      expect(result['shippingMethod'], 'historicalMean');
      expect(result['automaticPromotion'], isFalse);
      final models = result['models'] as Map;
      expect(
        models.keys,
        unorderedEquals(PeriodPredictionMethod.values.map((m) => m.name)),
      );
      for (final model in models.values) {
        expect((model as Map)['evaluatedPredictions'], 2);
        expect(model['predictionVersion'], PeriodPrediction.version);
      }
    },
  );
  test('no data produces no invented accuracy metric', () {
    final result = backtestHistories([]);
    expect(result['evaluatedPredictions'], 0);
    expect(result['meanAbsoluteErrorDays'], isNull);
    expect(result['fractionWithin3Days'], isNull);
    expect(result['predictionCoverage'], isNull);
  });
  test('unknown gap answers remain withheld rather than being invented for the benchmark', () {
    final result = backtestHistories([
      [
        DateTime.utc(2024, 1, 1),
        DateTime.utc(2024, 1, 29),
        DateTime.utc(2025, 1, 1),
        DateTime.utc(2025, 1, 29),
      ],
    ]);
    expect(result['eligibleTargets'], 2);
    expect(result['evaluatedPredictions'], 1);
    expect(result['withheldPredictions'], 1);
    expect(result['predictionCoverage'], .5);
    expect((result['withheldByReason'] as Map)['unexplainedGap'], 1);
    expect(result['reviewAnswersAvailable'], isFalse);
    // The very long held-out interval is scored; only the next forecast is
    // withheld after that gap has entered its training history.
    expect(result['meanAbsoluteErrorDays'], greaterThan(300));
  });
  test('a dubious training interval is counted as withheld, not silently collapsed', () {
    final result = backtestHistories([
      [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 2),
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 3, 1),
      ],
    ]);
    expect(result['evaluatedPredictions'], 0);
    expect(result['withheldPredictions'], 2);
    expect(result['meanAbsoluteErrorDays'], isNull);
  });
  test('duplicate or reversed starts fail rather than bias the score', () {
    final day = DateTime.utc(2026, 1, 1);
    expect(
      () => backtestHistories([
        [day, day],
      ]),
      throwsFormatException,
    );
    expect(
      () => backtestHistories([
        [day, day.subtract(const Duration(days: 1))],
      ]),
      throwsFormatException,
    );
  });
}
