// Round 2 review — FAILING BY DESIGN until fixed, in any DST-observing
// zone. Run with:  TZ=America/New_York flutter test <this file>
// (In UTC/no-DST zones the arithmetic coincides and these pass.)
//
// planNifasCountdown / planPregnancyMilestone build fire times with
// `today.add(Duration(days: n))` (24h multiples) instead of calendar-day
// arithmetic (`addCalendarDays`, which planCycleReminder already uses), so
// a DST change between now and the fire day shifts the 09:00 reminder.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

void main() {
  final dstZone =
      DateTime(2026, 10, 31).timeZoneOffset != DateTime(2026, 11, 2).timeZoneOffset;

  test('nifas day-35 warning fires at 09:00 local even across a DST change '
      '(zone has DST between Oct 31 and Nov 2 2026: $dstZone)', () {
    final plan = NotificationScheduler.planNifasCountdown(
      profile: PregnancyProfile(
        id: 'p',
        userId: 'u',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 10, 20),
      ),
      now: DateTime(2026, 10, 20, 12),
    );
    expect(plan, isNotNull);
    expect(plan!.fireAt, DateTime(2026, 11, 24, 9));
  });

  // Also fails in UTC: the planner probes candidate days at 00:00, so when
  // the week flips before 09:00 (set-up time 08:00) the reminder lands a
  // day late (Nov 3). In New York it is additionally an hour early (08:00).
  test('pregnancy milestone across fall-back fires on the right day at 09:00',
      () {
    final plan = NotificationScheduler.planPregnancyMilestone(
      profile: PregnancyProfile(
        id: 'p',
        userId: 'u',
        trackingBasis: TrackingBasis.manualWeek,
        manualWeekValue: 12,
        manualWeekSetAt: DateTime(2026, 10, 26, 8),
      ),
      now: DateTime(2026, 10, 31, 12),
    );
    expect(plan, isNotNull);
    // Week 13 begins 2026-11-02 08:00 local; the 09:00 reminder that day.
    expect(plan!.fireAt, DateTime(2026, 11, 2, 9));
  });
}
