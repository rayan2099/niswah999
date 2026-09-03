import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

CycleLog _log(
  int day, {
  required FlowLevel flow,
  int cycleDay = 1,
  String? notes,
}) {
  return CycleLog(
    id: 'log-$day',
    userId: 'user-1',
    date: DateTime(2026, 1, day),
    flow: flow,
    cycleDay: cycleDay,
    notes: notes,
  );
}

void main() {
  group('FiqhReportInsightsEngine — nifas priority', () {
    test('postpartum profile takes priority over any cycle log state', () {
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'user-1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 1, 1),
      );
      final logs = [_log(15, flow: FlowLevel.medium, cycleDay: 1)];

      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        pregnancyProfile: profile,
        now: DateTime(2026, 1, 20),
      );

      expect(insights.mode, FiqhReportMode.nifas);
      expect(insights.daysPostpartum, 19);
      expect(insights.nifasPhase, 'نفاس');
    });

    test('notes still surface from cycle logs while in nifas mode', () {
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'user-1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 1, 1),
      );
      final logs = [
        _log(15, flow: FlowLevel.medium, cycleDay: 1, notes: 'spotting today'),
      ];

      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        pregnancyProfile: profile,
        now: DateTime(2026, 1, 20),
      );

      expect(insights.notes.single.text, 'spotting today');
    });
  });

  group('FiqhReportInsightsEngine — sparse history', () {
    test('no logs at all reports tahara with no averages', () {
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanbali,
        now: DateTime(2026, 1, 20),
      );

      expect(insights.mode, FiqhReportMode.cycle);
      expect(insights.cycleState, FiqhCycleState.tahara);
      expect(insights.hasEnoughForAverages, isFalse);
      expect(insights.averageCycleLengthDays, isNull);
      expect(insights.notes, isEmpty);
    });

    test('a logged note surfaces even with insufficient history for averages', () {
      final logs = [
        _log(1, flow: FlowLevel.medium, cycleDay: 1, notes: 'first period ever'),
      ];

      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        now: DateTime(2026, 1, 10),
      );

      expect(insights.hasEnoughForAverages, isFalse);
      expect(insights.notes.single.text, 'first period ever');
    });

    test('fewer than two haid starts does not compute an average', () {
      final logs = [
        _log(1, flow: FlowLevel.medium, cycleDay: 1),
        _log(2, flow: FlowLevel.medium, cycleDay: 2),
        _log(3, flow: FlowLevel.none, cycleDay: 3),
      ];

      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        now: DateTime(2026, 1, 10),
      );

      expect(insights.hasEnoughForAverages, isFalse);
      expect(insights.averageCycleLengthDays, isNull);
      expect(insights.haidEpisodeCount, 1);
      expect(insights.averageHaidDurationDays, 2);
    });
  });

  group('FiqhReportInsightsEngine — sufficient history', () {
    test('two haid starts compute an average cycle length', () {
      final logs = [
        _log(1, flow: FlowLevel.medium, cycleDay: 1),
        _log(2, flow: FlowLevel.medium, cycleDay: 2),
        _log(3, flow: FlowLevel.none, cycleDay: 3),
        _log(29, flow: FlowLevel.medium, cycleDay: 1),
        _log(30, flow: FlowLevel.medium, cycleDay: 2),
        _log(31, flow: FlowLevel.none, cycleDay: 3),
      ];

      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        now: DateTime(2026, 2, 5),
      );

      expect(insights.hasEnoughForAverages, isTrue);
      expect(insights.averageCycleLengthDays, 28);
      expect(insights.haidEpisodeCount, 2);
      expect(insights.averageHaidDurationDays, 2);
      expect(insights.cycleState, FiqhCycleState.tahara);
    });

    test('currently bleeding within madhhab bounds reports haid', () {
      final logs = [
        _log(1, flow: FlowLevel.medium, cycleDay: 1),
        _log(2, flow: FlowLevel.medium, cycleDay: 2),
        _log(3, flow: FlowLevel.none, cycleDay: 3),
        _log(29, flow: FlowLevel.medium, cycleDay: 1),
        _log(30, flow: FlowLevel.medium, cycleDay: 2),
      ];

      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanbali,
        now: DateTime(2026, 1, 31),
      );

      expect(insights.cycleState, FiqhCycleState.haid);
    });

    test('bleeding past a madhhab\'s maximum reports needsAdvisory', () {
      // Hanafi max is 240 hours (10 days). A first short episode establishes
      // a second haid start (so hasSufficientHistory is true), then a
      // second episode runs 12 days straight — past the hanafi ceiling.
      final logs = [
        _log(1, flow: FlowLevel.medium, cycleDay: 1),
        _log(2, flow: FlowLevel.none, cycleDay: 2),
        for (var day = 15; day <= 27; day++)
          _log(day, flow: FlowLevel.medium, cycleDay: day - 14),
      ];

      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.hanafi,
        now: DateTime(2026, 1, 27),
      );

      expect(insights.hasEnoughForAverages, isTrue);
      expect(insights.cycleState, FiqhCycleState.needsAdvisory);
    });
  });
}
