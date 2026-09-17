import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';

/// Menstrual Data Integrity charter, Commit B: without a configured
/// Supabase client (no session — matches app-start-before-sign-in and
/// every offline moment), every read/write on this server-only
/// repository must degrade to an honest, well-typed "nothing happened"
/// rather than throwing an unrelated null-pointer style failure. The RPC
/// itself (`start_bleeding_episode`'s atomicity, its one-active-episode
/// conflict, and its auth requirement) was verified directly against a
/// real local Postgres reconstruction — see the migration's own commit
/// message for that evidence; this file covers the Dart-side null-client
/// contract, which is what a plain unit test can actually exercise.
void main() {
  group('BleedingEpisodeRepositoryImpl with no Supabase client', () {
    final repository = BleedingEpisodeRepositoryImpl(client: null);

    test('startEpisode throws a StateError, not a null-pointer crash', () {
      expect(
        () => repository.startEpisode(
          startDate: DateTime(2026, 9, 17),
          startPrecision: ObservationPrecision.dateOnly,
          flow: ObservationFlow.medium,
          observationPrecision: ObservationPrecision.dateOnly,
          timezone: 'UTC',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('endEpisode returns null rather than throwing', () async {
      final result = await repository.endEpisode(
        episodeId: 'episode-1',
        endDate: DateTime(2026, 9, 20),
        endPrecision: ObservationPrecision.dateOnly,
        endSource: ObservationSource.userObserved,
      );
      expect(result, isNull);
    });

    test('markEpisodeUncertain returns null rather than throwing', () async {
      final result = await repository.markEpisodeUncertain('episode-1');
      expect(result, isNull);
    });

    test('addObservation returns null rather than throwing', () async {
      final result = await repository.addObservation(
        BleedingObservation(
          userId: 'user-1',
          episodeId: 'episode-1',
          observedDate: DateTime(2026, 9, 17),
          precision: ObservationPrecision.dateOnly,
          flow: ObservationFlow.medium,
          source: ObservationSource.userObserved,
          timezone: 'UTC',
        ),
      );
      expect(result, isNull);
    });

    test(
      'getObservationsForEpisode returns an empty list rather than throwing',
      () async {
        final result = await repository.getObservationsForEpisode('episode-1');
        expect(result, isEmpty);
      },
    );

    test('getActiveEpisode returns null rather than throwing', () async {
      final result = await repository.getActiveEpisode('user-1');
      expect(result, isNull);
    });
  });
}
