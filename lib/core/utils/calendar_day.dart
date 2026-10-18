/// Civil-day arithmetic for reported calendar dates. Local midnight-to-midnight
/// can be 23 or 25 hours across DST; Duration.inDays would lose a recorded day.
/// This deliberately uses the supplied date fields, without changing zones.
int calendarDayDifference(DateTime end, DateTime start) => DateTime.utc(
  end.year,
  end.month,
  end.day,
).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

DateTime addCalendarDays(DateTime date, int days) => date.isUtc
    ? DateTime.utc(date.year, date.month, date.day + days)
    : DateTime(date.year, date.month, date.day + days);
