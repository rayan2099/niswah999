import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';

void main() {
  const service = CycleCalculationService();

  CycleLog start(String id, DateTime date) => CycleLog(
    id: id,
    userId: 'user',
    date: date,
    flow: FlowLevel.medium,
    cycleDay: 1,
  );

  CycleLog end(String id, DateTime date) => CycleLog(
    id: id,
    userId: 'user',
    date: date,
    flow: FlowLevel.none,
  );

  test('does not fabricate values with fewer than two Haid starts', () {
    final empty = service.calculate(const []);
    final oneStart = service.calculate([start('one', DateTime(2026, 1, 1))]);

    expect(empty.hasSufficientHistory, isFalse);
    expect(empty.currentCycleDay, isNull);
    expect(empty.averageCycleLength, isNull);
    expect(oneStart.hasSufficientHistory, isFalse);
    expect(oneStart.currentCycleDay, isNull);
    expect(oneStart.averageCycleLength, isNull);
    expect(empty.averagePeriodLength, isNull);
    expect(oneStart.averagePeriodLength, isNull);
  });

  test('derives cycle length and day from stored Haid starts', () {
    final result = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 1, 31)),
    ], asOf: DateTime(2026, 2, 5));

    expect(result.hasSufficientHistory, isTrue);
    expect(result.averageCycleLength, 30);
    expect(result.currentCycleDay, 6);
    expect(result.lastHaidStart, DateTime(2026, 1, 31));
    expect(
      result.averagePeriodLength,
      isNull,
      reason: 'no logged end was ever paired with a start',
    );
  });

  test(
    'hasPlausibleAverage is false for a degenerate few-days-apart average '
    'even though hasSufficientHistory is already true',
    () {
      final result = service.calculate([
        start('first', DateTime(2026, 1, 1)),
        start('second', DateTime(2026, 1, 3)),
      ], asOf: DateTime(2026, 1, 4));

      expect(result.hasSufficientHistory, isTrue);
      expect(result.averageCycleLength, 2);
      expect(
        result.hasPlausibleAverage,
        isFalse,
        reason: 'a 2-day average cycle length is not a real menstrual cycle',
      );
    },
  );

  test('hasPlausibleAverage is true for a realistic average cycle length', () {
    final result = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 1, 31)),
    ], asOf: DateTime(2026, 2, 5));

    expect(result.hasSufficientHistory, isTrue);
    expect(result.hasPlausibleAverage, isTrue);
  });

  test('computes average period length from completed start+end pairs', () {
    final onePair = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      end('first-end', DateTime(2026, 1, 6)),
    ], asOf: DateTime(2026, 1, 10));
    expect(onePair.averagePeriodLength, 5);

    final twoPairs = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      end('first-end', DateTime(2026, 1, 6)),
      start('second', DateTime(2026, 2, 1)),
      end('second-end', DateTime(2026, 2, 8)),
    ], asOf: DateTime(2026, 2, 10));
    expect(twoPairs.averagePeriodLength, 6);
  });

  test('does not fabricate a period length for an episode still in progress', () {
    final stillBleeding = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      end('first-end', DateTime(2026, 1, 6)),
      start('second', DateTime(2026, 2, 1)),
    ], asOf: DateTime(2026, 2, 3));

    expect(stillBleeding.averagePeriodLength, 5);
  });

  test('averages every observed per-instance interval without clamping', () {
    final result = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 2, 10)),
      start('third', DateTime(2026, 3, 12)),
    ], asOf: DateTime(2026, 3, 12));

    expect(result.averageCycleLength, 35);
  });

  test('cycleLengths is populated in oldest-to-newest order', () {
    final result = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 1, 29)),
      start('third', DateTime(2026, 2, 26)),
      start('fourth', DateTime(2026, 3, 28)),
    ], asOf: DateTime(2026, 4, 1));

    expect(result.cycleLengths, [28, 28, 30]);
  });

  test('hasRegularityData requires one more logged cycle than the average',
      () {
    expect(service.calculate(const []).hasRegularityData, isFalse);
    expect(
      service.calculate([
        start('one', DateTime(2026, 1, 1)),
      ]).hasRegularityData,
      isFalse,
    );

    final oneInterval = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 1, 31)),
    ], asOf: DateTime(2026, 2, 5));
    expect(
      oneInterval.hasSufficientHistory,
      isTrue,
      reason: 'average length only needs one interval',
    );
    expect(
      oneInterval.hasRegularityData,
      isFalse,
      reason: 'variance needs at least two intervals to mean anything',
    );

    final twoIntervals = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 2, 10)),
      start('third', DateTime(2026, 3, 12)),
    ], asOf: DateTime(2026, 3, 12));
    expect(twoIntervals.hasRegularityData, isTrue);
  });

  test('regularity is insufficientData when hasRegularityData is false', () {
    final oneInterval = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 1, 31)),
    ], asOf: DateTime(2026, 2, 5));

    expect(oneInterval.regularityScore, isNull);
    expect(oneInterval.regularity, CycleRegularity.insufficientData);
  });

  test('a tight cluster of cycle lengths is highly regular', () {
    final result = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 1, 29)),
      start('third', DateTime(2026, 2, 26)),
      start('fourth', DateTime(2026, 3, 26)),
    ], asOf: DateTime(2026, 4, 1));

    expect(result.cycleLengths, [28, 28, 28]);
    expect(result.regularityScore, 1.0);
    expect(result.regularity, CycleRegularity.highlyRegular);
    expect(
      result.cycleLengths.every(result.isCycleLengthWithinNormalRange),
      isTrue,
      reason: 'zero deviation from the mean is always within range',
    );
  });

  test('a wide spread of cycle lengths is irregular', () {
    final result = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 2, 10)),
      start('third', DateTime(2026, 2, 25)),
      start('fourth', DateTime(2026, 4, 1)),
    ], asOf: DateTime(2026, 4, 1));

    expect(result.cycleLengths, [40, 15, 35]);
    expect(result.regularityScore, 0.0);
    expect(result.regularity, CycleRegularity.irregular);
    expect(
      result.isCycleLengthWithinNormalRange(15),
      isFalse,
      reason: 'furthest from the mean of 30',
    );
    expect(
      result.isCycleLengthWithinNormalRange(40),
      isTrue,
      reason: 'per-marker classification is not all-or-nothing',
    );
  });

  test(
    'a repeated cycleDay == 1 log while still bleeding does not start a '
    'new episode',
    () {
      final result = service.calculate([
        start('first', DateTime(2026, 1, 1)),
        // Still bleeding, no Tahara logged in between — a re-tap/correction
        // of the same start, not a second distinct episode. Without the
        // fix this produces a bogus 1-day interval.
        start('duplicate-relog', DateTime(2026, 1, 2)),
        end('first-end', DateTime(2026, 1, 6)),
        start('second', DateTime(2026, 1, 29)),
      ], asOf: DateTime(2026, 2, 5));

      expect(
        result.haidStarts,
        [DateTime(2026, 1, 1), DateTime(2026, 1, 29)],
        reason:
            'the duplicate cycleDay 1 re-log must not count as its own '
            'episode start',
      );
      expect(result.cycleLengths, [28]);
      expect(result.averageCycleLength, 28);
    },
  );

  test(
    'a new start shortly after a logged end still counts as a separate '
    'episode',
    () {
      // Guards against over-correcting the fix above into merging every
      // short interval — a genuine end (Tahara) was logged first, so this
      // is a real new episode regardless of how soon it follows.
      final result = service.calculate([
        start('first', DateTime(2026, 1, 1)),
        end('first-end', DateTime(2026, 1, 6)),
        start('second', DateTime(2026, 1, 8)),
      ], asOf: DateTime(2026, 1, 10));

      expect(result.haidStarts, [DateTime(2026, 1, 1), DateTime(2026, 1, 8)]);
      expect(result.cycleLengths, [7]);
    },
  );

  test('regularity math is not clamped or filtered for outliers', () {
    final result = service.calculate([
      start('first', DateTime(2026, 1, 1)),
      start('second', DateTime(2026, 1, 29)),
      start('third', DateTime(2026, 2, 26)),
      start('fourth', DateTime(2026, 5, 27)),
    ], asOf: DateTime(2026, 5, 27));

    // Raw, unclamped intervals: 28, 28, 90 — the 90-day outlier is kept, not
    // excluded, so the mean absolute deviation is large enough to floor the
    // score at 0 rather than landing on some filtered/clamped value.
    expect(result.cycleLengths, [28, 28, 90]);
    expect(result.regularityScore, 0.0);
    expect(result.regularity, CycleRegularity.irregular);
  });

  group('computeCycleDayForNewEntry', () {
    test(
      'three consecutive daily logs of the same period get 1, 2, 3 — not '
      'all 1',
      () {
        // Day 1: no prior history at all.
        final day1 = service.computeCycleDayForNewEntry(
          existingLogs: const [],
          date: DateTime(2026, 3, 1),
          flow: FlowLevel.medium,
        );
        expect(day1, 1);

        // Day 2: yesterday's log (correctly saved as cycleDay 1) is already
        // in history — this must continue the same episode, not restart it.
        final loggedDay1 = start('d1', DateTime(2026, 3, 1));
        final day2 = service.computeCycleDayForNewEntry(
          existingLogs: [loggedDay1],
          date: DateTime(2026, 3, 2),
          flow: FlowLevel.medium,
        );
        expect(day2, 2);

        final loggedDay2 = loggedDay1.copyWith(
          id: 'd2',
          date: DateTime(2026, 3, 2),
          cycleDay: 2,
        );
        final day3 = service.computeCycleDayForNewEntry(
          existingLogs: [loggedDay1, loggedDay2],
          date: DateTime(2026, 3, 3),
          flow: FlowLevel.medium,
        );
        expect(day3, 3);
      },
    );

    test('a new bleeding log after a gap starts a fresh episode at day 1', () {
      final priorEpisode = [
        start('first', DateTime(2026, 1, 1)),
        end('first-end', DateTime(2026, 1, 6)),
      ];

      final cycleDay = service.computeCycleDayForNewEntry(
        existingLogs: priorEpisode,
        date: DateTime(2026, 1, 29),
        flow: FlowLevel.light,
      );

      expect(cycleDay, 1);
    });

    test(
      'backfilling a date in the middle of history uses the episode active '
      'on that date, not the most recent one',
      () {
        final logs = [
          start('first', DateTime(2026, 1, 1)),
          start('second', DateTime(2026, 1, 29)),
        ];

        // Backfilling Jan 5th (5 days into the first episode) must not be
        // computed relative to the Jan 29 start, which is chronologically
        // later than the date being backfilled.
        final cycleDay = service.computeCycleDayForNewEntry(
          existingLogs: logs,
          date: DateTime(2026, 1, 5),
          flow: FlowLevel.spotting,
        );

        expect(cycleDay, 5);
      },
    );
  });
}
