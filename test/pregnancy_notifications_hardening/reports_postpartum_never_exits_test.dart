// Round 2 review (pregnancy / nifas / notifications) — FAILING BY DESIGN
// until fixed. Proves: once `pregnancy_profile.is_postpartum` is true, the
// Fiqh/Doctor/Husband reports stay in "nifas" mode FOREVER — months after
// the birth, after her cycles have returned — and never compute her real
// Haid/Tahara state again. No code path ever clears `is_postpartum`
// (PregnancyStatusController.deactivate() is local-only).
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

void main() {
  test('200 days after birth, with cycles back, the Fiqh report must not '
      'still say "Current state: Nifas"', () {
    final birth = DateTime(2026, 1, 1);
    final now = DateTime(2026, 7, 20); // day 200 postpartum
    final profile = PregnancyProfile(
      id: 'p',
      userId: 'user-1',
      isPostpartum: true,
      postpartumStartDate: birth,
    );
    // Two completed cycles after nifas, and she is bleeding today.
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
      pregnancyProfile: profile,
      now: now,
    );

    // Today: mode == nifas, daysPostpartum == 200, phase 'ما بعد النفاس';
    // the PDF prints "Current state: Nifas" / husband report "Nifas".
    expect(
      insights.mode,
      FiqhReportMode.cycle,
      reason:
          'daysPostpartum=${insights.daysPostpartum} phase=${insights.nifasPhase}',
    );
  });
}
