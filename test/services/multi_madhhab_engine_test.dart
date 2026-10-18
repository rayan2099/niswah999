import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

void main() {
  const calculator = CycleCalculationService();
  const evaluator = MadhhabRuleEvaluator();

  group('multi-Madhhab boundaries', () {
    final cases =
        <
          ({
            String name,
            Madhhab madhhab,
            Duration duration,
            FiqhCycleState expected,
          })
        >[
          (
            name: 'Hanafi rejects below 72h',
            madhhab: Madhhab.hanafi,
            duration: const Duration(hours: 71, minutes: 59),
            expected: FiqhCycleState.needsAdvisory,
          ),
          (
            name: 'Hanafi accepts exactly 72h',
            madhhab: Madhhab.hanafi,
            duration: const Duration(hours: 72),
            expected: FiqhCycleState.haid,
          ),
          (
            name: 'Hanafi accepts exactly 240h',
            madhhab: Madhhab.hanafi,
            duration: const Duration(hours: 240),
            expected: FiqhCycleState.haid,
          ),
          (
            name: 'Hanafi rejects above 240h',
            madhhab: Madhhab.hanafi,
            duration: const Duration(hours: 240, minutes: 1),
            expected: FiqhCycleState.needsAdvisory,
          ),
          for (final madhhab in [Madhhab.shafii, Madhhab.hanbali]) ...[
            (
              name: '${madhhab.name} rejects below cumulative 24h',
              madhhab: madhhab,
              duration: const Duration(hours: 23, minutes: 59),
              expected: FiqhCycleState.needsAdvisory,
            ),
            (
              name: '${madhhab.name} accepts exactly cumulative 24h',
              madhhab: madhhab,
              duration: const Duration(hours: 24),
              expected: FiqhCycleState.haid,
            ),
            (
              name: '${madhhab.name} accepts exactly 15 days',
              madhhab: madhhab,
              duration: const Duration(days: 15),
              expected: FiqhCycleState.haid,
            ),
            (
              name: '${madhhab.name} rejects above 15 days',
              madhhab: madhhab,
              duration: const Duration(days: 15, minutes: 1),
              expected: FiqhCycleState.needsAdvisory,
            ),
          ],
          // FD-7 (2026-10-15, evidence-based correction — see
          // FOUNDER_DECISIONS.md and ENGINE_TO_KB_ATOM_CROSSWALK.md):
          // Maliki has NO time-based minimum for Haid — unlike
          // Shafi'i/Hanbali above, which keep their real 24h minimum
          // (the `for` loop above is the regression proof that Maliki's
          // change did not leak into them). These boundary cases prove
          // the "no minimum" semantic directly: durations that would
          // fail every other madhhab's minimum must still be `haid` for
          // Maliki, all the way down to a single minute.
          (
            name: 'Maliki (FD-7 no minimum) accepts 1 minute of bleeding',
            madhhab: Madhhab.maliki,
            duration: const Duration(minutes: 1),
            expected: FiqhCycleState.haid,
          ),
          (
            name: 'Maliki (FD-7 no minimum) accepts 1 hour of bleeding',
            madhhab: Madhhab.maliki,
            duration: const Duration(hours: 1),
            expected: FiqhCycleState.haid,
          ),
          (
            name:
                'Maliki (FD-7 no minimum) accepts 23h59m — below every '
                'other madhhab\'s minimum, still haid for Maliki',
            madhhab: Madhhab.maliki,
            duration: const Duration(hours: 23, minutes: 59),
            expected: FiqhCycleState.haid,
          ),
          (
            name: 'Maliki accepts exactly 24h',
            madhhab: Madhhab.maliki,
            duration: const Duration(hours: 24),
            expected: FiqhCycleState.haid,
          ),
          (
            name: 'Maliki accepts exactly 15 days',
            madhhab: Madhhab.maliki,
            duration: const Duration(days: 15),
            expected: FiqhCycleState.haid,
          ),
          (
            name:
                'Maliki rejects above 15 days (maximum is unaffected by FD-7)',
            madhhab: Madhhab.maliki,
            duration: const Duration(days: 15, minutes: 1),
            expected: FiqhCycleState.needsAdvisory,
          ),
        ];

    for (final testCase in cases) {
      test(testCase.name, () {
        final result = evaluator.evaluate(
          madhhab: testCase.madhhab,
          hasSufficientHistory: true,
          isBleeding: true,
          bleedingDuration: testCase.duration,
          personalHabit: const Duration(days: 15),
          purityBefore: const Duration(days: 15),
        );
        expect(result.state, testCase.expected);
      });
    }

    test('Hanafi enforces the 15-day purity boundary', () {
      final below = evaluator.evaluate(
        madhhab: Madhhab.hanafi,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 5),
        purityBefore: const Duration(days: 14, hours: 23, minutes: 59),
      );
      final exact = evaluator.evaluate(
        madhhab: Madhhab.hanafi,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 3),
        purityBefore: const Duration(days: 15),
      );
      expect(below.state, FiqhCycleState.needsAdvisory);
      expect(exact.state, FiqhCycleState.haid);
    });
  });

  group('FD-7 (2026-10-15) — evidence-based per-madhhab corrections', () {
    test('minimumHaidFor is null only for Maliki — Hanafi/Shafi\'i/Hanbali '
        'keep their real minimum, unaffected', () {
      expect(MadhhabRuleEvaluator.minimumHaidFor(Madhhab.maliki), isNull);
      expect(
        MadhhabRuleEvaluator.minimumHaidFor(Madhhab.hanafi),
        const Duration(hours: 72),
      );
      expect(
        MadhhabRuleEvaluator.minimumHaidFor(Madhhab.shafii),
        const Duration(hours: 24),
      );
      expect(
        MadhhabRuleEvaluator.minimumHaidFor(Madhhab.hanbali),
        const Duration(hours: 24),
      );
    });

    test('minimumPurityFor is 13 days only for Hanbali — Hanafi/Maliki/'
        'Shafi\'i stay at 15 days, unaffected', () {
      expect(
        MadhhabRuleEvaluator.minimumPurityFor(Madhhab.hanbali),
        const Duration(days: 13),
      );
      expect(
        MadhhabRuleEvaluator.minimumPurityFor(Madhhab.hanafi),
        const Duration(days: 15),
      );
      expect(
        MadhhabRuleEvaluator.minimumPurityFor(Madhhab.maliki),
        const Duration(days: 15),
      );
      expect(
        MadhhabRuleEvaluator.minimumPurityFor(Madhhab.shafii),
        const Duration(days: 15),
      );
    });

    test('evaluate() result.minimumPurity reflects the per-madhhab value, '
        'not a single shared constant', () {
      final hanbali = evaluator.evaluate(
        madhhab: Madhhab.hanbali,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 3),
      );
      final hanafi = evaluator.evaluate(
        madhhab: Madhhab.hanafi,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 3),
      );
      expect(hanbali.minimumPurity, const Duration(days: 13));
      expect(hanafi.minimumPurity, const Duration(days: 15));
    });

    test('evaluate() result.minimumHaid is null for Maliki even when the '
        'resulting state is needsAdvisory (maximum-exceeded case) — proves '
        'the result struct itself carries the explicit "no minimum" '
        'semantic through, not just the classification decision', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.maliki,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 16),
      );
      expect(result.state, FiqhCycleState.needsAdvisory);
      expect(result.minimumHaid, isNull);
    });
  });

  test("Maliki preserves and evaluates the user's personal habit ('adah)", () {
    final withinHabit = evaluator.evaluate(
      madhhab: Madhhab.maliki,
      hasSufficientHistory: true,
      isBleeding: true,
      bleedingDuration: const Duration(days: 6),
      personalHabit: const Duration(days: 7),
    );
    final beyondHabit = evaluator.evaluate(
      madhhab: Madhhab.maliki,
      hasSufficientHistory: true,
      isBleeding: true,
      bleedingDuration: const Duration(days: 8),
      personalHabit: const Duration(days: 7),
    );
    expect(withinHabit.personalHabit, const Duration(days: 7));
    expect(withinHabit.isWithinPersonalHabit, isTrue);
    expect(beyondHabit.isWithinPersonalHabit, isFalse);
  });

  group('insufficient history', () {
    for (final madhhab in Madhhab.values) {
      test('${madhhab.name} remains insufficient with fewer than 2 starts', () {
        final logs = [_start('one', DateTime(2026, 8, 1))];
        final factual = calculator.calculate(logs, asOf: DateTime(2026, 8, 3));
        final ruled = evaluator.evaluate(
          madhhab: madhhab,
          hasSufficientHistory: factual.hasSufficientHistory,
          isBleeding: true,
          bleedingDuration: const Duration(days: 2),
        );
        expect(factual.currentCycleDay, isNull);
        expect(factual.averageCycleLength, isNull);
        expect(ruled.state, FiqhCycleState.insufficientHistory);
      });
    }
  });

  test('switching Madhhab changes validation without mutating raw logs', () {
    final logs = [
      _start('first', DateTime(2026, 7, 1)),
      _start('second', DateTime(2026, 8, 1)),
    ];
    final original = List<CycleLog>.of(logs);
    final factual = calculator.calculate(logs, asOf: DateTime(2026, 8, 3));

    final hanafi = evaluator.evaluate(
      madhhab: Madhhab.hanafi,
      hasSufficientHistory: factual.hasSufficientHistory,
      isBleeding: true,
      bleedingDuration: const Duration(hours: 48),
      purityBefore: const Duration(days: 20),
    );
    final shafii = evaluator.evaluate(
      madhhab: Madhhab.shafii,
      hasSufficientHistory: factual.hasSufficientHistory,
      isBleeding: true,
      bleedingDuration: const Duration(hours: 48),
      purityBefore: const Duration(days: 20),
    );

    expect(hanafi.state, FiqhCycleState.needsAdvisory);
    expect(shafii.state, FiqhCycleState.haid);
    expect(logs, orderedEquals(original));
  });
}

CycleLog _start(String id, DateTime date) => CycleLog(
  id: id,
  userId: 'test-user',
  date: date,
  flow: FlowLevel.medium,
  cycleDay: 1,
);
