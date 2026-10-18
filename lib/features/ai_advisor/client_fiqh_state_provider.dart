import '../../core/network/supabase_client.dart';
import '../../core/utils/app_clock.dart';
import '../cycle_tracking/domain/services/report_canonical_evidence.dart';
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
  ClientFiqhStateProvider({
    Future<ReportCanonicalEvidence?> Function(DateTime now)? evidenceLoader,
    DateTime Function()? clock,
  }) : _evidenceLoader = evidenceLoader ?? _loadEvidence,
       _clock = clock ?? AppClock.now;

  final Future<ReportCanonicalEvidence?> Function(DateTime now) _evidenceLoader;
  final DateTime Function() _clock;

  static Future<ReportCanonicalEvidence?> _loadEvidence(DateTime now) async {
    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (userId == null) return null;
    final evidence = await ReportCanonicalEvidence.load(
      userId: userId,
      now: now,
    );
    if (NiswahSupabase.clientOrNull?.auth.currentUser?.id != userId)
      return null;
    return evidence;
  }

  /// Returns the current [FiqhCycleState]'s name (e.g. "haid", "tahara",
  /// "madhhabUnresolved"), or null if it could not be determined (no
  /// history, a repository error, etc.) — callers must treat null as "omit
  /// the field", never invent a fallback value. [madhhab] is null whenever
  /// `MadhhabController.state` is not `selected` (Fiqh Remediation Wave 1)
  /// — [CycleStatusEngine] itself never guesses one on this class's behalf.
  Future<String?> currentClassification(Madhhab? madhhab) async {
    try {
      final now = _clock();
      final evidence = await _evidenceLoader(now);
      return evidence?.currentClassification(madhhab: madhhab, now: now).name;
    } catch (_) {
      // Never let a context-enrichment failure block sending the question.
      return null;
    }
  }
}
