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

  CycleLog ended(String id, DateTime date) => CycleLog(
    id: id,
    userId: 'user',
    date: date,
    flow: FlowLevel.none,
  );

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

  test(
    'currently bleeding: daysIntoCurrentEpisode is real, grounded data',
    () {
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
    },
  );

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

  test(
    'insufficient history despite currently bleeding: state falls back to '
    'tahara and daysIntoCurrentEpisode must NOT leak through — otherwise '
    'state and daysIntoCurrentEpisode would disagree the same way this fix '
    'exists to prevent',
    () {
      final logs = [bleeding('only-start', DateTime(2026, 3, 1))];
      final now = DateTime(2026, 3, 3);

      final snapshot = evaluate(logs, now);

      expect(snapshot.state, FiqhCycleState.tahara);
      expect(snapshot.daysIntoCurrentEpisode, isNull);
      expect(snapshot.cycleDayEstimate, isNull);
      expect(snapshot.averagePeriodLength, isNull);
    },
  );
}
