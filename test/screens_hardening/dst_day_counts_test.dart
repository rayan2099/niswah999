import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_segment_planner.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

/// Screens hardening — day counts shown on the dashboard across DST
/// changes. Only meaningful in a DST zone, e.g.:
///   TZ=Europe/London flutter test test/screens_hardening/dst_day_counts_test.dart
/// (Europe springs forward 2026-03-29). Skipped otherwise.
final bool _springForwardMarch2026 =
    DateTime(2026, 3, 30).difference(DateTime(2026, 3, 27)).inHours != 72;

/// Europe falls back 2026-10-25.
final bool _fallBackOctober2026 =
    DateTime(2026, 10, 26).difference(DateTime(2026, 10, 25)).inHours != 24;

void main() {
  test(
    'ring segment plan: fertile window Mar 30-Apr 5 of a cycle started '
    'Mar 20 begins on cycle day 11 (tahara1 = days 6..10 = 5 days)',
    skip: !_springForwardMarch2026,
    () {
      final plan = const CycleSegmentPlanner().plan(
        cycleLength: 28,
        periodLength: 5,
        fertileWindow: FertileWindow(
          start: DateTime(2026, 3, 30),
          end: DateTime(2026, 4, 5),
          peakDay: DateTime(2026, 4, 4),
        ),
        cycleStart: DateTime(2026, 3, 20),
        isBleedingNow: false,
        cycleDayEstimate: 8,
      );
      final tahara1 = plan.segments.firstWhere(
        (s) => s.id == CycleSegmentId.tahara1,
      );
      final fertile = plan.segments.firstWhere(
        (s) => s.id == CycleSegmentId.fertile,
      );
      expect(tahara1.durationDays, 5);
      expect(fertile.durationDays, 7);
    },
  );

  test(
    'missed check-in banner: with Oct 25 covered, the first missing day is '
    'Oct 26 (not Oct 25 23:00) across the fall-back',
    skip: !_fallBackOctober2026,
    () {
      final day = missedCheckinFirstMissingDay(
        episodeStartDate: DateTime(2026, 10, 23),
        observedDates: [DateTime(2026, 10, 24), DateTime(2026, 10, 25)],
      );
      expect(day, DateTime(2026, 10, 26));
      expect(
        day.isBefore(DateTime(2026, 10, 26)),
        isFalse,
        reason: 'on Oct 26 nothing is missing yet',
      );
    },
  );
}
