import 'package:flutter_test/flutter_test.dart';

import '../scripts/export_cycle_evaluation_folds.dart';

void main() {
  test('actual runtime candidate predictions are computed from the same full prefix', () {
    final result = buildCycleEvaluationFolds([
      ['2026-01-01', '2026-01-29', '2026-02-26', '2026-03-29'],
    ]);
    final histories = result['histories'] as List;
    final records = (histories.single as Map)['folds'] as List;
    expect((records.last as Map)['runtimeCandidateDays'], {
      'currentMean6': 28,
      'median6': 28,
      'trimmedMean6': 28,
    });
  });
  List<Map> folds(Map result, [int history = 0]) =>
      (((result['histories'] as List)[history] as Map)['folds'] as List)
          .cast<Map>();

  test(
    'held-out target changes scoring only, never its own prediction inputs',
    () {
      final data = [
        ['2026-01-01', '2026-01-29', '2026-02-26', '2026-03-29'],
      ];
      final first = buildCycleEvaluationFolds(data);
      final changed = buildCycleEvaluationFolds([
        ['2026-01-01', '2026-01-29', '2026-02-26', '2026-06-01'],
      ]);
      final a = Map.of(folds(first).last)..remove('actualDays');
      final b = Map.of(folds(changed).last)..remove('actualDays');
      expect(a, b);
      expect(folds(first).first, folds(changed).first);
      expect(folds(first).last['actualDays'], 31);
      expect(data.single.last, '2026-03-29');
    },
  );
  test(
    'a long future target is scored and later becomes a withheld training gap',
    () {
      final result = buildCycleEvaluationFolds([
        ['2024-01-01', '2024-01-29', '2025-01-01', '2025-01-29'],
      ]);
      expect(result['evaluatedPredictions'], 1);
      expect(result['withheldPredictions'], 1);
      expect(folds(result).first['actualDays'] as int, greaterThan(300));
      expect(folds(result).last['reason'], 'unexplainedGap');
      expect(folds(result).last.containsKey('actualDays'), isFalse);
    },
  );
  test('same declared participant fragments stay grouped and identifiers are not exported', () {
    final result = buildCycleEvaluationFolds({
      'histories': [
        {
          'group': 'private-participant-key',
          'starts': ['2020-01-01', '2020-01-29', '2020-02-26'],
        },
        {
          'group': 'private-participant-key',
          'starts': ['2021-01-01', '2021-01-29', '2021-02-26'],
        },
      ],
    });
    expect(result['groups'], 1);
    final rows = result['histories'] as List;
    expect((rows.first as Map)['group'], (rows.last as Map)['group']);
    expect(result.toString().contains('private-participant-key'), isFalse);
    expect(result.toString().contains('2020-01-01'), isFalse);
  });
  test('overlapping fragments cannot duplicate one persons outcomes', () {
    expect(
      () => buildCycleEvaluationFolds({
        'histories': [
          {
            'group': 'same',
            'starts': ['2020-01-01', '2020-01-29', '2020-02-26'],
          },
          {
            'group': 'same',
            'starts': ['2020-01-29', '2020-02-26', '2020-03-25'],
          },
        ],
      }),
      throwsFormatException,
    );
  });
  test('questionable short starts remain withheld instead of silently deduplicated', () {
    final result = buildCycleEvaluationFolds([
      ['2026-01-01', '2026-01-02', '2026-02-01', '2026-03-01'],
    ]);
    expect(result['evaluatedPredictions'], 0);
    expect(result['withheldPredictions'], 2);
    expect(result['withheldByReason'], {'invalidHistory': 2});
  });
  test('invalid civil dates, duplicate dates and backwards history fail', () {
    for (final history in [
      ['2026-02-30'],
      ['2026-01-01', '2026-01-01'],
      ['2026-01-29', '2026-01-01'],
    ]) {
      expect(() => buildCycleEvaluationFolds([history]), throwsFormatException);
    }
  });
  test('old outliers never enter the selected recent features', () {
    final result = buildCycleEvaluationFolds([
      [
        '1900-01-01',
        '2026-01-01',
        '2026-01-29',
        '2026-02-26',
        '2026-03-26',
        '2026-04-23',
        '2026-05-21',
        '2026-06-18',
        '2026-07-16',
      ],
    ]);
    expect(folds(result).last['priorIntervals'], [28, 28, 28, 28, 28, 28]);
    expect(folds(result).last['baselineDays'], 28);
  });
}
