import '../../../../core/utils/calendar_days.dart';
import '../entities/wellbeing_log.dart';

/// Mood, energy and sleep check-ins grouped into equal time buckets for the
/// Insights chart (testing feedback 2026-10-30).
///
/// Only real check-ins are averaged. A bucket with no check-in has
/// `count == 0` and no averages: the chart leaves a gap there instead of
/// drawing a guessed value or a zero.
class WellbeingTrendBucket {
  const WellbeingTrendBucket({
    required this.start,
    required this.end,
    required this.count,
    this.mood,
    this.energy,
    this.sleep,
  });

  /// First calendar day of the bucket.
  final DateTime start;

  /// Last calendar day of the bucket (inclusive).
  final DateTime end;
  final int count;
  final double? mood;
  final double? energy;
  final double? sleep;

  bool get hasData => count > 0;
}

enum WellbeingTrendGranularity { week, month }

class WellbeingTrend {
  const WellbeingTrend({
    required this.granularity,
    required this.buckets,
    required this.checkIns,
  });

  final WellbeingTrendGranularity granularity;

  /// Every bucket in the range, oldest first, including empty ones.
  final List<WellbeingTrendBucket> buckets;

  /// Check-ins inside the range (one per day at most, as stored).
  final int checkIns;

  int get bucketsWithData => buckets.where((b) => b.hasData).length;

  /// Ranges longer than six months are grouped by calendar month so the
  /// chart stays readable; shorter ones by seven-day blocks counted from
  /// the range start (not a locale-dependent week start).
  static WellbeingTrend compute({
    required List<WellbeingLog> logs,
    required DateTime from,
    required DateTime today,
    required int months,
  }) {
    final first = calendarDay(from);
    final last = calendarDay(today);
    final inRange = [
      for (final log in logs)
        if (!calendarDay(log.logDate).isBefore(first) &&
            !calendarDay(log.logDate).isAfter(last))
          log,
    ];
    final granularity = months > 6
        ? WellbeingTrendGranularity.month
        : WellbeingTrendGranularity.week;

    final ranges = <(DateTime, DateTime)>[];
    if (granularity == WellbeingTrendGranularity.week) {
      for (
        var start = first;
        !start.isAfter(last);
        start = addCalendarDays(start, 7)
      ) {
        final end = addCalendarDays(start, 6);
        ranges.add((start, end.isAfter(last) ? last : end));
      }
    } else {
      for (
        var start = DateTime(first.year, first.month);
        !start.isAfter(last);
        start = DateTime(start.year, start.month + 1)
      ) {
        final end = DateTime(start.year, start.month + 1, 0);
        ranges.add((
          start.isBefore(first) ? first : start,
          end.isAfter(last) ? last : end,
        ));
      }
    }

    final buckets = [
      for (final (start, end) in ranges)
        _bucket(start, end, [
          for (final log in inRange)
            if (!calendarDay(log.logDate).isBefore(start) &&
                !calendarDay(log.logDate).isAfter(end))
              log,
        ]),
    ];
    return WellbeingTrend(
      granularity: granularity,
      buckets: buckets,
      checkIns: inRange.length,
    );
  }

  /// One bucket per calendar month from [from] to [today], oldest first.
  /// [monthOf] returns a value shared by every day of one month, so the
  /// months can be Gregorian or Hijri (the calendar screen's choice). The
  /// first and last months may be partial.
  static WellbeingTrend computeByMonth({
    required List<WellbeingLog> logs,
    required DateTime from,
    required DateTime today,
    required int Function(DateTime day) monthOf,
  }) {
    final first = calendarDay(from);
    final last = calendarDay(today);
    final inRange = [
      for (final log in logs)
        if (!calendarDay(log.logDate).isBefore(first) &&
            !calendarDay(log.logDate).isAfter(last))
          log,
    ];
    final ranges = <(DateTime, DateTime)>[];
    for (var day = first; !day.isAfter(last); day = addCalendarDays(day, 1)) {
      if (ranges.isNotEmpty && monthOf(ranges.last.$1) == monthOf(day)) {
        ranges[ranges.length - 1] = (ranges.last.$1, day);
      } else {
        ranges.add((day, day));
      }
    }
    return WellbeingTrend(
      granularity: WellbeingTrendGranularity.month,
      buckets: [
        for (final (start, end) in ranges)
          _bucket(start, end, [
            for (final log in inRange)
              if (!calendarDay(log.logDate).isBefore(start) &&
                  !calendarDay(log.logDate).isAfter(end))
                log,
          ]),
      ],
      checkIns: inRange.length,
    );
  }

  static WellbeingTrendBucket _bucket(
    DateTime start,
    DateTime end,
    List<WellbeingLog> logs,
  ) {
    if (logs.isEmpty) {
      return WellbeingTrendBucket(start: start, end: end, count: 0);
    }
    double avg(int Function(WellbeingLog) pick) =>
        logs.map(pick).reduce((a, b) => a + b) / logs.length;
    return WellbeingTrendBucket(
      start: start,
      end: end,
      count: logs.length,
      mood: avg((log) => log.mood),
      energy: avg((log) => log.energy),
      sleep: avg((log) => log.sleep),
    );
  }
}
