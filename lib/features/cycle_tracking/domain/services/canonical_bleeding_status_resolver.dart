import 'package:collection/collection.dart';

import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../entities/bleeding_episode.dart';
import '../entities/load_result.dart';

/// Menstrual Data Integrity charter, Commit F3 — explicit ring states.
/// Deliberately NOT a spectrum of "sufficient/insufficient history" (the
/// legacy engine's own framing) — distinct, honest states, each with its
/// own real meaning:
enum RingFactualState {
  /// No canonical episode exists at all yet — nothing to show, nothing
  /// to fabricate.
  noHistory,

  /// A real, currently open episode exists — she is being tracked right
  /// now. This is always shown immediately (Commit F4: never gated on
  /// prior history), and is independent of whatever the legacy
  /// cycle_entries-derived Fiqh engine can or can't compute.
  factualOpenEpisode,

  /// At least one episode has ended, but fewer than two trustworthy
  /// completed episodes exist — real, observed history exists, but
  /// Section F5 is explicit: one completed episode is not enough for a
  /// cycle-to-cycle prediction. Show the history, never an average/
  /// next-period/fertile-window.
  factualCompletedHistory,

  /// Two or more *trustworthy* completed episodes (Closure Blocker 16:
  /// episode count alone is not sufficient — a read degraded by
  /// quarantined/unparseable rows never reaches this state, since the
  /// true picture may be incomplete) — only now is a cycle-to-cycle
  /// prediction genuinely input-eligible (the legacy engine's own
  /// average-cycle-length computation still decides whether it's
  /// *plausible*, a separate, narrower question this state doesn't
  /// answer by itself).
  predictionEligibleHistory,

  /// Closure Blocker 1 — the read itself failed (network/backend/auth):
  /// genuinely unknown, never silently treated as [noHistory]. The
  /// caller must show a retryable "couldn't verify" state, never a
  /// confident empty one.
  unavailable,
}

class CanonicalBleedingStatus {
  const CanonicalBleedingStatus({
    required this.state,
    required this.openEpisode,
    required this.daysIntoOpenEpisode,
    required this.completedEpisodeCount,
    this.isDegraded = false,
    this.quarantinedCount = 0,
  });

  final RingFactualState state;
  final BleedingEpisode? openEpisode;

  /// 1-based — the day she started is day 1, matching Commit F4's own
  /// "Day 1 of this record" copy.
  final int? daysIntoOpenEpisode;
  final int completedEpisodeCount;

  /// Closure Blocker 17 — true when one or more rows in the underlying
  /// read were quarantined (failed strict parsing) rather than silently
  /// dropped and treated as if the remaining rows were the whole truth.
  /// [state] is still usable when this is true (the rows that DID parse
  /// are real), but a caller computing something with real user-facing
  /// stakes (a prediction, a Fiqh conclusion) must not claim full
  /// confidence — see [RingFactualState.predictionEligibleHistory]'s own
  /// doc comment for why a degraded read can never reach that state.
  final bool isDegraded;
  final int quarantinedCount;
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
    final result = await _repository.getEpisodesForUser(userId);
    return switch (result) {
      LoadUnavailable<List<BleedingEpisode>>() => const CanonicalBleedingStatus(
        state: RingFactualState.unavailable,
        openEpisode: null,
        daysIntoOpenEpisode: null,
        completedEpisodeCount: 0,
      ),
      LoadSuccess<List<BleedingEpisode>>(:final data) => resolveFromEpisodes(
        episodes: data,
        now: now,
      ),
      LoadDegraded<List<BleedingEpisode>>(
        :final data,
        :final quarantinedCount,
      ) =>
        resolveFromEpisodes(
          episodes: data,
          now: now,
          isDegraded: true,
          quarantinedCount: quarantinedCount,
        ),
    };
  }

  /// The pure decision logic, separated from the fetch above so it is
  /// directly unit-testable with a plain list — no Supabase client, no
  /// I/O — mirroring [NotificationScheduler]'s own pure-planner pattern.
  static CanonicalBleedingStatus resolveFromEpisodes({
    required List<BleedingEpisode> episodes,
    required DateTime now,
    bool isDegraded = false,
    int quarantinedCount = 0,
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
        isDegraded: isDegraded,
        quarantinedCount: quarantinedCount,
      );
    }

    if (completedCount == 0) {
      return CanonicalBleedingStatus(
        state: RingFactualState.noHistory,
        openEpisode: null,
        daysIntoOpenEpisode: null,
        completedEpisodeCount: 0,
        isDegraded: isDegraded,
        quarantinedCount: quarantinedCount,
      );
    }

    // Closure Blocker 16 — "we have two completed episodes" and "we have
    // enough trustworthy evidence to predict" are kept as two separate
    // questions: a degraded read (one or more rows quarantined
    // elsewhere in the same query) never reaches predictionEligibleHistory
    // even if the rows that DID parse number two or more — the true
    // completed count may be understated, overstated, or the
    // quarantined row itself may have been a corrupt completed episode
    // that would change the picture. Every episode that DID parse is
    // itself individually trustworthy (BleedingEpisode.fromJson never
    // silently defaults a required field — a malformed row throws and
    // is quarantined, not admitted), so the count itself is exact for
    // what could be read; it is the completeness of the read as a whole
    // that a degraded result cannot vouch for.
    final trustworthyForPrediction = !isDegraded && completedCount >= 2;

    return CanonicalBleedingStatus(
      state: trustworthyForPrediction
          ? RingFactualState.predictionEligibleHistory
          : RingFactualState.factualCompletedHistory,
      openEpisode: null,
      daysIntoOpenEpisode: null,
      completedEpisodeCount: completedCount,
      isDegraded: isDegraded,
      quarantinedCount: quarantinedCount,
    );
  }
}
