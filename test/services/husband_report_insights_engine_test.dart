import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_segment_planner.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import 'package:niswah/features/husband_report/domain/services/husband_report_insights_engine.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

CycleLog _log(int day, {required FlowLevel flow, int cycleDay = 1}) {
  return CycleLog(
    id: 'log-$day',
    userId: 'user-1',
    date: DateTime(2026, 1, day),
    flow: flow,
    cycleDay: cycleDay,
  );
}

void main() {
  test('sparse history: no next-period date or fertile window fabricated', () {
    final insights = HusbandReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanbali,
      displayName: 'أم محمد',
      now: DateTime(2026, 1, 20),
    );

    expect(insights.displayName, 'أم محمد');
    expect(insights.fiqh.mode, FiqhReportMode.cycle);
    expect(insights.fiqh.hasEnoughForAverages, isFalse);
    expect(insights.nextPeriodDate, isNull);
    expect(insights.fertileWindowStart, isNull);
    expect(insights.fertileWindowEnd, isNull);
    expect(insights.fertilePeakDay, isNull);
    expect(insights.segmentPlan, isNull);
  });

  test(
    'sufficient history: next period and fertile window are derived from '
    'the same real cycle stats the dashboard uses, not re-invented',
    () {
      // Two 28-day-apart Haid starts — a real, regular history.
      final logs = [
        _log(1, flow: FlowLevel.medium, cycleDay: 1),
        _log(4, flow: FlowLevel.none, cycleDay: 4),
        _log(29, flow: FlowLevel.medium, cycleDay: 1),
        _log(32, flow: FlowLevel.none, cycleDay: 4),
      ];

      final insights = HusbandReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        displayName: 'أم محمد',
        now: DateTime(2026, 2, 1),
      );

      expect(insights.fiqh.hasEnoughForAverages, isTrue);
      expect(insights.fiqh.averageCycleLengthDays, 28);
      // Next period = last Haid start (Jan 29) + average cycle length (28d).
      expect(insights.nextPeriodDate, DateTime(2026, 1, 29 + 28));
      expect(insights.fertileWindowStart, isNotNull);
      expect(insights.fertileWindowEnd, isNotNull);
      expect(insights.fertilePeakDay, isNotNull);
      // Reuses the same segment planner the dashboard's cycle ring uses —
      // rather than re-deriving the fertile-window breakdown independently.
      expect(insights.segmentPlan, isNotNull);
      expect(insights.segmentPlan!.segments, isNotEmpty);
      expect(
        insights.segmentPlan!.segments.any(
          (segment) => segment.id == CycleSegmentId.fertile,
        ),
        isTrue,
        reason: 'a regular history should always surface a fertile segment',
      );
    },
  );

  test(
    'overdue history: next period and fertile window are rolled forward, '
    'never shown in the past — the exact bug reported in the Husband Report',
    () {
      // Same 28-day-apart history as above, but "now" is well past the
      // naive projection (Jan 29 + 28 = Feb 26) with no new Haid start
      // logged — she is late.
      final logs = [
        _log(1, flow: FlowLevel.medium, cycleDay: 1),
        _log(4, flow: FlowLevel.none, cycleDay: 4),
        _log(29, flow: FlowLevel.medium, cycleDay: 1),
        _log(32, flow: FlowLevel.none, cycleDay: 4),
      ];
      final now = DateTime(2026, 3, 1);

      final insights = HusbandReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        displayName: 'أم محمد',
        now: now,
      );

      expect(insights.nextPeriodDate, isNotNull);
      expect(
        insights.nextPeriodDate!.isBefore(now),
        isFalse,
        reason: 'a "next period" prediction must never be in the past',
      );
      expect(
        insights.fertileWindowStart!.isBefore(now),
        isFalse,
        reason: 'the fertile window must roll forward with the prediction',
      );
    },
  );

  test(
    'postpartum profile: husband report follows the same nifas priority as '
    'the fiqh report, and skips cycle-only fields entirely',
    () {
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'user-1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 1, 1),
      );
      final logs = [_log(15, flow: FlowLevel.medium, cycleDay: 1)];

      final insights = HusbandReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        displayName: 'أم محمد',
        pregnancyProfile: profile,
        now: DateTime(2026, 1, 20),
      );

      expect(insights.fiqh.mode, FiqhReportMode.nifas);
      expect(insights.fiqh.daysPostpartum, 19);
      expect(insights.nextPeriodDate, isNull);
      expect(insights.fertileWindowStart, isNull);
      expect(insights.fertileWindowEnd, isNull);
    },
  );
}
