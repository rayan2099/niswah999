import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';
import 'package:niswah/features/wellbeing/domain/services/wellbeing_period_split.dart';

WellbeingLog _mood(DateTime day, int mood) => WellbeingLog(
  id: 'w-${day.toIso8601String()}',
  userId: 'u',
  logDate: day,
  mood: mood,
  energy: mood,
  sleep: mood,
);

CycleLog _flow(DateTime day, FlowLevel flow) => CycleLog(
  id: 'c-${day.toIso8601String()}',
  userId: 'u',
  date: day,
  flow: flow,
);

void main() {
  final today = DateTime(2026, 10, 28);

  test('check-ins with no period at all are all counted, as other days', () {
    final split = WellbeingPeriodSplit.compute(
      logs: [
        _mood(DateTime(2026, 10, 20), 2),
        _mood(DateTime(2026, 10, 21), 4),
      ],
      today: today,
    );
    expect(split.all.count, 2);
    expect(split.all.averageMood, 3);
    expect(split.onPeriodDays.count, 0);
    expect(split.onPeriodDays.averageMood, isNull);
    expect(split.onOtherDays.count, 2);
  });

  test(
    'a closed episode marks start up to (not including) the first clean day',
    () {
      final split = WellbeingPeriodSplit.compute(
        logs: [
          _mood(DateTime(2026, 10, 1), 1),
          _mood(DateTime(2026, 10, 5), 2),
          _mood(DateTime(2026, 10, 6), 5),
        ],
        episodes: [
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 10, 1),
            endDate: DateTime(2026, 10, 6),
          ),
        ],
        today: today,
      );
      expect(split.onPeriodDays.count, 2);
      expect(split.onPeriodDays.averageMood, 1.5);
      expect(split.onOtherDays.count, 1);
      expect(split.onOtherDays.averageMood, 5);
    },
  );

  test(
    'an open episode counts at most ${WellbeingPeriodSplit.openEpisodeMaxDays} days',
    () {
      final split = WellbeingPeriodSplit.compute(
        logs: [
          _mood(DateTime(2026, 10, 3), 3),
          _mood(DateTime(2026, 10, 20), 3),
        ],
        episodes: [CanonicalEpisodeTiming(startDate: DateTime(2026, 10, 1))],
        today: today,
      );
      expect(split.onPeriodDays.count, 1);
      expect(split.onOtherDays.count, 1);
    },
  );

  test('daily flow logs count; no-flow and symptoms-only logs do not', () {
    final split = WellbeingPeriodSplit.compute(
      logs: [
        _mood(DateTime(2026, 10, 10), 2),
        _mood(DateTime(2026, 10, 11), 4),
        _mood(DateTime(2026, 10, 12), 4),
      ],
      cycleLogs: [
        _flow(DateTime(2026, 10, 10), FlowLevel.light),
        _flow(DateTime(2026, 10, 11), FlowLevel.none),
        CycleLog(
          id: 's',
          userId: 'u',
          date: DateTime(2026, 10, 12),
          flow: FlowLevel.medium,
          symptoms: const [CycleLog.symptomsOnlyMarker],
        ),
      ],
      today: today,
    );
    expect(split.onPeriodDays.count, 1);
    expect(split.onOtherDays.count, 2);
  });
}
