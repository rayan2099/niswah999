// Round-2 focused regressions for the prediction / calendar invariant
// violations found by the property suites in this folder (R2-4..R2-8,
// R2-6b), each a minimal (shrunk) history. Fixed on
// fix/round2-prediction-properties; the fiqh regressions R2-1..R2-3 live in
// fiqh_regressions_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_segment_planner.dart';

import 'support/synthetic_history.dart';

const _m = ObservationFlow.medium;

void main() {
  test('R2-4 no next-period range once she is past the late tolerance', () {
    // Intervals 20, 34, 22, 36 (all kept): predicted 29 days, spread ~7.0,
    // so the late tolerance is capped at 10 while ceil(1.5 x spread) is 11.
    // Found by P2b; rebuilt for the leave-one-out missed-log rule (#7),
    // which changed the original shrunk history's prediction.
    final logs = [
      for (final d in [
        DateTime(2025, 1, 1),
        DateTime(2025, 1, 21),
        DateTime(2025, 2, 24),
        DateTime(2025, 3, 18),
        DateTime(2025, 4, 23),
      ]) ...[
        CycleLog(id: 's$d', userId: 'u', date: d, flow: FlowLevel.medium),
        CycleLog(
          id: 'e$d',
          userId: 'u',
          date: addCalendarDays(d, 1),
          flow: FlowLevel.none,
          cycleDay: 2,
        ),
      ],
    ];
    final s = const CycleTrackingController().summarizeHistory(
      logs,
      now: DateTime(2025, 6, 2),
    );
    expect(s.predictedCycleLength, 29);
    expect(s.daysLate, 11);
    expect(s.nextPeriodStart, isNull); // "late by 11 days", no date
    expect(
      s.nextPeriodRange,
      isNull,
      reason:
          'range ${ymd(s.nextPeriodRange?.earliest)}..'
          '${ymd(s.nextPeriodRange?.latest)} still offered',
    );
    // On the last tolerated day the range still ends exactly there.
    final onTime = const CycleTrackingController().summarizeHistory(
      logs,
      now: DateTime(2025, 5, 22),
    );
    expect(ymd(onTime.nextPeriodRange?.latest), '2025-06-01');
  });

  test('R2-5 fertile window never starts before the cycle start', () {
    final logs = [
      CycleLog(
        id: 'a',
        userId: 'u',
        date: DateTime(2024, 12, 26),
        flow: FlowLevel.medium,
      ),
      CycleLog(
        id: 'b',
        userId: 'u',
        date: DateTime(2024, 12, 27),
        flow: FlowLevel.none,
        cycleDay: 2,
      ),
      CycleLog(
        id: 'c',
        userId: 'u',
        date: DateTime(2025, 1, 16),
        flow: FlowLevel.medium,
      ),
      CycleLog(
        id: 'd',
        userId: 'u',
        date: DateTime(2025, 1, 17),
        flow: FlowLevel.none,
        cycleDay: 2,
      ),
    ];
    final s = const CycleTrackingController().summarizeHistory(
      logs,
      now: DateTime(2025, 1, 16),
    );
    expect(s.predictedCycleLength, 21);
    expect(s.fertileWindow.start, isNotNull);
    expect(
      s.fertileWindow.start!.isBefore(DateTime(2025, 1, 16)),
      isFalse,
      reason: 'fertile window starts ${ymd(s.fertileWindow.start)}',
    );
  });

  test('R2-6 one episode supplied as canonical timing + its flat '
      'projection is counted once (uncertain start day, next day missing)', () {
    // Onboarding: "my period started 2026-05-01 and is ongoing" (flow
    // uncertain), first check-in on 05-03.
    final h = SynthHistory(
      kind: 'R2-6',
      seed: 160019,
      anchor: DateTime(2026, 5, 1),
      episodes: const [
        SynthEpisode(
          start: 0,
          flows: [ObservationFlow.uncertain, _m, _m, _m],
          skipped: {1},
          ended: false,
        ),
      ],
    );
    final ev = evidenceAsOf(h, 3);
    final calc = const CycleCalculationService().calculate(
      ev.flatLogs,
      asOf: h.day(3),
      canonicalEpisodes: ev.timing,
    );
    expect(calc.haidStarts.map(ymd), [
      '2026-05-01',
    ], reason: 'one period counted as cycles ${calc.cycleLengths}');
    expect(calc.hasSufficientHistory, isFalse);
  });

  test('R2-6b canonical start is not moved a day later by its own '
      'projection', () {
    final h = SynthHistory(
      kind: 'R2-6b',
      seed: 160033,
      anchor: DateTime(2024, 11, 20),
      episodes: const [
        SynthEpisode(start: 0, flows: [ObservationFlow.uncertain, _m]),
      ],
    );
    final ev = evidenceAsOf(h, 1);
    final calc = const CycleCalculationService().calculate(
      ev.flatLogs,
      asOf: h.day(1),
      canonicalEpisodes: ev.timing,
    );
    expect(calc.haidStarts.map(ymd), ['2024-11-20']);
  });

  test('R2-7 one missed period does not shift the prediction by weeks', () {
    // Regular 35-day cycles; the second period was never logged.
    final with3 = CycleCalculationService.predictFromIntervals([35, 35, 35]);
    final missed = CycleCalculationService.predictFromIntervals([70, 35]);
    expect(with3!.length, 35);
    expect(
      (missed!.length - 35).abs(),
      lessThanOrEqualTo(3),
      reason: 'predicted ${missed.length}',
    );
  });

  test('R2-8 segment plan never overlaps when the period outlasts the '
      'fertile window', () {
    final start = DateTime(2026, 5, 31);
    final plan = const CycleSegmentPlanner().plan(
      cycleLength: 26,
      periodLength: 15,
      fertileWindow: FertileWindow(
        start: DateTime(2026, 6, 7),
        end: DateTime(2026, 6, 13),
        peakDay: DateTime(2026, 6, 12),
      ),
      cycleStart: start,
      isBleedingNow: false,
      cycleDayEstimate: 20,
    );
    expect(
      plan.totalDays,
      26,
      reason: plan.segments
          .map((s) => '${s.id.name}:${s.durationDays}')
          .join(' '),
    );
  });
}
