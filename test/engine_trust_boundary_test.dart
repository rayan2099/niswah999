import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_evidence_adapter.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_status_engine.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

// Engineering safety scenarios, NOT independently reviewed religious answers.
void main() {
  final now = DateTime(2026, 10, 17, 12);
  const calculator = CycleCalculationService();
  const evaluator = MadhhabRuleEvaluator();

  CycleLog log(DateTime date, FlowLevel flow, {int day = 1}) => CycleLog(
    id: date.toIso8601String(),
    userId: 'synthetic',
    date: date,
    flow: flow,
    cycleDay: day,
  );

  test('one canonical episode cannot masquerade as several cycle starts', () {
    final observations = [
      for (var day = 10; day <= 17; day++)
        BleedingObservation(
          id: 'obs-$day',
          userId: 'synthetic',
          episodeId: 'one-episode',
          observedDate: DateTime(2026, 10, day),
          precision: ObservationPrecision.dateOnly,
          flow: ObservationFlow.medium,
          source: ObservationSource.userObserved,
          utcOffsetMinutes: 180,
        ),
    ];
    final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
      observations: observations.reversed.toList(),
    );
    final calculation = calculator.calculate(logs, asOf: now);
    expect(calculation.haidStarts, [DateTime(2026, 10, 10)]);
    expect(calculation.hasSufficientHistory, isFalse);
    expect(calculation.averageCycleLength, isNull);
    for (final madhhab in Madhhab.values) {
      final snapshot = const CycleStatusEngine().evaluate(
        logs: logs,
        calculation: calculation,
        madhhab: madhhab,
        now: now,
      );
      expect(snapshot.state, FiqhCycleState.insufficientHistory);
      expect(snapshot.daysIntoCurrentEpisode, 8);
    }
  });

  for (final madhhab in Madhhab.values) {
    test(
      '${madhhab.name}: unknown preceding purity cannot ground a ruling',
      () {
        final result = evaluator.evaluate(
          madhhab: madhhab,
          hasSufficientHistory: true,
          isBleeding: true,
          bleedingDuration: const Duration(days: 5),
          personalHabit: const Duration(days: 7),
        );
        expect(result.state, FiqhCycleState.needsAdvisory);
        expect(result.minimumOnlyPending, isFalse);
      },
    );
    test(
      '${madhhab.name}: short purity interval defers without a countdown',
      () {
        final minimum = MadhhabRuleEvaluator.minimumPurityFor(madhhab);
        final result = evaluator.evaluate(
          madhhab: madhhab,
          hasSufficientHistory: true,
          isBleeding: true,
          bleedingDuration: const Duration(hours: 1),
          purityBefore: minimum - const Duration(minutes: 1),
          personalHabit: const Duration(days: 5),
        );
        expect(result.state, FiqhCycleState.needsAdvisory);
        expect(result.minimumOnlyPending, isFalse);
      },
    );
  }

  test('Maliki missing habit and exceeded habit require review', () {
    for (final habit in <Duration?>[null, const Duration(days: 5)]) {
      final result = evaluator.evaluate(
        madhhab: Madhhab.maliki,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 9),
        purityBefore: const Duration(days: 20),
        personalHabit: habit,
      );
      expect(result.state, FiqhCycleState.needsAdvisory);
      expect(result.minimumOnlyPending, isFalse);
    }
  });

  test('negative duration can never be accepted as Maliki haid', () {
    final result = evaluator.evaluate(
      madhhab: Madhhab.maliki,
      hasSufficientHistory: true,
      isBleeding: true,
      bleedingDuration: const Duration(hours: -1),
      purityBefore: const Duration(days: 20),
      personalHabit: const Duration(days: 5),
    );
    expect(result.state, FiqhCycleState.needsAdvisory);
  });

  test('future starts do not leak into historical statistics', () {
    final logs = [
      log(DateTime(2026, 9, 1), FlowLevel.medium),
      log(DateTime(2026, 10, 1), FlowLevel.medium),
      log(DateTime(2026, 11, 1), FlowLevel.medium),
    ];
    final result = calculator.calculate(
      logs,
      asOf: now,
      canonicalEpisodes: [
        CanonicalEpisodeTiming(startDate: DateTime(2026, 12, 1)),
      ],
    );
    expect(result.cycleLengths, [30]);
    expect(result.lastHaidStart, DateTime(2026, 10, 1));
    final state = const CycleStatusEngine().evaluate(
      logs: logs,
      calculation: result,
      madhhab: Madhhab.hanafi,
      now: now,
    );
    expect(state.state, FiqhCycleState.insufficientHistory);
  });

  test(
    'an unclosed earlier episode does not inflate a later completed one',
    () {
      final result = calculator.calculate([
        log(DateTime(2026, 8, 1), FlowLevel.medium),
        log(DateTime(2026, 9, 1), FlowLevel.medium),
        log(DateTime(2026, 9, 6), FlowLevel.none),
      ], asOf: now);
      expect(result.averagePeriodLength, 5);
    },
  );

  test(
    'overdue summary withholds a new period and fertile-window estimate',
    () {
      final summary = const CycleTrackingController().summarizeHistory([
        log(DateTime(2026, 8, 1), FlowLevel.medium),
        log(DateTime(2026, 8, 29), FlowLevel.medium),
      ], now: now);
      expect(summary.averageCycleLength, 28);
      expect(summary.nextPeriodStart, isNull);
      expect(summary.fertileWindow.peakDay, isNull);
    },
  );

  test(
    'nonpositive cycle lengths fail immediately rather than loop forever',
    () {
      for (final length in [0, -28]) {
        expect(
          () => const CycleTrackingController().predictNextPeriodStart(
            cycleStart: now,
            averageCycleLength: length,
            now: now,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('due today stays due today at 11pm', () {
    final expected = const CycleTrackingController().predictNextPeriodStart(
      cycleStart: DateTime(2026, 9, 19),
      averageCycleLength: 28,
      now: DateTime(2026, 10, 17, 23),
    );
    expect(expected, DateTime(2026, 10, 17));
  });
}
