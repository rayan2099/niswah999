// Round 2 review — FAILING BY DESIGN until fixed.
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
    // Pregnancy set up Monday 2026-10-05 15:00 at week 12. The engine's
    // week flips at 15:00 every Monday; the planner probes candidate days
    // at MIDNIGHT, so it sees the flip a day late — and on the flip day
    // itself, after 15:00, it finds no higher week within its 7-day probe.
    final setAt = DateTime(2026, 10, 5, 15);
    final profile = _manual(12, setAt);

    test('a refresh on the boundary day AFTER the flip still plans the next '
        'milestone (it currently returns null, and _apply(null) CANCELS id '
        '102 — the already-scheduled week-13 reminder is lost)', () {
      final morning = NotificationScheduler.planPregnancyMilestone(
        profile: profile,
        now: DateTime(2026, 10, 12, 10),
      );
      // Precondition: the 10:00 refresh scheduled "entered week 13".
      expect(morning, isNotNull);
      expect(morning!.bodyEn, contains('week 13'));
      expect(morning.fireAt, DateTime(2026, 10, 13, 9));

      final evening = NotificationScheduler.planPregnancyMilestone(
        profile: profile,
        now: DateTime(2026, 10, 12, 16),
      );
      expect(evening, isNotNull,
          reason: 'no milestone planned; coordinator cancels id 102');
    });
  });

  group('dashboard vs engine week cap', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => AppClock.now = DateTime.now);

    test('3 weeks after setting week 39, dashboard and chat/reports/'
        'notifications must agree on the week', () async {
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
      // dashboard: clamp(1, 40) -> 40 ; engine: clamp(1, 42) -> 42
      expect(c.currentWeek, engineWeek);
      await c.deactivate();
    });
  });
}
