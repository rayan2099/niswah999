import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/core/utils/calendar_day.dart';

void main() {
  group('CycleTrackingController', () {
    test('period, phase and fertile projections share recent eligible history while averages stay factual', () {
      final last = DateTime(2026, 10, 1);
      var date = last;
      final starts = [last];
      for (final length in [28, 28, 28, 28, 28, 28, 18000]) {
        date = addCalendarDays(date, -length);
        starts.insert(0, date);
      }
      final result = const CycleTrackingController().summarizeHistory(
        const [],
        now: addCalendarDays(last, 14),
        canonicalEpisodes: [
          for (final d in starts)
            CanonicalEpisodeTiming(
              startDate: d,
              endDate: addCalendarDays(d, 5),
            ),
        ],
      );
      expect(result.averageCycleLength, greaterThan(90));
      expect(result.nextPeriodStart, addCalendarDays(last, 28));
      expect(result.fertileWindow.peakDay, addCalendarDays(last, 14));
      expect(result.currentPhase, CyclePhase.ovulation);
      expect(result.periodPrediction.intervalCount, 6);
    });
    test('calculates the current phase from a cycle start', () {
      final baseDate = DateTime(2026, 8, 1);
      final phase = CycleTrackingController().calculatePhase(
        date: baseDate.add(const Duration(days: 4)),
        cycleStart: baseDate,
        averageCycleLength: 28,
      );

      expect(phase, CyclePhase.menstrual);
    });

    test('builds a fertile window using the 14-day luteal-phase heuristic '
        '(ovulation = predicted next period minus 14 days)', () {
      final cycleStart = DateTime(2026, 8, 1);
      final window = CycleTrackingController().calculateFertileWindow(
        cycleStart: cycleStart,
        averageCycleLength: 28,
        now: cycleStart,
      );

      // predictedNextPeriodStart = Aug 1 + 28 days = Aug 29
      // ovulationDay = Aug 29 - 14 days = Aug 15
      expect(window.peakDay, equals(DateTime(2026, 8, 15)));
      expect(window.start != null && window.end != null, isTrue);
      expect(window.start!.isBefore(window.end!), isTrue);
      expect(window.start!.day, equals(10));
      expect(window.end!.day, equals(16));
    });

    test('overdue estimates never invent another cycle or fertile window', () {
      final controller = CycleTrackingController();
      final start = DateTime(2026, 8, 1);
      final now = DateTime(2026, 8, 30);
      expect(
        controller.predictNextPeriodStart(
          cycleStart: start,
          averageCycleLength: 28,
          now: now,
        ),
        DateTime(2026, 8, 29),
      );
      final window = controller.calculateFertileWindow(
        cycleStart: start,
        averageCycleLength: 28,
        now: now,
      );
      expect(window.peakDay, isNull);
      expect(window.start, isNull);
      expect(window.end, isNull);
    });

    test('predictNextPeriodStart leaves a projection landing exactly on "now" '
        'alone — due today is not overdue', () {
      final cycleStart = DateTime(2026, 8, 1);
      final naiveNextPeriod = DateTime(2026, 8, 29);

      final next = CycleTrackingController().predictNextPeriodStart(
        cycleStart: cycleStart,
        averageCycleLength: 28,
        now: naiveNextPeriod,
      );

      expect(next, equals(naiveNextPeriod));
    });

    test('summarizes historical cycle tracking data', () {
      final logs = [
        CycleLog(
          id: '1',
          userId: 'user_1',
          date: DateTime(2026, 7, 1),
          flow: FlowLevel.light,
          notes: 'period started',
          cycleDay: 1,
        ),
        CycleLog(
          id: '2',
          userId: 'user_1',
          date: DateTime(2026, 7, 6),
          flow: FlowLevel.none,
          notes: 'cycle continued',
          cycleDay: 6,
        ),
        CycleLog(
          id: '3',
          userId: 'user_1',
          date: DateTime(2026, 8, 1),
          flow: FlowLevel.medium,
          notes: 'next period',
          cycleDay: 1,
        ),
      ];

      final summary = CycleTrackingController().summarizeHistory(logs);

      expect(summary.averageCycleLength, equals(31));
      expect(summary.averagePeriodLength, equals(5));
      expect(summary.lastCycleStart, equals(DateTime(2026, 8, 1)));
      expect(summary.hasPlausibleAverage, isTrue);
    });

    test('summarizeHistory withholds forward predictions for a degenerate '
        '(implausibly short) average cycle length, without hiding the '
        'reported average itself', () {
      final logs = [
        CycleLog(
          id: '1',
          userId: 'user_1',
          date: DateTime(2026, 8, 1),
          flow: FlowLevel.medium,
          cycleDay: 1,
        ),
        CycleLog(
          id: '2',
          userId: 'user_1',
          date: DateTime(2026, 8, 3),
          flow: FlowLevel.medium,
          cycleDay: 1,
        ),
      ];

      final summary = CycleTrackingController().summarizeHistory(
        logs,
        now: DateTime(2026, 8, 4),
      );

      expect(summary.averageCycleLength, equals(2));
      expect(
        summary.nextPeriodStart,
        isNull,
        reason: 'a 2-day average is too implausible to predict from',
      );
      expect(summary.fertileWindow.peakDay, isNull);
      expect(
        summary.hasPlausibleAverage,
        isFalse,
        reason:
            'lets consumers like the calendar gate their own projections '
            '(e.g. a repeating "Expected Haid" pattern) the same way',
      );
    });
  });
}
