import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';

void main() {
  const service = CycleCalculationService();
  final asOf = DateTime(2026, 8, 18, 15);
  CycleLog log(String id, DateTime day, FlowLevel flow) => CycleLog(
    id: id,
    userId: 'synthetic-owner',
    date: day,
    flow: flow,
    cycleDay: flow == FlowLevel.none ? 6 : 1,
  );

  test('future legacy start cannot alter historical cycle timing', () {
    final history = [
      log('first', DateTime(2026, 7, 21), FlowLevel.medium),
      log('end', DateTime(2026, 7, 26), FlowLevel.none),
      log('current', DateTime(2026, 8, 18, 12), FlowLevel.medium),
    ];
    final expected = service.calculate(history, asOf: asOf);
    final result = service.calculate([
      ...history,
      log('future', DateTime(2026, 9, 15), FlowLevel.medium),
    ], asOf: asOf);
    expect(result.haidStarts, expected.haidStarts);
    expect(result.cycleLengths, [28]);
    expect(result.currentCycleDay, 1);
    expect(result.predictedCycleLength, expected.predictedCycleLength);
  });

  test('future legacy end cannot supply a historical measured duration', () {
    final result = service.calculate([
      log('start', DateTime(2026, 8, 13), FlowLevel.medium),
      log('future-end', DateTime(2026, 8, 19), FlowLevel.none),
    ], asOf: asOf);
    expect(result.averagePeriodLength, isNull);
  });

  test('canonical starts use civil dates and exclude later dates', () {
    final result = service.calculate(
      const [],
      asOf: asOf,
      canonicalEpisodes: [
        CanonicalEpisodeTiming(startDate: DateTime(2026, 7, 21, 12)),
        CanonicalEpisodeTiming(startDate: DateTime(2026, 8, 18, 23)),
        CanonicalEpisodeTiming(startDate: DateTime(2026, 8, 19)),
      ],
    );
    expect(result.haidStarts, [DateTime(2026, 7, 21), DateTime(2026, 8, 18)]);
    expect(result.cycleLengths, [28]);
    expect(result.currentCycleDay, 1);
  });

  test('canonical future end is withheld without changing stored timing', () {
    final timing = CanonicalEpisodeTiming(
      startDate: DateTime(2026, 8, 13),
      endDate: DateTime(2026, 8, 19),
    );
    final result = service.calculate(
      const [],
      asOf: asOf,
      canonicalEpisodes: [timing],
    );
    expect(result.averagePeriodLength, isNull);
    expect(timing.endDate, DateTime(2026, 8, 19));
  });

  test('canonical end on the as-of civil date remains measured', () {
    final result = service.calculate(
      const [],
      asOf: asOf,
      canonicalEpisodes: [
        CanonicalEpisodeTiming(
          startDate: DateTime(2026, 8, 13),
          endDate: DateTime(2026, 8, 18, 23),
        ),
      ],
    );
    expect(result.averagePeriodLength, 5);
  });

  for (final endedWithoutDate in [true, false]) {
    test(
      'historical cutoff preserves ${endedWithoutDate ? "unknown ended" : "open"} canonical timing',
      () {
        final result = service.calculate(
          [
            log('later-start', DateTime(2026, 8, 10), FlowLevel.medium),
            log('later-end', DateTime(2026, 8, 15), FlowLevel.none),
            log('future', DateTime(2026, 9, 8), FlowLevel.medium),
          ],
          asOf: asOf,
          canonicalEpisodes: [
            CanonicalEpisodeTiming(
              startDate: DateTime(2026, 7, 13),
              endUnknown: endedWithoutDate,
            ),
          ],
        );
        expect(
          result.haidStarts,
          endedWithoutDate
              ? [DateTime(2026, 7, 13), DateTime(2026, 8, 10)]
              : [DateTime(2026, 7, 13)],
        );
        expect(result.cycleLengths, endedWithoutDate ? [28] : isEmpty);
        expect(result.averagePeriodLength, endedWithoutDate ? 5 : isNull);
      },
    );
  }
}
