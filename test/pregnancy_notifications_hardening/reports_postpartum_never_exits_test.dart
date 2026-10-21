// Pregnancy/notifications hardening (2026-10-21) — regression tests for
// finding 2: reports use the nifas branch only while the engine's phase is
// nifas; after it they fall through to the cycle branch.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

CycleLog _log(DateTime date, FlowLevel flow, int cycleDay) => CycleLog(
  id: 'log-${date.toIso8601String()}',
  userId: 'user-1',
  date: date,
  flow: flow,
  cycleDay: cycleDay,
);

PregnancyProfile _postpartum(DateTime birth) => PregnancyProfile(
  id: 'p',
  userId: 'user-1',
  isPostpartum: true,
  postpartumStartDate: birth,
);

void main() {
  final birth = DateTime(2026, 1, 1);

  test(
    '200 days after birth, with cycles back, the report is in cycle mode',
    () {
      final logs = <CycleLog>[
        for (var d = 1; d <= 6; d++)
          _log(DateTime(2026, 5, d), FlowLevel.medium, d),
        _log(DateTime(2026, 5, 7), FlowLevel.none, 7),
        for (var d = 1; d <= 6; d++)
          _log(DateTime(2026, 6, d), FlowLevel.medium, d),
        _log(DateTime(2026, 6, 7), FlowLevel.none, 7),
        for (var d = 17; d <= 20; d++)
          _log(DateTime(2026, 7, d), FlowLevel.medium, d - 16),
      ];
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanafi,
        pregnancyProfile: _postpartum(birth),
        now: DateTime(2026, 7, 20),
      );
      expect(insights.mode, FiqhReportMode.cycle);
      expect(insights.pregnancy, isNull);
    },
  );

  test('inside the engine nifas phase (day 40) the report is still nifas', () {
    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanafi,
      pregnancyProfile: _postpartum(birth),
      now: DateTime(2026, 2, 10),
    );
    expect(insights.mode, FiqhReportMode.nifas);
    expect(insights.daysPostpartum, 40);
  });

  test('day 41 (engine phase over) falls through to the cycle branch', () {
    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanafi,
      pregnancyProfile: _postpartum(birth),
      now: DateTime(2026, 2, 11),
    );
    expect(insights.mode, FiqhReportMode.cycle);
  });
}
