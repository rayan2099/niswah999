import '../../../../core/utils/calendar_days.dart';
import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../entities/wellbeing_log.dart';

/// Averages for one group of mood check-ins.
class WellbeingGroupSummary {
  const WellbeingGroupSummary({
    required this.count,
    this.averageMood,
    this.averageEnergy,
    this.averageSleep,
  });

  final int count;
  final double? averageMood;
  final double? averageEnergy;
  final double? averageSleep;

  static WellbeingGroupSummary of(Iterable<WellbeingLog> logs) {
    final list = logs.toList();
    if (list.isEmpty) return const WellbeingGroupSummary(count: 0);
    double avg(int Function(WellbeingLog) pick) =>
        list.map(pick).reduce((a, b) => a + b) / list.length;
    return WellbeingGroupSummary(
      count: list.length,
      averageMood: avg((log) => log.mood),
      averageEnergy: avg((log) => log.energy),
      averageSleep: avg((log) => log.sleep),
    );
  }
}

/// Mood check-ins split by whether bleeding was recorded on that day.
///
/// Mood, energy and sleep are tracked every day, period or not (device run
/// 2026-10-28). This split only says which check-ins fell on a recorded
/// bleeding day; it is a tracking fact, never a fiqh classification
/// (haid, istihadah or tuhr are decided elsewhere).
class WellbeingPeriodSplit {
  const WellbeingPeriodSplit({
    required this.all,
    required this.onPeriodDays,
    required this.onOtherDays,
  });

  final WellbeingGroupSummary all;
  final WellbeingGroupSummary onPeriodDays;
  final WellbeingGroupSummary onOtherDays;

  /// An episode with no recorded end counts as bleeding for at most this
  /// many days from its start, so an end she forgot to log does not mark
  /// the rest of the month as period days.
  static const openEpisodeMaxDays = 10;

  static WellbeingPeriodSplit compute({
    required List<WellbeingLog> logs,
    List<CycleLog> cycleLogs = const [],
    List<CanonicalEpisodeTiming> episodes = const [],
    required DateTime today,
  }) {
    final bleedingDays = <DateTime>{
      for (final log in cycleLogs)
        if (log.recordsFlow && log.flow != FlowLevel.none)
          calendarDay(log.date),
    };
    final todayDay = calendarDay(today);
    for (final episode in episodes) {
      final start = calendarDay(episode.startDate);
      // endDate is the first clean day, so it is not a bleeding day.
      final cap = addCalendarDays(start, openEpisodeMaxDays);
      // An unknown end (PT-002): only the start day is known.
      final end = episode.endUnknown
          ? addCalendarDays(start, 1)
          : episode.endDate == null
          ? (todayDay.isBefore(cap) ? addCalendarDays(todayDay, 1) : cap)
          : calendarDay(episode.endDate!);
      for (var day = start; day.isBefore(end); day = addCalendarDays(day, 1)) {
        bleedingDays.add(day);
      }
    }

    bool onPeriod(WellbeingLog log) =>
        bleedingDays.contains(calendarDay(log.logDate));

    return WellbeingPeriodSplit(
      all: WellbeingGroupSummary.of(logs),
      onPeriodDays: WellbeingGroupSummary.of(logs.where(onPeriod)),
      onOtherDays: WellbeingGroupSummary.of(logs.where((l) => !onPeriod(l))),
    );
  }
}
