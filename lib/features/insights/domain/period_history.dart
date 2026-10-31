import '../../../core/utils/calendar_days.dart';
import '../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../cycle_tracking/domain/services/cycle_calculation_service.dart';

/// The "سجل الدورة" history, built from the two stores the app keeps
/// (TestFlight Feedback 2, page 5).
///
/// Before this, Insights listed canonical periods and raw `cycle_entries`
/// rows one after the other with no relationship, and showed each row's
/// legacy `cycle_day` field. On page 5 that put "27/10 – 30/10, مكتملة" and
/// "30/10, يوم الدورة 1" side by side. They are not a duplicate: a period's
/// end date is its first clean day (`end_bleeding_episode` writes a
/// `flow = none` observation on `end_date`, so length = end − start), and
/// the 30/10 row is that closing observation mirrored into `cycle_entries`,
/// whose `cycle_day` defaults to 1 because the legacy rows never saw the
/// period's start. `cycle_day` is a legacy, derived field and is no longer
/// shown.
///
/// This builder only arranges records for display. It never deletes,
/// merges or reclassifies a record: every input row appears exactly once,
/// either under the period whose dates contain it or on its own.

/// Input: one canonical period.
class HistoryPeriodInput {
  const HistoryPeriodInput({
    required this.startDate,
    this.firstCleanDay,
    this.endUnknown = false,
  });

  /// From a [CanonicalEpisodeTiming] as main has it. The period-tracking
  /// branch (PR #60) adds `endUnknown`; pass it through here once merged.
  factory HistoryPeriodInput.fromTiming(
    CanonicalEpisodeTiming timing, {
    bool endUnknown = false,
  }) => HistoryPeriodInput(
    startDate: timing.startDate,
    firstCleanDay: timing.endDate,
    endUnknown: endUnknown,
  );

  final DateTime startDate;

  /// The canonical `end_date`: the first day with no bleeding.
  final DateTime? firstCleanDay;

  /// Ended, but she does not know when (PT-002).
  final bool endUnknown;
}

enum PeriodStatus { completed, ongoing, endUnknown }

enum ObservationKind { bleeding, noBleeding, symptomsOnly }

/// One daily record from `cycle_entries`, described in plain terms.
class HistoryObservation {
  const HistoryObservation({
    required this.log,
    required this.kind,
    this.dayOfPeriod,
    this.isFirstCleanDay = false,
  });

  final CycleLog log;
  final ObservationKind kind;

  /// 1-based day within its period, from the period's own start (never the
  /// legacy `cycle_day` field). Null for a record outside any period.
  final int? dayOfPeriod;

  /// The record on the period's end date: when bleeding was recorded as
  /// stopped.
  final bool isFirstCleanDay;

  DateTime get date => calendarDay(log.date);
}

sealed class PeriodHistoryItem {
  const PeriodHistoryItem();

  /// The date the list is ordered by (newest first).
  DateTime get anchor;
}

class PeriodItem extends PeriodHistoryItem {
  const PeriodItem({
    required this.start,
    required this.status,
    this.lastBleedingDay,
    this.firstCleanDay,
    this.lengthDays,
    this.currentDay,
    this.observations = const [],
  });

  final DateTime start;
  final PeriodStatus status;

  /// The day before [firstCleanDay], for a completed period.
  final DateTime? lastBleedingDay;
  final DateTime? firstCleanDay;

  /// Days of bleeding: firstCleanDay − start. Null when unknown.
  final int? lengthDays;

  /// For an ongoing period: today is day N.
  final int? currentDay;

  /// Daily records that fall within this period, oldest first.
  final List<HistoryObservation> observations;

  @override
  DateTime get anchor => start;
}

class StandaloneObservationItem extends PeriodHistoryItem {
  const StandaloneObservationItem(this.observation);
  final HistoryObservation observation;

  @override
  DateTime get anchor => observation.date;
}

ObservationKind _kindOf(CycleLog log) {
  if (!log.recordsFlow) return ObservationKind.symptomsOnly;
  return log.flow == FlowLevel.none
      ? ObservationKind.noBleeding
      : ObservationKind.bleeding;
}

List<PeriodHistoryItem> buildPeriodHistory({
  required List<HistoryPeriodInput> periods,
  required List<CycleLog> logs,
  required DateTime today,
}) {
  final todayDay = calendarDay(today);
  final sortedPeriods = [...periods]
    ..sort((a, b) => b.startDate.compareTo(a.startDate));

  // The last day a record can belong to each period.
  DateTime lastLinkedDay(HistoryPeriodInput p) {
    final start = calendarDay(p.startDate);
    if (p.firstCleanDay != null) return calendarDay(p.firstCleanDay!);
    if (p.endUnknown) return start;
    return todayDay.isBefore(start) ? start : todayDay;
  }

  final byPeriod = <int, List<HistoryObservation>>{};
  final standalone = <StandaloneObservationItem>[];
  for (final log in logs) {
    final day = calendarDay(log.date);
    var placed = false;
    for (var i = 0; i < sortedPeriods.length; i++) {
      final p = sortedPeriods[i];
      final start = calendarDay(p.startDate);
      if (day.isBefore(start) || day.isAfter(lastLinkedDay(p))) continue;
      final kind = _kindOf(log);
      final isFirstClean =
          p.firstCleanDay != null &&
          calendarDaysBetween(calendarDay(p.firstCleanDay!), day) == 0;
      byPeriod
          .putIfAbsent(i, () => [])
          .add(
            HistoryObservation(
              log: log,
              kind: kind,
              isFirstCleanDay: isFirstClean,
              dayOfPeriod: isFirstClean
                  ? null
                  : calendarDaysBetween(start, day) + 1,
            ),
          );
      placed = true;
      break;
    }
    if (!placed) {
      standalone.add(
        StandaloneObservationItem(
          HistoryObservation(log: log, kind: _kindOf(log)),
        ),
      );
    }
  }

  final items = <PeriodHistoryItem>[
    for (var i = 0; i < sortedPeriods.length; i++)
      _periodItem(
        sortedPeriods[i],
        todayDay,
        (byPeriod[i] ?? [])..sort((a, b) => a.date.compareTo(b.date)),
      ),
    ...standalone,
  ];
  items.sort((a, b) {
    final byDate = b.anchor.compareTo(a.anchor);
    if (byDate != 0) return byDate;
    // Same day: the period first, then its unrelated record.
    return (a is PeriodItem ? 0 : 1) - (b is PeriodItem ? 0 : 1);
  });
  return items;
}

PeriodItem _periodItem(
  HistoryPeriodInput p,
  DateTime today,
  List<HistoryObservation> observations,
) {
  final start = calendarDay(p.startDate);
  if (p.firstCleanDay != null) {
    final clean = calendarDay(p.firstCleanDay!);
    final length = calendarDaysBetween(start, clean);
    return PeriodItem(
      start: start,
      status: PeriodStatus.completed,
      firstCleanDay: clean,
      lastBleedingDay: length > 0 ? addCalendarDays(clean, -1) : null,
      lengthDays: length > 0 ? length : null,
      observations: observations,
    );
  }
  if (p.endUnknown) {
    return PeriodItem(
      start: start,
      status: PeriodStatus.endUnknown,
      observations: observations,
    );
  }
  final day = calendarDaysBetween(start, today) + 1;
  return PeriodItem(
    start: start,
    status: PeriodStatus.ongoing,
    currentDay: day >= 1 ? day : null,
    observations: observations,
  );
}
