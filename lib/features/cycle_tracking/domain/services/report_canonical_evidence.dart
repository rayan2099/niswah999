import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../entities/bleeding_episode.dart';
import '../entities/cycle_log.dart';
import '../entities/load_result.dart';
import 'canonical_bleeding_status_resolver.dart';
import 'canonical_fiqh_evidence_adapter.dart';
import 'cycle_calculation_service.dart';

/// The evidence the Fiqh / Husband / Doctor reports must use for the CURRENT
/// state and the cycle statistics — the same canonical, post-correction
/// evidence the Today dashboard rules on, never the legacy `cycle_entries`
/// table alone.
///
/// Found live (D-011): a woman with Hanafi selected and a bleeding episode
/// recorded in onboarding (open, flow "uncertain" — never projected to
/// `cycle_entries`) saw "Current state: Tahara" in the Fiqh report while
/// Today showed "Bleeding recorded — Day 4". The reports read only the legacy
/// table, which has no row for an uncertain day.
class ReportCanonicalEvidence {
  const ReportCanonicalEvidence({
    required this.effectiveLogs,
    required this.episodes,
    required this.hasOpenEpisode,
    required this.evidenceUnresolved,
    this.unavailable = false,
  });

  /// Effective (post-correction) canonical days with a representable flow.
  final List<CycleLog> effectiveLogs;

  /// Episode start/end DATES only (never a flow) — see [CanonicalEpisodeTiming].
  final List<CanonicalEpisodeTiming> episodes;

  final bool hasOpenEpisode;

  /// A material gap in the evidence for the open episode (an "I'm not sure"
  /// day on/after its start, or a quarantined row) — never rule confidently.
  final bool evidenceUnresolved;

  /// The canonical read itself failed — genuinely unknown, never "no data".
  final bool unavailable;

  /// Same definition the dashboard uses: an excluded "I'm not sure" day only
  /// matters when it falls on/after the currently open episode's start.
  static bool hasMaterialUnresolvedEvidence({
    required List<BleedingObservation> observations,
    required DateTime? openEpisodeStart,
  }) {
    if (openEpisodeStart == null) return false;
    final start = DateTime(
      openEpisodeStart.year,
      openEpisodeStart.month,
      openEpisodeStart.day,
    );
    return CanonicalFiqhEvidenceAdapter.excludedUncertainDates(
      observations: observations,
    ).any((date) => !date.isBefore(start));
  }

  /// Loads the evidence for [userId]; null when nobody is signed in.
  static Future<ReportCanonicalEvidence?> load({
    required String? userId,
    required DateTime now,
    BleedingEpisodeRepositoryImpl? repository,
  }) async {
    if (userId == null) return null;
    final repo = repository ?? BleedingEpisodeRepositoryImpl();
    final episodesResult = await repo.getEpisodesForUser(userId);
    final observationsResult = await repo.getAllObservationsForUser(userId);

    if (episodesResult is LoadUnavailable<List<BleedingEpisode>> ||
        observationsResult is LoadUnavailable<List<BleedingObservation>>) {
      return const ReportCanonicalEvidence(
        effectiveLogs: [],
        episodes: [],
        hasOpenEpisode: false,
        evidenceUnresolved: true,
        unavailable: true,
      );
    }

    final status = await CanonicalBleedingStatusResolver(repo)
        .resolve(userId: userId, now: now);
    final episodes = episodesResult.dataOrNull ?? const <BleedingEpisode>[];
    final observations =
        observationsResult.dataOrNull ?? const <BleedingObservation>[];
    final quarantined = switch (observationsResult) {
      LoadDegraded<List<BleedingObservation>>(:final quarantinedCount) =>
        quarantinedCount,
      _ => 0,
    };

    return ReportCanonicalEvidence(
      effectiveLogs: CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: observations,
      ),
      episodes: [
        for (final e in episodes)
          CanonicalEpisodeTiming(startDate: e.startDate, endDate: e.endDate),
      ],
      hasOpenEpisode: status.state == RingFactualState.factualOpenEpisode,
      evidenceUnresolved:
          quarantined > 0 ||
          hasMaterialUnresolvedEvidence(
            observations: observations,
            openEpisodeStart: status.openEpisode?.startDate,
          ),
    );
  }
}
