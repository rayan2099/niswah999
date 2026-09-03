import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

void main() {
  group('CycleTrackingController', () {
    test('calculates the current phase from a cycle start', () {
      final baseDate = DateTime(2026, 8, 1);
      final phase = CycleTrackingController().calculatePhase(
        date: baseDate.add(const Duration(days: 4)),
        cycleStart: baseDate,
        averageCycleLength: 28,
      );

      expect(phase, CyclePhase.menstrual);
    });

    test(
      'builds a fertile window using the 14-day luteal-phase heuristic '
      '(ovulation = predicted next period minus 14 days)',
      () {
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
      },
    );

    test(
      'predictNextPeriodStart rolls forward past the naive projection once '
      'it is already in the past — the exact bug reported in the Husband '
      'Report (a "next period" and fertile window shown before "today")',
      () {
        final cycleStart = DateTime(2026, 8, 1);
        const averageCycleLength = 28;
        // Naive projection would be Aug 1 + 28 = Aug 29 — one day before
        // "now", i.e. one day overdue with no new Haid start logged.
        final now = DateTime(2026, 8, 30);

        final next = CycleTrackingController().predictNextPeriodStart(
          cycleStart: cycleStart,
          averageCycleLength: averageCycleLength,
          now: now,
        );

        expect(
          next.isBefore(now),
          isFalse,
          reason: 'a "next period" prediction must never be in the past',
        );
        expect(next, equals(DateTime(2026, 9, 26)));

        final window = CycleTrackingController().calculateFertileWindow(
          cycleStart: cycleStart,
          averageCycleLength: averageCycleLength,
          now: now,
        );
        expect(
          window.peakDay!.isBefore(now),
          isFalse,
          reason: 'the fertile window must roll forward with the prediction',
        );
        expect(window.peakDay, equals(DateTime(2026, 9, 12)));
      },
    );

    test(
      'predictNextPeriodStart leaves a projection landing exactly on "now" '
      'alone — due today is not overdue',
      () {
        final cycleStart = DateTime(2026, 8, 1);
        final naiveNextPeriod = DateTime(2026, 8, 29);

        final next = CycleTrackingController().predictNextPeriodStart(
          cycleStart: cycleStart,
          averageCycleLength: 28,
          now: naiveNextPeriod,
        );

        expect(next, equals(naiveNextPeriod));
      },
    );

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

    test(
      'summarizeHistory withholds forward predictions for a degenerate '
      '(implausibly short) average cycle length, without hiding the '
      'reported average itself',
      () {
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
      },
    );
  });
}
