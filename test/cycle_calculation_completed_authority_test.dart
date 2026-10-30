import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';

void main() {
  const service = CycleCalculationService();
  final asOf = DateTime(2026, 8, 18);
  CycleLog log(String id, DateTime day, FlowLevel flow) => CycleLog(
    id: id,
    userId: 'synthetic-owner',
    date: day,
    flow: flow,
    cycleDay: flow == FlowLevel.none ? 10 : 1,
  );

  test(
    'completed canonical start and duration outrank an earlier projection',
    () {
      final result = service.calculate(
        [
          log('projection', DateTime(2026, 7, 1), FlowLevel.medium),
          log('next-cycle', DateTime(2026, 7, 29), FlowLevel.medium),
        ],
        asOf: asOf,
        canonicalEpisodes: [
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 7, 2),
            endDate: DateTime(2026, 7, 7),
          ),
        ],
      );
      expect(result.haidStarts, [DateTime(2026, 7, 2), DateTime(2026, 7, 29)]);
      expect(result.cycleLengths, [27]);
      expect(result.averagePeriodLength, 5);
    },
  );

  test(
    'conflicting projection duration cannot replace measured canonical length',
    () {
      final result = service.calculate(
        [
          log('projection', DateTime(2026, 7, 1), FlowLevel.medium),
          log('projection-end', DateTime(2026, 7, 10), FlowLevel.none),
        ],
        asOf: asOf,
        canonicalEpisodes: [
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 7, 2),
            endDate: DateTime(2026, 7, 7),
          ),
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 7, 29),
            endDate: DateTime(2026, 8, 7),
          ),
        ],
      );
      expect(result.haidStarts, [DateTime(2026, 7, 2), DateTime(2026, 7, 29)]);
      expect(
        result.averagePeriodLength,
        7,
      ); // Equal episode weights: (5 + 9) / 2.
    },
  );
}
