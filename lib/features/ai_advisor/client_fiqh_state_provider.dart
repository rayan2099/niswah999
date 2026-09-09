import '../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import '../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../cycle_tracking/domain/services/cycle_status_engine.dart';
import '../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

/// AICTX remediation: supplies the Fiqh Advisor Edge Function with the same
/// deterministic classification the dashboard already shows, computed by
/// the single canonical engine (CycleStatusEngine/MadhhabRuleEvaluator) —
/// never a second implementation. The server treats this as
/// `client_computed` (see supabase/functions/_shared/ai_user_context.ts's
/// header comment for why it is not independently re-verified server-side)
/// and falls back to `not_provided` if this returns null, which it does on
/// any failure — this must never block sending a fiqh question.
class ClientFiqhStateProvider {
  ClientFiqhStateProvider({CycleTrackingRepository? repository})
    : _repository = repository ?? CycleTrackingRepositoryImpl();

  final CycleTrackingRepository _repository;

  /// Returns the current [FiqhCycleState]'s name (e.g. "haid", "tahara"),
  /// or null if it could not be determined (no history, a repository
  /// error, etc.) — callers must treat null as "omit the field", never
  /// invent a fallback value.
  Future<String?> currentClassification(Madhhab madhhab) async {
    try {
      final logs = await _repository.getCycleLogs();
      if (logs.isEmpty) return null;

      final calculation = const CycleCalculationService().calculate(
        logs,
        asOf: DateTime.now(),
      );
      final snapshot = const CycleStatusEngine().evaluate(
        logs: logs,
        calculation: calculation,
        madhhab: madhhab,
        now: DateTime.now(),
      );
      return snapshot.state.name;
    } catch (_) {
      // Never let a context-enrichment failure block sending the question.
      return null;
    }
  }
}
