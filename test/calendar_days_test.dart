import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_days.dart';

// These hold in every time zone; run with e.g. TZ=Europe/London to cover
// the daylight-saving days that Duration-based arithmetic gets wrong.
void main() {
  test('addCalendarDays always lands on local midnight', () {
    for (var offset = 0; offset < 400; offset++) {
      final day = addCalendarDays(DateTime(2026, 1, 1), offset);
      expect(day.hour, 0, reason: '$day');
      expect(day.minute, 0, reason: '$day');
    }
    expect(addCalendarDays(DateTime(2026, 10, 1), 28), DateTime(2026, 10, 29));
    expect(addCalendarDays(DateTime(2026, 12, 20), 30), DateTime(2027, 1, 19));
    expect(addCalendarDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
  });

  test('calendarDaysBetween counts whole days across DST and years', () {
    expect(
      calendarDaysBetween(DateTime(2026, 3, 15), DateTime(2026, 4, 12)),
      28,
    );
    expect(
      calendarDaysBetween(DateTime(2026, 10, 1), DateTime(2026, 10, 29)),
      28,
    );
    expect(
      calendarDaysBetween(DateTime(2026, 12, 20, 23), DateTime(2027, 1, 19, 1)),
      30,
    );
    expect(calendarDaysBetween(DateTime(2026, 5, 2), DateTime(2026, 5, 1)), -1);
    for (var offset = 0; offset < 400; offset++) {
      final start = DateTime(2026, 1, 1);
      expect(
        calendarDaysBetween(start, addCalendarDays(start, offset)),
        offset,
      );
    }
  });
}
