/// Calendar-day arithmetic that is safe across daylight-saving changes.
///
/// Local midnights are not 24 hours apart on the days clocks change, so
/// `date.add(Duration(days: n))` can land at 23:00 on the previous day and
/// `a.difference(b).inDays` can come out one short. Every cycle date in the
/// app is a calendar day, so day math goes through these helpers instead.
library;

/// [value] truncated to its local calendar day (midnight).
DateTime calendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// The calendar day [days] after (or before, if negative) [value]'s day.
DateTime addCalendarDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);

/// Whole calendar days from [from]'s day to [to]'s day (negative if [to]
/// is earlier). Time of day and DST offsets are ignored.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
