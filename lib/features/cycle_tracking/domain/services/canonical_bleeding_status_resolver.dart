import 'package:collection/collection.dart';

import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../entities/bleeding_episode.dart';

/// Menstrual Data Integrity charter, Commit F3 — explicit ring states.
/// Deliberately NOT a spectrum of "sufficient/insufficient history" (the
/// legacy engine's own framing) — four distinct, honest states, each
/// with its own real meaning:
enum RingFactualState {
  /// No canonical episode exists at all yet — nothing to show, nothing
  /// to fabricate.
  noHistory,

  /// A real, currently open episode exists — she is being tracked right
  /// now. This is always shown immediately (Commit F4: never gated on
  /// prior history), and is independent of whatever the legacy
  /// cycle_entries-derived Fiqh engine can or can't compute.
  factualOpenEpisode,

  /// At least one episode has ended, but fewer than two — real, observed
  /// history exists, but Section F5 is explicit: one completed episode
  /// is not enough for a cycle-to-cycle prediction. Show the history,
  /// never an average/next-period/fertile-window.
  factualCompletedHistory,

  /// Two or more completed episodes — only now is a cycle-to-cycle
  /// prediction genuinely input-eligible (the legacy engine's own
  /// average-cycle-length computation still decides whether it's
  /// *plausible*, a separate, narrower question this state doesn't
  /// answer by itself).
  predictionEligibleHistory,
}

class CanonicalBleedingStatus {
  const CanonicalBleedingStatus({
    required this.state,
    required this.openEpisode,
    required this.daysIntoOpenEpisode,
    required this.completedEpisodeCount,
  });

  final RingFactualState state;
  final BleedingEpisode? openEpisode;

  /// 1-based — the day she started is day 1, matching Commit F4's own
  /// "Day 1 of this record" copy.
  final int? daysIntoOpenEpisode;
  final int completedEpisodeCount;
}

/// Reads `bleeding_episodes` directly — deliberately never via the
/// `cycle_entries` legacy projection, which is the exact structural
/// dependency Commit F must eliminate (Blocker 12: a canonical save that
/// succeeded must be visible on the dashboard even when the projection
/// mirroring it into `cycle_entries` has failed).
class CanonicalBleedingStatusResolver {
  const CanonicalBleedingStatusResolver(this._repository);

  final BleedingEpisodeRepositoryImpl _repository;

  Future<CanonicalBleedingStatus> resolve({
    required String userId,
    required DateTime now,
  }) async {
    final episodes = await _repository.getEpisodesForUser(userId);
    return resolveFromEpisodes(episodes: episodes, now: now);
  }

  /// The pure decision logic, separated from the fetch above so it is
  /// directly unit-testable with a plain list — no Supabase client, no
  /// I/O — mirroring [NotificationScheduler]'s own pure-planner pattern.
  static CanonicalBleedingStatus resolveFromEpisodes({
    required List<BleedingEpisode> episodes,
    required DateTime now,
  }) {
    final openEpisode = episodes
        .where((e) => e.lifecycleStatus == LifecycleStatus.open)
        .firstOrNull;
    final completedCount = episodes
        .where((e) => e.lifecycleStatus == LifecycleStatus.ended)
        .length;

    if (openEpisode != null) {
      final today = DateTime(now.year, now.month, now.day);
      final start = DateTime(
        openEpisode.startDate.year,
        openEpisode.startDate.month,
        openEpisode.startDate.day,
      );
      final daysInto = today.difference(start).inDays + 1;
      return CanonicalBleedingStatus(
        state: RingFactualState.factualOpenEpisode,
        openEpisode: openEpisode,
        daysIntoOpenEpisode: daysInto < 1 ? 1 : daysInto,
        completedEpisodeCount: completedCount,
      );
    }

    if (completedCount == 0) {
      return CanonicalBleedingStatus(
        state: RingFactualState.noHistory,
        openEpisode: null,
        daysIntoOpenEpisode: null,
        completedEpisodeCount: 0,
      );
    }

    return CanonicalBleedingStatus(
      state: completedCount == 1
          ? RingFactualState.factualCompletedHistory
          : RingFactualState.predictionEligibleHistory,
      openEpisode: null,
      daysIntoOpenEpisode: null,
      completedEpisodeCount: completedCount,
    );
  }
}
