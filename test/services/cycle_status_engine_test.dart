import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_status_engine.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

void main() {
  const calculationService = CycleCalculationService();
  const engine = CycleStatusEngine();

  CycleLog bleeding(String id, DateTime date, {int cycleDay = 1}) => CycleLog(
    id: id,
    userId: 'user',
    date: date,
    flow: FlowLevel.medium,
    cycleDay: cycleDay,
  );

  CycleLog ended(String id, DateTime date) =>
      CycleLog(id: id, userId: 'user', date: date, flow: FlowLevel.none);

  CycleStatusSnapshot evaluate(List<CycleLog> logs, DateTime now) {
    final calculation = calculationService.calculate(logs, asOf: now);
    return engine.evaluate(
      logs: logs,
      calculation: calculation,
      madhhab: Madhhab.shafii,
      now: now,
    );
  }

  test('empty history is tahara with no episode day', () {
    final snapshot = evaluate(const [], DateTime(2026, 1, 1));

    expect(snapshot.state, FiqhCycleState.tahara);
    expect(snapshot.daysIntoCurrentEpisode, isNull);
    expect(snapshot.cycleDayEstimate, isNull);
  });

  test(
    'the exact bug this fix closes: cycleDayEstimate stays stale after the '
    'period actually ended, but daysIntoCurrentEpisode correctly goes null',
    () {
      final logs = [
        bleeding('e1-start', DateTime(2026, 1, 1)),
        ended('e1-end', DateTime(2026, 1, 5)),
        bleeding('e2-start', DateTime(2026, 2, 1)),
        ended('e2-end', DateTime(2026, 2, 5)),
      ];
      final now = DateTime(2026, 2, 10);

      final snapshot = evaluate(logs, now);

      expect(snapshot.state, FiqhCycleState.tahara);
      expect(
        snapshot.daysIntoCurrentEpisode,
        isNull,
        reason: 'no bleeding is happening right now — this must be null',
      );
      expect(
        snapshot.cycleDayEstimate,
        10,
        reason:
            'the flow-blind statistical estimate keeps counting from the '
            'last recorded start regardless of the period having ended — '
            'this is the exact divergence that produced the reported bug, '
            'and it must remain legitimately different from '
            'daysIntoCurrentEpisode, never silently unified into one wrong '
            'number',
      );
      expect(snapshot.averagePeriodLength, 4);
    },
  );

  test('currently bleeding: daysIntoCurrentEpisode is real, grounded data', () {
    final logs = [
      bleeding('e1-start', DateTime(2026, 1, 1)),
      ended('e1-end', DateTime(2026, 1, 6)),
      bleeding('e2-start', DateTime(2026, 2, 1)),
      bleeding('e2-day2', DateTime(2026, 2, 2), cycleDay: 2),
      bleeding('e2-day3', DateTime(2026, 2, 3), cycleDay: 3),
    ];
    final now = DateTime(2026, 2, 3);

    final snapshot = evaluate(logs, now);

    expect(snapshot.state, FiqhCycleState.haid);
    expect(snapshot.daysIntoCurrentEpisode, 3);
    expect(snapshot.averagePeriodLength, 5);
  });

  test(
    'needsAdvisory: daysIntoCurrentEpisode and confirmAt are both populated',
    () {
      final logs = [
        bleeding('e1-start', DateTime(2026, 1, 1)),
        ended('e1-end', DateTime(2026, 1, 6)),
        bleeding('e2-start', DateTime(2026, 2, 1)),
      ];
      // Shafii's minimum haid duration is 24 hours — a few hours in is
      // still "needs advisory", not yet confirmed haid.
      final now = DateTime(2026, 2, 1, 6);

      final snapshot = evaluate(logs, now);

      expect(snapshot.state, FiqhCycleState.needsAdvisory);
      expect(snapshot.daysIntoCurrentEpisode, isNotNull);
      expect(snapshot.confirmAt, DateTime(2026, 2, 2));
    },
  );

  test('insufficient history despite currently bleeding: state falls back to '
      'tahara and daysIntoCurrentEpisode must NOT leak through — otherwise '
      'state and daysIntoCurrentEpisode would disagree the same way this fix '
      'exists to prevent', () {
    final logs = [bleeding('only-start', DateTime(2026, 3, 1))];
    final now = DateTime(2026, 3, 3);

    final snapshot = evaluate(logs, now);

    expect(snapshot.state, FiqhCycleState.tahara);
    expect(snapshot.daysIntoCurrentEpisode, isNull);
    expect(snapshot.cycleDayEstimate, isNull);
    expect(snapshot.averagePeriodLength, isNull);
  });

  group('Fiqh Remediation Wave 1 (Section E/P) — no madhhab SELECTED', () {
    CycleStatusSnapshot evaluateWithMadhhab(
      List<CycleLog> logs,
      DateTime now,
      Madhhab? madhhab,
    ) {
      final calculation = calculationService.calculate(logs, asOf: now);
      return engine.evaluate(
        logs: logs,
        calculation: calculation,
        madhhab: madhhab,
        now: now,
      );
    }

    test('UNSET/UNKNOWN case (null madhhab): currently bleeding never returns '
        'haid/needsAdvisory — returns madhhabUnresolved instead, never a '
        'silently-guessed classification', () {
      final logs = [
        bleeding('e1-start', DateTime(2026, 1, 1)),
        bleeding('e1-day2', DateTime(2026, 1, 2), cycleDay: 2),
      ];
      final now = DateTime(2026, 1, 2);

      final snapshot = evaluateWithMadhhab(logs, now, null);

      expect(snapshot.state, FiqhCycleState.madhhabUnresolved);
      expect(
        snapshot.state,
        isNot(FiqhCycleState.haid),
        reason: 'never silently resolves to a specific state',
      );
      expect(
        snapshot.state,
        isNot(FiqhCycleState.tahara),
        reason:
            'a currently-bleeding user must never be shown as pure — that '
            'would be false precision, not merely an unhelpful default',
      );
      // The daysIntoCurrentEpisode data itself is real/grounded and safe
      // to show once she selects a madhhab — it is not the fiqh ruling
      // itself, only real elapsed-time data.
      expect(snapshot.daysIntoCurrentEpisode, 2);
    });

    test('null madhhab + not currently bleeding: still correctly tahara — a '
        'null madhhab never blocks a determination that holds regardless of '
        'madhhab', () {
      final logs = [
        bleeding('e1-start', DateTime(2026, 1, 1)),
        ended('e1-end', DateTime(2026, 1, 5)),
      ];
      final now = DateTime(2026, 1, 10);

      final snapshot = evaluateWithMadhhab(logs, now, null);

      expect(snapshot.state, FiqhCycleState.tahara);
    });

    test('switching from null (unresolved) to a real madhhab, same facts, now '
        'produces a real classification — proves the gate is genuinely a '
        'missing-input gate, not a permanently broken state', () {
      // Two complete prior episodes (matching the sufficient-history
      // pattern used elsewhere in this file) so the classification below
      // isn't itself short-circuited to insufficientHistory/tahara for
      // an unrelated reason.
      final logs = [
        bleeding('e1-start', DateTime(2026, 1, 1)),
        ended('e1-end', DateTime(2026, 1, 6)),
        bleeding('e2-start', DateTime(2026, 2, 1)),
        bleeding('e2-day2', DateTime(2026, 2, 2), cycleDay: 2),
      ];
      final now = DateTime(2026, 2, 2);

      final unresolved = evaluateWithMadhhab(logs, now, null);
      // Bleeding since Feb 1 00:00, evaluated at Feb 2 00:00 = exactly
      // 24h — Shafi'i's minimum haid duration, so this is a real `haid`
      // classification once a madhhab is actually supplied.
      final resolved = evaluateWithMadhhab(logs, now, Madhhab.shafii);

      expect(unresolved.state, FiqhCycleState.madhhabUnresolved);
      expect(resolved.state, FiqhCycleState.haid);
    });
  });
}
