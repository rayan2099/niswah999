import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_day.dart';

void main() {
  test('calendar dates retain their distance across spring DST', () {
    expect(
      calendarDayDifference(DateTime(2026, 4, 1), DateTime(2026, 2, 25)),
      35,
    );
    expect(
      calendarDayDifference(DateTime(2026, 5, 27), DateTime(2026, 2, 26)),
      90,
    );
  });
  test('calendar addition retains midnight across spring and fall DST', () {
    for (final date in [DateTime(2026, 3, 7), DateTime(2026, 10, 31)]) {
      final next = addCalendarDays(date, 2);
      expect(calendarDayDifference(next, date), 2);
      expect(next.hour, 0);
      expect(calendarDayDifference(addCalendarDays(next, -2), date), 0);
    }
  });
  test(
    'UTC date arithmetic retains UTC without changing the supplied date',
    () {
      final next = addCalendarDays(DateTime.utc(2026, 12, 31), 1);
      expect(next, DateTime.utc(2027, 1, 1));
      expect(next.isUtc, isTrue);
    },
  );
}
