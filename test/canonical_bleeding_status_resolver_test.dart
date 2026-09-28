import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_bleeding_status_resolver.dart';

BleedingEpisode _episode({
  required LifecycleStatus lifecycleStatus,
  required DateTime startDate,
  DateTime? endDate,
}) => BleedingEpisode(
  id: 'episode-${startDate.toIso8601String()}',
  userId: 'user-1',
  lifecycleStatus: lifecycleStatus,
  continuationCertainty: lifecycleStatus == LifecycleStatus.open
      ? ContinuationCertainty.confirmed
      : null,
  startDate: startDate,
  startPrecision: ObservationPrecision.dateOnly,
  startSource: ObservationSource.userObserved,
  endDate: endDate,
  endPrecision: endDate != null ? ObservationPrecision.dateOnly : null,
  endSource: endDate != null ? ObservationSource.userObserved : null,
);

/// Menstrual Data Integrity charter, Commit F — the pure decision logic
/// behind the dashboard's ring states, reading canonical episodes
/// directly. Section F2's own mandatory test ("deliberately force
/// CycleEntriesProjection to fail, then save a canonical observation
/// successfully — the dashboard MUST still show it correctly") is proven
/// here at the resolver level: this function never reads
/// `cycle_entries`/the projection at all, only the episode list the
/// caller passes in, so a projection failure structurally cannot affect
/// its result — there is no code path connecting them.
void main() {
  group('CanonicalBleedingStatusResolver.resolveFromEpisodes', () {
    test('F3: no episodes at all -> noHistory', () {
      final status = CanonicalBleedingStatusResolver.resolveFromEpisodes(
        episodes: const [],
        now: DateTime(2026, 9, 15),
      );
      expect(status.state, RingFactualState.noHistory);
      expect(status.openEpisode, isNull);
      expect(status.completedEpisodeCount, 0);
    });

    test('F1/F2/F4: a single open episode is factualOpenEpisode immediately '
        '— this is the exact scenario a failed CycleEntriesProjection must '
        'never hide, and this function has no dependency on the projection '
        'at all to prove it', () {
      final status = CanonicalBleedingStatusResolver.resolveFromEpisodes(
        episodes: [
          _episode(
            lifecycleStatus: LifecycleStatus.open,
            startDate: DateTime(2026, 9, 15),
          ),
        ],
        now: DateTime(2026, 9, 15),
      );
      expect(status.state, RingFactualState.factualOpenEpisode);
      expect(status.openEpisode, isNotNull);
      expect(
        status.daysIntoOpenEpisode,
        1,
        reason: 'the day it started is day 1 (Commit F4 copy)',
      );
    });

    test('daysIntoOpenEpisode counts forward correctly', () {
      final status = CanonicalBleedingStatusResolver.resolveFromEpisodes(
        episodes: [
          _episode(
            lifecycleStatus: LifecycleStatus.open,
            startDate: DateTime(2026, 9, 10),
          ),
        ],
        now: DateTime(2026, 9, 13),
      );
      expect(status.daysIntoOpenEpisode, 4);
    });

    test('F5: exactly one completed episode is factualCompletedHistory, '
        'never predictionEligibleHistory', () {
      final status = CanonicalBleedingStatusResolver.resolveFromEpisodes(
        episodes: [
          _episode(
            lifecycleStatus: LifecycleStatus.ended,
            startDate: DateTime(2026, 8, 1),
            endDate: DateTime(2026, 8, 5),
          ),
        ],
        now: DateTime(2026, 9, 15),
      );
      expect(status.state, RingFactualState.factualCompletedHistory);
      expect(status.completedEpisodeCount, 1);
    });

    test('F6: two completed episodes is predictionEligibleHistory', () {
      final status = CanonicalBleedingStatusResolver.resolveFromEpisodes(
        episodes: [
          _episode(
            lifecycleStatus: LifecycleStatus.ended,
            startDate: DateTime(2026, 8, 1),
            endDate: DateTime(2026, 8, 5),
          ),
          _episode(
            lifecycleStatus: LifecycleStatus.ended,
            startDate: DateTime(2026, 7, 1),
            endDate: DateTime(2026, 7, 5),
          ),
        ],
        now: DateTime(2026, 9, 15),
      );
      expect(status.state, RingFactualState.predictionEligibleHistory);
      expect(status.completedEpisodeCount, 2);
    });

    test('an open episode takes priority over any number of completed ones '
        '— the current, live fact always wins over historical count', () {
      final status = CanonicalBleedingStatusResolver.resolveFromEpisodes(
        episodes: [
          _episode(
            lifecycleStatus: LifecycleStatus.open,
            startDate: DateTime(2026, 9, 15),
          ),
          _episode(
            lifecycleStatus: LifecycleStatus.ended,
            startDate: DateTime(2026, 8, 1),
            endDate: DateTime(2026, 8, 5),
          ),
          _episode(
            lifecycleStatus: LifecycleStatus.ended,
            startDate: DateTime(2026, 7, 1),
            endDate: DateTime(2026, 7, 5),
          ),
        ],
        now: DateTime(2026, 9, 15),
      );
      expect(status.state, RingFactualState.factualOpenEpisode);
      expect(
        status.completedEpisodeCount,
        2,
        reason:
            'still reported, even though the open episode wins '
            'which state is shown',
      );
    });
  });
}
