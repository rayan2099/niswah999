import '../../core/network/supabase_client.dart';
import '../../core/utils/app_clock.dart';
import '../cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import '../cycle_tracking/domain/services/canonical_fiqh_assessment.dart';
import '../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../cycle_tracking/domain/services/report_canonical_evidence.dart';

/// AICTX remediation: supplies the Fiqh Advisor Edge Function with the same
/// deterministic classification the dashboard already shows. Fiqh
/// hardening (2026-10-18): computed from the same canonical evidence
/// ([ReportCanonicalEvidence.load]) through the same combination with the
/// canonical episode status ([CanonicalFiqhAssessment]) as the Today
/// dashboard and the reports — never from the legacy `cycle_entries`
/// table, which previously let a woman bleeding for the first time be
/// described to the model as "tahara". The server treats this as
/// `client_computed` (see supabase/functions/_shared/ai_user_context.ts's
/// header comment for why it is not independently re-verified server-side)
/// and falls back to `not_provided` if this returns null — this must never
/// block sending a fiqh question.
class ClientFiqhStateProvider {
  ClientFiqhStateProvider({
    BleedingEpisodeRepositoryImpl? repository,
    String? Function()? currentUserId,
    DateTime Function()? clock,
  }) : _repository = repository ?? BleedingEpisodeRepositoryImpl(),
       _currentUserId =
           currentUserId ??
           (() => NiswahSupabase.clientOrNull?.auth.currentUser?.id),
       _clock = clock ?? (() => AppClock.now());

  final BleedingEpisodeRepositoryImpl _repository;
  final String? Function() _currentUserId;
  final DateTime Function() _clock;

  /// Returns the current [FiqhCycleState]'s name (e.g. "haid", "tahara",
  /// "needsAdvisory", "madhhabUnresolved"), "insufficientHistory" while an
  /// episode is open with too little recorded history, or null when the
  /// state cannot be determined (no session, unreadable or unverifiable
  /// canonical evidence, any error) — callers must treat null as "omit the
  /// field", never invent a fallback value. [madhhab] is null whenever
  /// `MadhhabController.state` is not `selected` (Fiqh Remediation Wave 1).
  Future<String?> currentClassification(Madhhab? madhhab) async {
    try {
      final now = _clock();
      final evidence = await ReportCanonicalEvidence.load(
        userId: _currentUserId(),
        now: now,
        repository: _repository,
      );
      if (evidence == null || evidence.unavailable) return null;

      final assessment = CanonicalFiqhAssessment.assess(
        effectiveLogs: evidence.effectiveLogs,
        hasOpenEpisode: evidence.hasOpenEpisode,
        evidenceUnresolved: evidence.evidenceUnresolved,
        madhhab: madhhab,
        now: now,
      );
      return switch (assessment.verdict) {
        CanonicalFiqhVerdict.evaluated => assessment.state!.name,
        CanonicalFiqhVerdict.insufficientHistory =>
          FiqhCycleState.insufficientHistory.name,
        // "Unable to verify" on Today: there is no classification to send.
        CanonicalFiqhVerdict.evidenceUnresolved => null,
      };
    } catch (_) {
      // Never let a context-enrichment failure block sending the question.
      return null;
    }
  }
}
