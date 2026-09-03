import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_segment_planner.dart';

void main() {
  const planner = CycleSegmentPlanner();
  final cycleStart = DateTime(2026, 1, 1);

  test(
    'reproduces the reference design\'s exact segment durations '
    '(5/4/7/8/3/1, summing to a 28-day cycle)',
    () {
      final plan = planner.plan(
        cycleLength: 28,
        periodLength: 5,
        fertileWindow: FertileWindow(
          start: cycleStart.add(const Duration(days: 9)),
          end: cycleStart.add(const Duration(days: 15)),
          peakDay: cycleStart.add(const Duration(days: 12)),
        ),
        cycleStart: cycleStart,
        isBleedingNow: true,
        cycleDayEstimate: 1,
      );

      final durations = {
        for (final segment in plan.segments) segment.id: segment.durationDays,
      };
      expect(durations[CycleSegmentId.haid], 5);
      expect(durations[CycleSegmentId.tahara1], 4);
      expect(durations[CycleSegmentId.fertile], 7);
      expect(durations[CycleSegmentId.tahara2], 8);
      expect(durations[CycleSegmentId.prePeriod], 3);
      expect(durations[CycleSegmentId.expected], 1);
      expect(
        durations.values.reduce((a, b) => a + b),
        28,
        reason: 'segments must partition the full cycle length',
      );
    },
  );

  test('filters out a zero-duration segment instead of showing it as 0', () {
    final plan = planner.plan(
      cycleLength: 20,
      periodLength: 5,
      // Fertile window starts immediately after the period ends, so
      // tahara1 has nothing to span.
      fertileWindow: FertileWindow(
        start: cycleStart.add(const Duration(days: 5)),
        end: cycleStart.add(const Duration(days: 10)),
        peakDay: cycleStart.add(const Duration(days: 8)),
      ),
      cycleStart: cycleStart,
      isBleedingNow: true,
      cycleDayEstimate: 1,
    );

    expect(
      plan.segments.any((segment) => segment.id == CycleSegmentId.tahara1),
      isFalse,
      reason: 'a zero-duration segment must be absent, not present-with-0',
    );
  });

  test(
    'the guarantee: real fiqh state always wins over statistical '
    'day-position — Haid stays active even when cycleDayEstimate lands '
    'inside the fertile window',
    () {
      final plan = planner.plan(
        cycleLength: 28,
        periodLength: 5,
        fertileWindow: FertileWindow(
          start: cycleStart.add(const Duration(days: 9)),
          end: cycleStart.add(const Duration(days: 15)),
          peakDay: cycleStart.add(const Duration(days: 12)),
        ),
        cycleStart: cycleStart,
        isBleedingNow: true,
        // Statistically this would land inside the fertile window
        // (day-offset 12, well within 10-16) — but she's actually still
        // bleeding, so Haid must remain "current" regardless.
        cycleDayEstimate: 12,
      );

      expect(plan.active?.id, CycleSegmentId.haid);
    },
  );

  test(
    'disambiguates tahara1 vs tahara2 by cycleDayEstimate when not '
    'bleeding',
    () {
      FertileWindow fertileWindow() => FertileWindow(
        start: cycleStart.add(const Duration(days: 9)),
        end: cycleStart.add(const Duration(days: 15)),
        peakDay: cycleStart.add(const Duration(days: 12)),
      );

      final beforeFertile = planner.plan(
        cycleLength: 28,
        periodLength: 5,
        fertileWindow: fertileWindow(),
        cycleStart: cycleStart,
        isBleedingNow: false,
        cycleDayEstimate: 7, // within tahara1's 6-9 span
      );
      expect(beforeFertile.active?.id, CycleSegmentId.tahara1);

      final afterFertile = planner.plan(
        cycleLength: 28,
        periodLength: 5,
        fertileWindow: fertileWindow(),
        cycleStart: cycleStart,
        isBleedingNow: false,
        cycleDayEstimate: 20, // within tahara2's 17-24 span
      );
      expect(afterFertile.active?.id, CycleSegmentId.tahara2);

      final atBoundary = planner.plan(
        cycleLength: 28,
        periodLength: 5,
        fertileWindow: fertileWindow(),
        cycleStart: cycleStart,
        isBleedingNow: false,
        cycleDayEstimate: 17, // exactly tahara2's first day
      );
      expect(atBoundary.active?.id, CycleSegmentId.tahara2);
    },
  );
}
