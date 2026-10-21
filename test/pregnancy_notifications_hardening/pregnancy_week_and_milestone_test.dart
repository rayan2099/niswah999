// Pregnancy/notifications hardening (2026-10-21) — regression tests.
// Findings 9 (one shared week cap) and 10 (milestone probed at the 09:00
// fire time over 8 days, so a refresh never cancels a valid reminder).
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

PregnancyProfile _manual(int week, DateTime setAt) => PregnancyProfile(
  id: 'p',
  userId: 'u',
  trackingBasis: TrackingBasis.manualWeek,
  manualWeekValue: week,
  manualWeekSetAt: setAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('weekly milestone reminder', () {
    // Set up Monday 2026-10-05 15:00 at week 12: the engine's week flips at
    // 15:00 every Monday, so the first 09:00 on/after each flip is Tuesday.
    final profile = _manual(12, DateTime(2026, 10, 5, 15));

    test('refreshes before and after the flip plan the SAME reminder', () {
      final morning = NotificationScheduler.planPregnancyMilestone(
        profile: profile,
        now: DateTime(2026, 10, 12, 10),
      );
      expect(morning, isNotNull);
      expect(morning!.feedBodyEn, contains('week 13'));
      expect(morning.fireAt, DateTime(2026, 10, 13, 9));

      // Previously null here, and the coordinator then cancelled id 102.
      final evening = NotificationScheduler.planPregnancyMilestone(
        profile: profile,
        now: DateTime(2026, 10, 12, 16),
      );
      expect(evening, morning);
    });

    test('after that reminder fired, the next week is planned', () {
      final plan = NotificationScheduler.planPregnancyMilestone(
        profile: profile,
        now: DateTime(2026, 10, 13, 10),
      );
      expect(plan!.fireAt, DateTime(2026, 10, 20, 9));
      expect(plan.feedBodyEn, contains('week 14'));
    });

    test('a week that flips before 09:00 is announced that same morning', () {
      final plan = NotificationScheduler.planPregnancyMilestone(
        profile: _manual(12, DateTime(2026, 10, 5, 8)),
        now: DateTime(2026, 10, 8, 12),
      );
      expect(plan!.fireAt, DateTime(2026, 10, 12, 9));
    });

    test('no milestone once the shared cap is reached', () {
      final plan = NotificationScheduler.planPregnancyMilestone(
        profile: _manual(42, DateTime(2026, 10, 5, 15)),
        now: DateTime(2026, 10, 6, 10),
      );
      expect(plan, isNull);
    });
  });

  group('one shared week cap', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => AppClock.now = DateTime.now);

    test('3 weeks after setting week 39, the dashboard and the engine '
        '(chat/reports/notifications) agree', () async {
      final start = DateTime(2026, 9, 1, 10);
      AppClock.now = () => start;
      final c = PregnancyStatusController.instance;
      await c.activate(startWeek: 39);
      final later = start.add(const Duration(days: 21));
      AppClock.now = () => later;

      final engineWeek = PregnancyStatusEngine.getStatus(
        _manual(39, start),
        later,
      ).week;
      expect(engineWeek, PregnancyStatusEngine.maxWeek);
      expect(c.currentWeek, engineWeek);
      await c.deactivate();
    });
  });
}
