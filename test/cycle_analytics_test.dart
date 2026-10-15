import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/analytics/cycle_analytics.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

void main() {
  final now = DateTime(2026, 10, 15, 12);
  CycleLog log(DateTime date, FlowLevel flow, {int day = 1}) => CycleLog(
    id: date.toIso8601String(), userId: 'synthetic', date: date,
    flow: flow, cycleDay: day, notes: 'PRIVATE_NOT_FOR_ANALYTICS',
  );
  Map<String, dynamic> snapshot(List<CycleLog> logs, {Madhhab? madhhab}) {
    final calculation = const CycleCalculationService().calculate(logs, asOf: now);
    final summary = const CycleTrackingController().summarizeHistory(logs, now: now);
    return CycleAnalytics.snapshot(logs: logs, calculation: calculation,
      summary: summary, madhhab: madhhab, now: now);
  }
  test('empty, stale and future observations never become current purity', () {
    for (final logs in <List<CycleLog>>[
      [], [log(now.subtract(const Duration(days: 1)), FlowLevel.none)],
      [log(now.add(const Duration(days: 1)), FlowLevel.light)],
    ]) {
      final result = snapshot(logs);
      expect(result['fiqh_state'], 'unknown');
      expect(result['bleeding'], isNull);
    }
  });
  test('today no-flow is reported purity but unresolved bleeding is distinct', () {
    expect(snapshot([log(now, FlowLevel.none)])['fiqh_state'], 'tahara');
    final result = snapshot([log(now, FlowLevel.light)]);
    expect(result['fiqh_state'], 'madhhabUnresolved');
    expect(result['bleeding'], isTrue);
    expect(result['ovulation_estimate'], isNull);
  });
  test('insufficient-history bleeding cannot export legacy Tahara fallback', () {
    final result = snapshot([log(now, FlowLevel.light)], madhhab: Madhhab.hanafi);
    expect(result['fiqh_state'], 'unknown');
    expect(result['bleeding'], isTrue);
    expect(result.keys, unorderedEquals(['fiqh_state','bleeding','ovulation_estimate','pre_period_estimate']));
    expect(result.toString(), isNot(contains('PRIVATE_NOT_FOR_ANALYTICS')));
  });
  test('forecasts use existing engine dates and 1–7 day definition', () {
    // A recorded 28-day interval: Oct 1 -> Oct 29. Today is the engine's
    // predicted ovulation day. Predictions stay separate from observed purity.
    final logs = [log(DateTime(2026,9,3),FlowLevel.light),
      log(DateTime(2026,10,1),FlowLevel.light),log(now,FlowLevel.none)];
    final result=snapshot(logs);
    expect(result['ovulation_estimate'], isTrue);
    expect(result['pre_period_estimate'], isFalse);
    expect(result['fiqh_state'], 'tahara');
  });
}
