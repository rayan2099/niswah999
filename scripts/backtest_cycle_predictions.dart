import 'dart:convert';
import 'dart:io';

import '../lib/core/utils/calendar_day.dart';
import '../lib/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import '../lib/features/cycle_tracking/domain/entities/cycle_log.dart';
import '../lib/features/cycle_tracking/domain/entities/period_prediction.dart';
import '../lib/features/cycle_tracking/domain/services/cycle_prediction_service.dart';

/// Rolling-origin evaluation of the real app predictor. Never pass a held-out
/// period to the calculation that predicts it. Input histories must come from
/// consented, de-identified data; synthetic runs are not clinical validation.
Map<String, Object?> backtestHistories(
  List<List<DateTime>> histories, {
  PeriodPredictionMethod method = PeriodPredictionMethod.historicalMean,
}) {
  final errors = <int>[];
  final historyMeanErrors = <double>[];
  final rangeWidths = <int>[];
  var rangeHits = 0;
  final errorsByHistorySize = <String, List<int>>{
    'oneInterval': [],
    'twoToFiveIntervals': [],
    'sixOrMoreIntervals': [],
  };
  var withheld = 0;
  final withheldReasons = <String, int>{};
  void recordWithheld(String reason) {
    withheld++;
    withheldReasons.update(reason, (n) => n + 1, ifAbsent: () => 1);
  }

  var shortHistories = 0;
  for (final starts in histories) {
    final historyErrors = <int>[];
    for (var i = 1; i < starts.length; i++) {
      if (calendarDayDifference(starts[i], starts[i - 1]) <= 0) {
        throw const FormatException(
          'Histories must contain strictly ordered unique dates',
        );
      }
    }
    if (starts.length < 3) shortHistories++;
    for (var target = 2; target < starts.length; target++) {
      // Do not let the legacy log adapter silently collapse a dubious
      // one-day "cycle" and make a training history look cleaner than it is.
      var prefixNeedsReview = false;
      for (var i = 1; i < target; i++) {
        if (calendarDayDifference(starts[i], starts[i - 1]) <
            CyclePredictionService.minimumUsableIntervalDays)
          prefixNeedsReview = true;
      }
      if (prefixNeedsReview) {
        recordWithheld(PredictionReviewReason.invalidHistory.name);
        continue;
      }
      final training = [
        for (var i = 0; i < target; i++)
          CycleLog(
            id: '$i',
            userId: 'deidentified',
            date: starts[i],
            flow: FlowLevel.medium,
            cycleDay: 1,
          ),
      ];
      final summary = const CycleTrackingController().summarizeHistory(
        training,
        now: starts[target - 1],
        predictionMethod: method,
      );
      final prediction = summary.nextPeriodStart;
      if (prediction == null) {
        recordWithheld(
          summary.periodPrediction.reviewReason?.name ??
              summary.periodPrediction.status.name,
        );
      } else {
        final error = calendarDayDifference(prediction, starts[target]).abs();
        errors.add(error);
        historyErrors.add(error);
        final bucket = target - 1 == 1
            ? 'oneInterval'
            : target - 1 < 6
            ? 'twoToFiveIntervals'
            : 'sixOrMoreIntervals';
        errorsByHistorySize[bucket]!.add(error);
        final details = summary.periodPrediction;
        if (details.hasHistoricalRange) {
          rangeWidths.add(
            calendarDayDifference(
              details.historicalRangeEnd!,
              details.historicalRangeStart!,
            ),
          );
          if (calendarDayDifference(
                    starts[target],
                    details.historicalRangeStart!,
                  ) >=
                  0 &&
              calendarDayDifference(
                    details.historicalRangeEnd!,
                    starts[target],
                  ) >=
                  0)
            rangeHits++;
        }
      }
    }
    if (historyErrors.isNotEmpty) {
      historyMeanErrors.add(
        historyErrors.reduce((a, b) => a + b) / historyErrors.length,
      );
    }
  }
  final sorted = [...errors]..sort();
  final n = sorted.length;
  double? within(int days) =>
      n == 0 ? null : sorted.where((e) => e <= days).length / n;
  return {
    'method': method.name,
    'predictionVersion': PeriodPrediction.version,
    'histories': histories.length,
    'historiesWithFewerThanThreeStarts': shortHistories,
    'evaluatedPredictions': n,
    'withheldPredictions': withheld,
    'eligibleTargets': n + withheld,
    'predictionCoverage': n + withheld == 0 ? null : n / (n + withheld),
    'withheldByReason': withheldReasons,
    'reviewAnswersAvailable': false,
    'meanAbsoluteErrorDays': n == 0 ? null : sorted.reduce((a, b) => a + b) / n,
    'medianAbsoluteErrorDays': n == 0
        ? null
        : n.isOdd
        ? sorted[n ~/ 2].toDouble()
        : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2,
    'fractionWithin1Day': within(1),
    'fractionWithin3Days': within(3),
    'fractionWithin7Days': within(7),
    'historyWeightedMeanAbsoluteErrorDays': historyMeanErrors.isEmpty
        ? null
        : historyMeanErrors.reduce((a, b) => a + b) / historyMeanErrors.length,
    'predictionsWithHistoricalRange': rangeWidths.length,
    'empiricalRangeCoverage': rangeWidths.isEmpty
        ? null
        : rangeHits / rangeWidths.length,
    'meanHistoricalRangeWidthDays': rangeWidths.isEmpty
        ? null
        : rangeWidths.reduce((a, b) => a + b) / rangeWidths.length,
    'byAvailableHistory': errorsByHistorySize.map(
      (key, values) => MapEntry(key, {
        'evaluatedPredictions': values.length,
        'meanAbsoluteErrorDays': values.isEmpty
            ? null
            : values.reduce((a, b) => a + b) / values.length,
      }),
    ),
    'scope': 'Period-start estimates only; not ovulation validation or clinical certification',
  };
}

Map<String, Object?> comparePredictionMethods(List<List<DateTime>> histories) =>
    {
      'shippingMethod': PeriodPredictionMethod.historicalMean.name,
      'automaticPromotion': false,
      'models': {
        for (final method in PeriodPredictionMethod.values)
          method.name: backtestHistories(histories, method: method),
      },
    };

void main(List<String> args) {
  final compare = args.length == 2 && args.first == '--compare';
  if (args.length != 1 && !compare) {
    stderr.writeln(
      'Usage: dart run scripts/backtest_cycle_predictions.dart [--compare] <histories.json>',
    );
    exitCode = 64;
    return;
  }
  try {
    final data = jsonDecode(File(args.last).readAsStringSync()) as List;
    final histories = data
        .map(
          (raw) => (raw as List).map((value) {
            if (value is! String ||
                !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
              throw const FormatException('Use YYYY-MM-DD dates only');
            }
            final parsed = DateTime.parse('${value}T00:00:00Z');
            if (parsed.toIso8601String().substring(0, 10) != value) {
              throw const FormatException('Invalid calendar date');
            }
            return parsed;
          }).toList(),
        )
        .toList();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(
        compare
            ? comparePredictionMethods(histories)
            : backtestHistories(histories),
      ),
    );
  } catch (_) {
    // Do not echo a health-history input or filename into a diagnostic log.
    stderr.writeln(
      'Invalid input. Supply an array of strictly ordered date arrays.',
    );
    exitCode = 65;
  }
}
