import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';

/// Regression for the onboarding-history -> legacy contradiction found by
/// the six-surface acceptance walkthrough: onboarding persists a real
/// canonical episode whose start observation is `flow = uncertain`
/// (never projected into cycle_entries — inventing a flow would be
/// fabrication), so Calendar/Insights told a returning woman with two
/// real starts to "log two cycle starts". The dates ARE safely
/// representable as timing facts.
void main() {
  const service = CycleCalculationService();
  final today = DateTime(2026, 8, 18);

  CycleLog startLog(DateTime date) => CycleLog(
    id: 'log-${date.toIso8601String()}',
    userId: 'u',
    date: date,
    flow: FlowLevel.medium,
    cycleDay: 1,
  );

  // What onboarding recorded: a real ended period 32 -> 27 days ago.
  final historical = CanonicalEpisodeTiming(
    startDate: today.subtract(const Duration(days: 32)),
    endDate: today.subtract(const Duration(days: 27)),
  );

  group('the contradiction, reproduced', () {
    test(
      'legacy logs alone see ONE start for an account with two real ones',
      () {
        final legacyOnly = service.calculate([startLog(today)], asOf: today);
        expect(legacyOnly.haidStarts, hasLength(1));
        expect(legacyOnly.hasSufficientHistory, isFalse);
        expect(legacyOnly.averageCycleLength, isNull);
      },
    );
  });

  group('with canonical episode timing supplied', () {
    test('the onboarding-reported period counts as a real start', () {
      final result = service.calculate(
        [startLog(today)],
        asOf: today,
        canonicalEpisodes: [historical],
      );
      expect(result.haidStarts, hasLength(2));
      expect(result.hasSufficientHistory, isTrue);
      expect(result.averageCycleLength, 32);
      expect(result.cycleLengths, [32]);
      expect(result.currentCycleDay, 1);
      expect(result.averagePeriodLength, 5);
    });

    test('an episode ALSO projected into logs is never double counted', () {
      final result = service.calculate(
        [startLog(today), startLog(today.subtract(const Duration(days: 32)))],
        asOf: today,
        canonicalEpisodes: [
          historical,
          CanonicalEpisodeTiming(startDate: today),
        ],
      );
      expect(result.haidStarts, hasLength(2));
      expect(result.cycleLengths, [32]);
    });

    test('a canonical start within 1 day of a logged start is the same '
        'episode and does not create a phantom second one', () {
      final result = service.calculate(
        [startLog(today)],
        asOf: today,
        canonicalEpisodes: [
          CanonicalEpisodeTiming(
            startDate: today.subtract(const Duration(days: 1)),
          ),
        ],
      );
      expect(result.haidStarts, hasLength(1));
    });

    test('the period length is not averaged twice when a log pairs it', () {
      final start = today.subtract(const Duration(days: 32));
      final logs = [
        startLog(start),
        CycleLog(
          id: 'end',
          userId: 'u',
          date: start.add(const Duration(days: 5)),
          flow: FlowLevel.none,
          cycleDay: 6,
        ),
        startLog(today),
      ];
      final result = service.calculate(
        logs,
        asOf: today,
        canonicalEpisodes: [historical],
      );
      expect(result.averagePeriodLength, 5);
      expect(result.haidStarts, hasLength(2));
    });

    test('one reported period alone is still honestly "not enough" — no '
        'invented second start, no fabricated cycle day', () {
      final result = service.calculate(
        const [],
        asOf: today,
        canonicalEpisodes: [historical],
      );
      expect(result.haidStarts, hasLength(1));
      expect(result.hasSufficientHistory, isFalse);
      expect(result.averageCycleLength, isNull);
      expect(result.currentCycleDay, isNull);
      // ...but the period she reported is known, and its length is real.
      expect(result.averagePeriodLength, 5);
    });

    test('an open (still-going) reported period is a start with no length', () {
      final result = service.calculate(
        const [],
        asOf: today,
        canonicalEpisodes: [CanonicalEpisodeTiming(startDate: today)],
      );
      expect(result.haidStarts, hasLength(1));
      expect(result.averagePeriodLength, isNull);
    });

    test('order of input never matters and duplicate episodes collapse', () {
      final a = service.calculate(
        [startLog(today)],
        asOf: today,
        canonicalEpisodes: [historical, historical],
      );
      final b = service.calculate(
        [startLog(today)],
        asOf: today,
        canonicalEpisodes: [historical],
      );
      expect(a.haidStarts, b.haidStarts);
      expect(a.cycleLengths, b.cycleLengths);
    });

    test('supplying no canonical episodes changes nothing (default)', () {
      final without = service.calculate([startLog(today)], asOf: today);
      final withEmpty = service.calculate(
        [startLog(today)],
        asOf: today,
        canonicalEpisodes: const [],
      );
      expect(withEmpty.haidStarts, without.haidStarts);
      expect(withEmpty.averageCycleLength, without.averageCycleLength);
    });
  });
}
