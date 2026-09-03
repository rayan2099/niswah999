import '../entities/wellbeing_log.dart';

enum MoodTrendDirection { improving, stable, fluctuating, declining }

/// A day-by-day mood point for the trend chart, spanning the current and
/// previous period so the line reads as continuous rather than resetting.
class MoodTrendPoint {
  const MoodTrendPoint(this.date, this.mood);
  final DateTime date;
  final int mood;
}

/// Everything a report screen needs to render — pre-computed and gated so
/// the UI never has to decide on its own whether a number is trustworthy.
class WellbeingInsights {
  const WellbeingInsights({
    required this.currentCount,
    required this.previousCount,
    required this.daysElapsedInPeriod,
    required this.moodDistribution,
    required this.trendSeries,
    required this.hasEnoughForCharts,
    this.averageMoodCurrent,
    this.averageMoodPrevious,
    this.trendDirection,
    this.sleepPatternFound = false,
    this.averageMoodOnLowSleepDays,
    this.averageMoodOnHigherSleepDays,
    this.goodDaysCount = 0,
    this.escalationRecommended = false,
  });

  final int currentCount;
  final int previousCount;
  final int daysElapsedInPeriod;

  /// mood value (1-5) -> count, current period only.
  final Map<int, int> moodDistribution;
  final List<MoodTrendPoint> trendSeries;

  /// Below this, no chart or trend claim is shown — just the "building
  /// your picture" state.
  final bool hasEnoughForCharts;

  final double? averageMoodCurrent;
  final double? averageMoodPrevious;
  final MoodTrendDirection? trendDirection;

  final bool sleepPatternFound;
  final double? averageMoodOnLowSleepDays;
  final double? averageMoodOnHigherSleepDays;

  /// Count of current-period days with mood >= 4, for the positive
  /// reinforcement note.
  final int goodDaysCount;

  /// Sustained low mood over enough entries to not be routine fluctuation
  /// — the report should gently point toward a person, not try to resolve
  /// it with a tip.
  final bool escalationRecommended;

  bool get canCompareToPreviousPeriod =>
      currentCount >= WellbeingInsightsEngine.minEntriesForMonthComparison &&
      previousCount >= WellbeingInsightsEngine.minEntriesForMonthComparison;
}

/// Computes report insights from raw check-ins. Thresholds below are tied
/// to what the investigation found about real logging cadence: today the
/// dashboard check-in keeps no history at all (SharedPreferences, single
/// day, overwritten daily), so a brand-new user starts this table at zero.
/// Even an engaged user realistically logs ~20-30 times/month, so "a
/// week's worth" (5-8 entries) is a reasonable low bar for "enough to say
/// something" without dressing up noise as insight.
class WellbeingInsightsEngine {
  const WellbeingInsightsEngine._();

  static const minEntriesForCharts = 5;
  static const minEntriesForTrendDirection = 8;
  static const minEntriesForMonthComparison = 4;
  static const minDaysPerSleepBucketForPattern = 5;
  static const minMoodGapForSleepPattern = 0.6;
  static const minEntriesForEscalationCheck = 7;
  static const escalationAverageMoodCeiling = 2.0;
  static const escalationLowMoodShare = 0.6;

  static WellbeingInsights analyze({
    required List<WellbeingLog> currentPeriodLogs,
    required List<WellbeingLog> previousPeriodLogs,
    required int daysElapsedInPeriod,
  }) {
    final current = [...currentPeriodLogs]
      ..sort((a, b) => a.logDate.compareTo(b.logDate));
    final previous = [...previousPeriodLogs]
      ..sort((a, b) => a.logDate.compareTo(b.logDate));

    final hasEnoughForCharts = current.length >= minEntriesForCharts;

    final distribution = <int, int>{};
    for (final log in current) {
      distribution[log.mood] = (distribution[log.mood] ?? 0) + 1;
    }

    final trendSeries = [
      ...previous.map((log) => MoodTrendPoint(log.logDate, log.mood)),
      ...current.map((log) => MoodTrendPoint(log.logDate, log.mood)),
    ];

    final averageMoodCurrent = current.isEmpty
        ? null
        : current.map((l) => l.mood).reduce((a, b) => a + b) / current.length;
    final averageMoodPrevious = previous.isEmpty
        ? null
        : previous.map((l) => l.mood).reduce((a, b) => a + b) /
              previous.length;

    MoodTrendDirection? trendDirection;
    if (current.length >= minEntriesForTrendDirection) {
      final mid = current.length ~/ 2;
      final firstHalf = current.sublist(0, mid);
      final secondHalf = current.sublist(mid);
      final firstAvg =
          firstHalf.map((l) => l.mood).reduce((a, b) => a + b) /
          firstHalf.length;
      final secondAvg =
          secondHalf.map((l) => l.mood).reduce((a, b) => a + b) /
          secondHalf.length;
      final delta = secondAvg - firstAvg;

      final variance =
          current.map((l) => (l.mood - averageMoodCurrent!) * (l.mood - averageMoodCurrent)).reduce((a, b) => a + b) /
          current.length;

      if (variance >= 1.4) {
        trendDirection = MoodTrendDirection.fluctuating;
      } else if (delta >= 0.6) {
        trendDirection = MoodTrendDirection.improving;
      } else if (delta <= -0.6) {
        trendDirection = MoodTrendDirection.declining;
      } else {
        trendDirection = MoodTrendDirection.stable;
      }
    }

    var sleepPatternFound = false;
    double? averageMoodOnLowSleepDays;
    double? averageMoodOnHigherSleepDays;
    final lowSleepDays = current.where((l) => l.sleep <= 2).toList();
    final higherSleepDays = current.where((l) => l.sleep >= 3).toList();
    if (lowSleepDays.length >= minDaysPerSleepBucketForPattern &&
        higherSleepDays.length >= minDaysPerSleepBucketForPattern) {
      final lowAvg =
          lowSleepDays.map((l) => l.mood).reduce((a, b) => a + b) /
          lowSleepDays.length;
      final higherAvg =
          higherSleepDays.map((l) => l.mood).reduce((a, b) => a + b) /
          higherSleepDays.length;
      if (higherAvg - lowAvg >= minMoodGapForSleepPattern) {
        sleepPatternFound = true;
        averageMoodOnLowSleepDays = lowAvg;
        averageMoodOnHigherSleepDays = higherAvg;
      }
    }

    final goodDaysCount = current.where((l) => l.mood >= 4).length;

    var escalationRecommended = false;
    if (current.length >= minEntriesForEscalationCheck) {
      final lowShare =
          current.where((l) => l.mood <= 2).length / current.length;
      if ((averageMoodCurrent != null &&
              averageMoodCurrent <= escalationAverageMoodCeiling) ||
          lowShare >= escalationLowMoodShare) {
        escalationRecommended = true;
      }
    }

    return WellbeingInsights(
      currentCount: current.length,
      previousCount: previous.length,
      daysElapsedInPeriod: daysElapsedInPeriod,
      moodDistribution: distribution,
      trendSeries: trendSeries,
      hasEnoughForCharts: hasEnoughForCharts,
      averageMoodCurrent: averageMoodCurrent,
      averageMoodPrevious: averageMoodPrevious,
      trendDirection: trendDirection,
      sleepPatternFound: sleepPatternFound,
      averageMoodOnLowSleepDays: averageMoodOnLowSleepDays,
      averageMoodOnHigherSleepDays: averageMoodOnHigherSleepDays,
      goodDaysCount: goodDaysCount,
      escalationRecommended: escalationRecommended,
    );
  }
}
