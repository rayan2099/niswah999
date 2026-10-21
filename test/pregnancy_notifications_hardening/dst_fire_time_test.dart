// Pregnancy/notifications hardening (2026-10-21) — regression tests for
// finding 11 (calendar-day math in reminder fire times and the rolling
// window). Meaningful in a DST zone; run both ways:
//   flutter test test/pregnancy_notifications_hardening
//   TZ=America/New_York flutter test test/pregnancy_notifications_hardening
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

void main() {
  test('nifas reminder fires at 09:00 local across a DST change', () {
    final plan = NotificationScheduler.planNifasCountdown(
      profile: PregnancyProfile(
        id: 'p',
        userId: 'u',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 10, 20),
      ),
      now: DateTime(2026, 10, 20, 12),
    );
    expect(plan!.fireAt, DateTime(2026, 11, 24, 9));
  });

  test('pregnancy milestone across fall-back: right day, 09:00', () {
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
    // Week 13 begins 2026-11-02 ~08:00 local; the 09:00 reminder that day.
    expect(plan!.fireAt, DateTime(2026, 11, 2, 9));
  });

  test('rolling check-in window: one plan per distinct local day across '
      'fall-back, every one at the preferred time', () {
    final episode = BleedingEpisode(
      id: 'ep',
      userId: 'u',
      lifecycleStatus: LifecycleStatus.open,
      continuationCertainty: ContinuationCertainty.confirmed,
      startDate: DateTime(2026, 10, 30),
      startPrecision: ObservationPrecision.dateOnly,
      startSource: ObservationSource.userObserved,
    );
    final plans = ActiveBleedingReminderScheduler.planRollingDailyCheckins(
      episode: episode,
      todaysObservationCount: 0,
      now: DateTime(2026, 10, 31, 8),
      leadHour: 18,
      leadMinute: 0,
      daysAhead: 5,
    );
    expect(plans.map((p) => p.fireAt), [
      DateTime(2026, 10, 31, 18),
      DateTime(2026, 11, 1, 18),
      DateTime(2026, 11, 2, 18),
      DateTime(2026, 11, 3, 18),
      DateTime(2026, 11, 4, 18),
    ]);
    expect(plans.map((p) => p.id).toSet(), hasLength(5));
    expect(
      ActiveBleedingReminderScheduler.rollingWindowReminderIds(
        userId: 'u',
        episodeId: 'ep',
        today: DateTime(2026, 10, 31),
        daysAhead: 5,
      ),
      plans.map((p) => p.id).toList(),
    );
  });
}
