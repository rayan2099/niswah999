import '../../features/cycle_tracking/domain/entities/cycle_log.dart';
import '../../features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../../features/cycle_tracking/domain/services/cycle_status_engine.dart';
import '../../features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../errors/app_error_reporter.dart';
import '../network/supabase_client.dart';

/// Coarse current-engine outputs only; never upload source history or notes.
/// A day without a real log is unknown for observed bleeding/fiqh, even when
/// the display engine returns its default Tahara for empty/stale history.
class CycleAnalytics {
  static Map<String, dynamic> snapshot({
    required List<CycleLog> logs,
    required CycleCalculationResult calculation,
    required CycleTrackingSummary summary,
    required Madhhab? madhhab,
    required DateTime now,
  }) {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final past = logs.where((log) => !log.date.isAfter(now)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final latest = past.isEmpty ? null : past.last;
    final bleeding = latest != null && sameDay(latest.date, now)
        ? latest.flow != FlowLevel.none
        : null;
    var fiqh = 'unknown';
    if (bleeding != null) {
      if (bleeding == false) {
        fiqh = 'tahara';
      } else if (madhhab == null) {
        fiqh = 'madhhabUnresolved';
      } else if (calculation.hasSufficientHistory) {
        final state = const CycleStatusEngine().evaluate(
          logs: past, calculation: calculation, madhhab: madhhab, now: now,
        ).state;
        // The legacy engine maps insufficient-history bleeding to Tahara.
        // Never export that fallback as observed purity.
        if (state == FiqhCycleState.haid || state == FiqhCycleState.needsAdvisory) {
          fiqh = state.name;
        }
      }
    }
    final canPredict = summary.hasPlausibleAverage &&
        calculation.hasSufficientHistory && summary.nextPeriodStart != null &&
        summary.fertileWindow.peakDay != null;
    final today = DateTime(now.year, now.month, now.day);
    final next = summary.nextPeriodStart;
    final daysToNext = next == null ? null :
        DateTime(next.year, next.month, next.day).difference(today).inDays;
    return {
      'fiqh_state': fiqh,
      'bleeding': bleeding,
      'ovulation_estimate': canPredict ? sameDay(summary.fertileWindow.peakDay!, now) : null,
      'pre_period_estimate': canPredict
          ? daysToNext != null && daysToNext >= 1 && daysToNext <= 7
          : null,
    };
  }

  static Future<void> record(Map<String, dynamic> value, String userId) async {
    final client = NiswahSupabase.clientOrNull;
    if (client == null || client.auth.currentUser?.id != userId) return;
    try {
      await client.rpc('record_cycle_analytics', params: {'p_snapshot': value});
    } catch (_, stack) {
      AppErrorReporter.report(StateError('Cycle analytics could not be recorded'), stack,
        context: 'CycleAnalytics.record', feature: 'analytics');
    }
  }
}
