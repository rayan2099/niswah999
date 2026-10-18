import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';

void main() {
  test('1000 seeded histories preserve canonical timing despite sparse projections and input order', () {
    final random = Random(20261018);
    const service = CycleCalculationService();
    for (var trial = 0; trial < 1000; trial++) {
      var start = DateTime.utc(2020 + random.nextInt(5), 1, 1);
      final episodes = <CanonicalEpisodeTiming>[];
      final logs = <CycleLog>[];
      final intervals = <int>[];
      final durations = <int>[];
      final expectedStarts = <DateTime>[];
      for (var i = 0; i < 2 + trial % 12; i++) {
        final duration = 3 + random.nextInt(6);
        final end = start.add(Duration(days: duration));
        episodes.add(CanonicalEpisodeTiming(startDate: start, endDate: end));
        expectedStarts.add(DateTime(start.year, start.month, start.day));
        durations.add(duration);
        // Unknown early flow is never invented: projection starts only
        // when a real flow was supplied, possibly days into the episode.
        final firstKnown = random.nextInt(duration);
        logs.add(
          CycleLog(
            id: 'flow-$i',
            userId: 'synthetic',
            date: start.add(Duration(days: firstKnown)),
            flow: FlowLevel.light,
            cycleDay: firstKnown + 1,
          ),
        );
        logs.add(
          CycleLog(
            id: 'end-$i',
            userId: 'synthetic',
            date: end,
            flow: FlowLevel.none,
            cycleDay: duration + 1,
          ),
        );
        if (i < 1 + trial % 12) {
          final interval = 20 + random.nextInt(21);
          intervals.add(interval);
          start = start.add(Duration(days: interval));
        }
      }
      final asOf = episodes.last.endDate!.add(const Duration(days: 2));
      episodes.shuffle(random);
      logs.shuffle(random);
      final actual = service.calculate(
        logs,
        asOf: asOf,
        canonicalEpisodes: episodes,
      );
      expect(
        actual.haidStarts,
        expectedStarts,
        reason: 'trial $trial: no projection may create a phantom start',
      );
      expect(actual.cycleLengths, intervals, reason: 'trial $trial');
      expect(
        actual.averagePeriodLength,
        (durations.reduce((a, b) => a + b) / durations.length).round(),
        reason: 'trial $trial',
      );
      expect(
        actual.averageCycleLength,
        (intervals.reduce((a, b) => a + b) / intervals.length).round(),
        reason: 'trial $trial',
      );
    }
  });
}
