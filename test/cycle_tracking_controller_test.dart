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
      'predictNextPeriodStart is plain calendar arithmetic and is never '
      'rolled forward to next month',
      () {
        final next = CycleTrackingController().predictNextPeriodStart(
          cycleStart: DateTime(2026, 8, 1),
          averageCycleLength: 28,
        );

        expect(next, equals(DateTime(2026, 8, 29)));
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

    group('summarizeHistory predictions', () {
      const controller = CycleTrackingController();
      var nextId = 0;

      /// One log per bleeding day for each (start, days) period, then a
      /// Tahara log the day after it ends.
      List<CycleLog> history(List<(DateTime, int)> periods) => [
        for (final (start, days) in periods) ...[
          for (var i = 0; i < days; i++)
            CycleLog(
              id: '${nextId++}',
              userId: 'user_1',
              date: DateTime(start.year, start.month, start.day + i),
              flow: FlowLevel.medium,
              cycleDay: i + 1,
            ),
          CycleLog(
            id: '${nextId++}',
            userId: 'user_1',
            date: DateTime(start.year, start.month, start.day + days),
            flow: FlowLevel.none,
            cycleDay: days + 1,
          ),
        ],
      ];

      /// Periods of [days] days starting at [first] and after each gap.
      List<(DateTime, int)> periods(
        DateTime first,
        List<int> gaps, {
        int days = 5,
      }) {
        final out = [(first, days)];
        var current = first;
        for (final gap in gaps) {
          current = DateTime(current.year, current.month, current.day + gap);
          out.add((current, days));
        }
        return out;
      }

      // Regular 28-day cycles; the last one starts Oct 1, so the next is
      // due Oct 29 — the same dates Flo's own calculator gives.
      final regular = history(periods(DateTime(2026, 7, 9), [28, 28, 28]));

      test('mid-cycle: next period, ovulation and fertile window', () {
        final summary = controller.summarizeHistory(
          regular,
          now: DateTime(2026, 10, 10, 9),
        );

        expect(summary.predictedCycleLength, 28);
        expect(summary.nextPeriodStart, DateTime(2026, 10, 29));
        expect(summary.fertileWindow.peakDay, DateTime(2026, 10, 15));
        expect(summary.fertileWindow.start, DateTime(2026, 10, 10));
        expect(summary.fertileWindow.end, DateTime(2026, 10, 16));
        expect(summary.daysLate, 0);
      });

      test(
        'on the due day, any time of day, the period is still due today '
        '(it used to jump a whole cycle ahead after midnight)',
        () {
          for (final hour in [0, 10, 23]) {
            final summary = controller.summarizeHistory(
              regular,
              now: DateTime(2026, 10, 29, hour, 30),
            );
            expect(
              summary.nextPeriodStart,
              DateTime(2026, 10, 29),
              reason: 'at $hour:30 on the due day',
            );
            expect(summary.daysLate, 0);
          }
        },
      );

      test(
        'a slightly late period shows "today" and hides the fertile window, '
        'never next month\'s dates',
        () {
          final summary = controller.summarizeHistory(
            regular,
            now: DateTime(2026, 10, 31, 10),
          );

          expect(summary.daysLate, 2);
          expect(summary.nextPeriodStart, DateTime(2026, 10, 31));
          expect(summary.fertileWindow.peakDay, isNull);
          expect(summary.fertileWindow.start, isNull);
        },
      );

      test('a clearly late period has no predicted date, only daysLate', () {
        final summary = controller.summarizeHistory(
          regular,
          now: DateTime(2026, 11, 12, 10),
        );

        expect(summary.daysLate, 14);
        expect(summary.nextPeriodStart, isNull);
        expect(summary.fertileWindow.peakDay, isNull);
      });

      test(
        'one unlogged period (a 56-day gap) does not drag the prediction',
        () {
          final summary = controller.summarizeHistory(
            history(periods(DateTime(2026, 6, 11), [28, 28, 56])),
            now: DateTime(2026, 10, 10, 9),
          );

          expect(summary.averageCycleLength, 37, reason: 'factual mean');
          expect(summary.predictedCycleLength, 28);
          expect(summary.nextPeriodStart, DateTime(2026, 10, 29));
        },
      );

      test('recent cycles count more than old ones', () {
        final summary = controller.summarizeHistory(
          history(periods(DateTime(2026, 1, 1), [26, 26, 26, 32, 32, 32])),
          now: DateTime(2026, 7, 1, 9),
        );

        expect(summary.averageCycleLength, 29);
        expect(summary.predictedCycleLength, greaterThan(29));
      });

      test('irregular cycles get a wider fertile window', () {
        final summary = controller.summarizeHistory(
          history(periods(DateTime(2026, 4, 1), [24, 35, 27, 40, 22])),
          now: DateTime(2026, 8, 30, 9),
        );

        final window = summary.fertileWindow;
        expect(window.peakDay, isNotNull);
        expect(
          window.end!.difference(window.start!).inDays + 1,
          13,
          reason: '7 days widened by 3 on each side',
        );
      });

      test('regular cycles keep the standard 7-day fertile window', () {
        final window = controller
            .summarizeHistory(regular, now: DateTime(2026, 10, 10, 9))
            .fertileWindow;

        expect(window.end!.difference(window.start!).inDays + 1, 7);
      });

      test('ovulation is not predicted for cycles shorter than 21 days', () {
        final summary = controller.summarizeHistory(
          history(periods(DateTime(2026, 9, 1), [16, 16, 16])),
          now: DateTime(2026, 10, 20, 9),
        );

        expect(summary.nextPeriodStart, DateTime(2026, 11, 4));
        expect(summary.fertileWindow.peakDay, isNull);
      });

      test('predictions cross the year boundary', () {
        final summary = controller.summarizeHistory(
          history(periods(DateTime(2026, 9, 21), [30, 30, 30])),
          now: DateTime(2026, 12, 25, 9),
        );

        expect(summary.nextPeriodStart, DateTime(2027, 1, 19));
        expect(summary.fertileWindow.peakDay, DateTime(2027, 1, 5));
        expect(summary.fertileWindow.start, DateTime(2026, 12, 31));
        expect(summary.fertileWindow.end, DateTime(2027, 1, 6));
      });

      test('cycle phase follows the same ovulation rule', () {
        final start = DateTime(2026, 1, 1);
        CyclePhase phaseOn(int cycleDay, int length) => controller
            .calculatePhase(
              date: DateTime(2026, 1, cycleDay),
              cycleStart: start,
              averageCycleLength: length,
            );

        expect(phaseOn(5, 28), CyclePhase.menstrual);
        expect(phaseOn(9, 28), CyclePhase.follicular);
        expect(phaseOn(10, 28), CyclePhase.ovulation);
        expect(phaseOn(16, 28), CyclePhase.ovulation);
        expect(phaseOn(17, 28), CyclePhase.luteal);
        expect(phaseOn(22, 35), CyclePhase.ovulation);
        expect(phaseOn(24, 35), CyclePhase.luteal);
      });
    });
  });
}
