import 'dart:convert';
import 'dart:io';

import '../lib/core/utils/calendar_day.dart';
import '../lib/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import '../lib/features/cycle_tracking/domain/entities/cycle_log.dart';
import '../lib/features/cycle_tracking/domain/entities/period_prediction.dart';
import '../lib/features/cycle_tracking/domain/services/cycle_prediction_service.dart';

/// Research-only, minimized fold data. Never write the output into Git.
/// Future target lengths are attached only AFTER the actual app has predicted.
Map<String, Object?> buildCycleEvaluationFolds(Object? input) {
  final bool suppliedGroups = input is Map;
  final List rows;
  if (suppliedGroups) {
    rows = input['histories'] as List;
  } else {
    rows = input as List;
  }
  final groups = <String, int>{};
  final groupSpans = <int, List<({DateTime first, DateTime last})>>{};
  final histories = <Map<String, Object?>>[];
  var eligible = 0;
  var withheld = 0;
  final reasons = <String, int>{};
  for (var h = 0; h < rows.length; h++) {
    final row = rows[h];
    final String groupKey;
    final List rawDates;
    if (suppliedGroups) {
      final mapped = row as Map;
      groupKey = mapped['group'] as String;
      if (groupKey.isEmpty) throw const FormatException('Missing group');
      rawDates = mapped['starts'] as List;
    } else {
      groupKey = 'source-$h';
      rawDates = row as List;
    }
    final group = groups.putIfAbsent(groupKey, () => groups.length);
    final starts = rawDates.map((raw) {
      if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
        throw const FormatException('Use civil dates');
      }
      final date = DateTime.parse('${raw}T00:00:00Z');
      if (date.toIso8601String().substring(0, 10) != raw) {
        throw const FormatException('Invalid date');
      }
      return date;
    }).toList();
    for (var i = 1; i < starts.length; i++) {
      if (calendarDayDifference(starts[i], starts[i - 1]) <= 0) {
        throw const FormatException('Unordered starts');
      }
    }
    if (starts.isNotEmpty) {
      final spans = groupSpans.putIfAbsent(group, () => []);
      for (final span in spans) {
        if (!starts.last.isBefore(span.first) &&
            !starts.first.isAfter(span.last)) {
          throw const FormatException('Overlapping histories in one group');
        }
      }
      spans.add((first: starts.first, last: starts.last));
    }
    final folds = <Map<String, Object?>>[];
    var shortPrefix = false;
    for (var target = 2; target < starts.length; target++) {
      if (calendarDayDifference(starts[target - 1], starts[target - 2]) <
          CyclePredictionService.minimumUsableIntervalDays) {
        shortPrefix = true;
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
      final summary = shortPrefix
          ? null
          : const CycleTrackingController().summarizeHistory(
              training,
              now: starts[target - 1],
            );
      if (summary?.nextPeriodStart == null) {
        final reason = shortPrefix
            ? PredictionReviewReason.invalidHistory.name
            : summary!.periodPrediction.reviewReason?.name ??
                  summary.periodPrediction.status.name;
        reasons.update(reason, (n) => n + 1, ifAbsent: () => 1);
        withheld++;
        folds.add({'targetIndex': target, 'eligible': false, 'reason': reason});
        continue;
      }
      final count = summary!.periodPrediction.intervalCount;
      final selected = [
        for (var i = target - count; i < target; i++)
          calendarDayDifference(starts[i], starts[i - 1]),
      ];
      final baseline = calendarDayDifference(
        summary.nextPeriodStart!,
        starts[target - 1],
      );
      if (selected.isEmpty ||
          selected.length > 6 ||
          (selected.reduce((a, b) => a + b) / selected.length).round() !=
              baseline) {
        throw StateError('Baseline no longer matches frozen research protocol');
      }
      // The target is used for scoring only, never passed to the controller.
      final runtimeCandidates = <String, int>{'currentMean6': baseline};
      for (final entry in {
        'median6': PeriodPredictionMethod.recentMedian,
        'trimmedMean6': PeriodPredictionMethod.recentTrimmedMean,
      }.entries) {
        final candidate = const CycleTrackingController().summarizeHistory(
          training,
          now: starts[target - 1],
          predictionMethod: entry.value,
        );
        if (candidate.nextPeriodStart == null) {
          throw StateError('Candidate changed frozen forecast coverage');
        }
        runtimeCandidates[entry.key] = calendarDayDifference(
          candidate.nextPeriodStart!,
          starts[target - 1],
        );
      }
      final actual = calendarDayDifference(starts[target], starts[target - 1]);
      folds.add({
        'targetIndex': target,
        'eligible': true,
        'priorIntervals': selected,
        'baselineDays': baseline,
        'runtimeCandidateDays': runtimeCandidates,
        'actualDays': actual,
      });
      eligible++;
    }
    histories.add({'group': group, 'folds': folds});
  }
  return {
    'schemaVersion': 1,
    'predictionVersion': PeriodPrediction.version,
    'groupingAssurance': suppliedGroups
        ? 'Caller-supplied grouping; participant identity not independently audited'
        : 'Source history only; not proof of unique participants',
    'sourceHistories': histories.length,
    'groups': groups.length,
    'eligibleTargets': eligible + withheld,
    'evaluatedPredictions': eligible,
    'withheldPredictions': withheld,
    'withheldByReason': reasons,
    'reviewAnswersAvailable': false,
    'histories': histories,
  };
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run scripts/export_cycle_evaluation_folds.dart <external-histories.json> <external-folds.json>',
    );
    exitCode = 64;
    return;
  }
  try {
    final output = File(args.last).absolute;
    output.parent.createSync(recursive: true);
    final root = Directory.fromUri(Platform.script.resolve('..'))
        .resolveSymbolicLinksSync();
    final parent = output.parent.resolveSymbolicLinksSync();
    final destination = output.existsSync()
        ? output.resolveSymbolicLinksSync()
        : '${parent}/${output.uri.pathSegments.last}';
    if (parent == root ||
        parent.startsWith('$root/') ||
        destination.startsWith('$root/')) {
      throw const FormatException('Keep research health records outside Git');
    }
    final result = buildCycleEvaluationFolds(
      jsonDecode(File(args.first).readAsStringSync()),
    );
    output.writeAsStringSync(jsonEncode(result));
    stdout.writeln(
      jsonEncode({
        for (final entry in result.entries)
          if (entry.key != 'histories') entry.key: entry.value,
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Export failed. Check ordered dates, grouping, baseline version and an output location outside Git. No health records were printed.',
    );
    exitCode = 65;
  }
}
