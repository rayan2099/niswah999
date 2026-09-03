import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';
import 'package:niswah/features/wellbeing/domain/services/wellbeing_insights_engine.dart';

WellbeingLog _log(int day, {required int mood, int energy = 3, int sleep = 3}) {
  return WellbeingLog(
    id: 'log-$day',
    userId: 'user-1',
    logDate: DateTime(2026, 8, day),
    mood: mood,
    energy: energy,
    sleep: sleep,
  );
}

void main() {
  group('WellbeingInsightsEngine — sparse data', () {
    test('below minEntriesForCharts yields no charts and no trend', () {
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: [_log(1, mood: 3), _log(2, mood: 4)],
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 3,
      );

      expect(insights.hasEnoughForCharts, isFalse);
      expect(insights.trendDirection, isNull);
      expect(insights.escalationRecommended, isFalse);
      expect(insights.canCompareToPreviousPeriod, isFalse);
    });

    test('exactly at minEntriesForCharts enables charts but not trend direction', () {
      final logs = List.generate(
        WellbeingInsightsEngine.minEntriesForCharts,
        (i) => _log(i + 1, mood: 3),
      );
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 10,
      );

      expect(insights.hasEnoughForCharts, isTrue);
      expect(insights.trendDirection, isNull);
    });
  });

  group('WellbeingInsightsEngine — trend direction', () {
    test('improving mood across the window is classified as improving', () {
      final logs = [
        for (var i = 0; i < 4; i++) _log(i + 1, mood: 2),
        for (var i = 4; i < 8; i++) _log(i + 1, mood: 4),
      ];
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 8,
      );

      expect(insights.trendDirection, MoodTrendDirection.improving);
    });

    test('declining mood across the window is classified as declining', () {
      final logs = [
        for (var i = 0; i < 4; i++) _log(i + 1, mood: 4),
        for (var i = 4; i < 8; i++) _log(i + 1, mood: 2),
      ];
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 8,
      );

      expect(insights.trendDirection, MoodTrendDirection.declining);
    });

    test('high variance is classified as fluctuating even with a flat delta', () {
      final logs = [
        _log(1, mood: 1),
        _log(2, mood: 5),
        _log(3, mood: 1),
        _log(4, mood: 5),
        _log(5, mood: 1),
        _log(6, mood: 5),
        _log(7, mood: 1),
        _log(8, mood: 5),
      ];
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 8,
      );

      expect(insights.trendDirection, MoodTrendDirection.fluctuating);
    });

    test('flat mood is classified as stable', () {
      final logs = List.generate(8, (i) => _log(i + 1, mood: 3));
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 8,
      );

      expect(insights.trendDirection, MoodTrendDirection.stable);
    });
  });

  group('WellbeingInsightsEngine — sleep pattern', () {
    test('a real, large mood gap on low-sleep days is surfaced', () {
      final logs = [
        for (var i = 0; i < 5; i++) _log(i + 1, mood: 2, sleep: 1),
        for (var i = 5; i < 10; i++) _log(i + 1, mood: 4, sleep: 4),
      ];
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 10,
      );

      expect(insights.sleepPatternFound, isTrue);
      expect(insights.averageMoodOnLowSleepDays, 2.0);
      expect(insights.averageMoodOnHigherSleepDays, 4.0);
    });

    test('a small gap is not surfaced as a pattern', () {
      final logs = [
        for (var i = 0; i < 5; i++) _log(i + 1, mood: 3, sleep: 1),
        for (var i = 5; i < 10; i++) _log(i + 1, mood: 3, sleep: 4),
      ];
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 10,
      );

      expect(insights.sleepPatternFound, isFalse);
    });

    test('too few days in one bucket does not surface a pattern', () {
      final logs = [
        _log(1, mood: 1, sleep: 1),
        _log(2, mood: 1, sleep: 1),
        for (var i = 2; i < 9; i++) _log(i + 1, mood: 4, sleep: 4),
      ];
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 9,
      );

      expect(insights.sleepPatternFound, isFalse);
    });
  });

  group('WellbeingInsightsEngine — escalation guardrail', () {
    test('sustained low mood over enough entries recommends escalation', () {
      final logs = List.generate(7, (i) => _log(i + 1, mood: 1));
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 7,
      );

      expect(insights.escalationRecommended, isTrue);
    });

    test('routine low mood below the entry threshold does not escalate', () {
      final logs = List.generate(3, (i) => _log(i + 1, mood: 1));
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 3,
      );

      expect(insights.escalationRecommended, isFalse);
    });

    test('mixed mood does not trigger escalation', () {
      final logs = [
        for (var i = 0; i < 4; i++) _log(i + 1, mood: 4),
        for (var i = 4; i < 8; i++) _log(i + 1, mood: 2),
      ];
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: logs,
        previousPeriodLogs: const [],
        daysElapsedInPeriod: 8,
      );

      expect(insights.escalationRecommended, isFalse);
    });
  });

  group('WellbeingInsightsEngine — month comparison', () {
    test('requires a minimum sample in both periods', () {
      final current = List.generate(5, (i) => _log(i + 1, mood: 4));
      final previous = [_log(1, mood: 2)];
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: current,
        previousPeriodLogs: previous,
        daysElapsedInPeriod: 5,
      );

      expect(insights.canCompareToPreviousPeriod, isFalse);
    });

    test('compares when both periods clear the threshold', () {
      final current = List.generate(5, (i) => _log(i + 1, mood: 4));
      final previous = List.generate(5, (i) => _log(i + 1, mood: 2));
      final insights = WellbeingInsightsEngine.analyze(
        currentPeriodLogs: current,
        previousPeriodLogs: previous,
        daysElapsedInPeriod: 5,
      );

      expect(insights.canCompareToPreviousPeriod, isTrue);
      expect(insights.averageMoodCurrent, 4.0);
      expect(insights.averageMoodPrevious, 2.0);
    });
  });
}
