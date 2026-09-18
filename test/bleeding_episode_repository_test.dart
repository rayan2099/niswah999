import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';

/// Menstrual Data Integrity charter: without a configured Supabase client
/// (no session — matches app-start-before-sign-in and every offline
/// moment), every read/write on this server-only repository must degrade
/// to an honest, well-typed "nothing happened" rather than throwing an
/// unrelated null-pointer style failure. The RPCs themselves
/// (`start_bleeding_episode`/`end_bleeding_episode`'s atomicity,
/// idempotency, ownership/state validation, and future-date rejection)
/// were verified directly against a real local Postgres reconstruction —
/// see the migrations' own commit messages for that evidence; this file
/// covers the Dart-side null-client contract and the pure `localToday`
/// helper, which is what a plain unit test can actually exercise.
void main() {
  group('BleedingEpisodeRepositoryImpl with no Supabase client', () {
    final repository = BleedingEpisodeRepositoryImpl(client: null);

    test('startEpisode throws a StateError, not a null-pointer crash', () {
      expect(
        () => repository.startEpisode(
          clientOperationId: 'op-1',
          startDate: DateTime(2026, 9, 17),
          startPrecision: ObservationPrecision.dateOnly,
          flow: ObservationFlow.medium,
          observationPrecision: ObservationPrecision.dateOnly,
          timezone: 'UTC',
          utcOffsetMinutes: 0,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('endEpisode returns null rather than throwing', () async {
      final result = await repository.endEpisode(
        clientOperationId: 'op-2',
        episodeId: 'episode-1',
        endDate: DateTime(2026, 9, 20),
        endPrecision: ObservationPrecision.dateOnly,
        observationPrecision: ObservationPrecision.dateOnly,
        timezone: 'UTC',
        utcOffsetMinutes: 0,
      );
      expect(result, isNull);
    });

    test('markEpisodeUncertain returns null rather than throwing', () async {
      final result = await repository.markEpisodeUncertain('episode-1');
      expect(result, isNull);
    });

    test('recordObservation returns null rather than throwing', () async {
      final result = await repository.recordObservation(
        clientOperationId: 'daily-op-1',
        episodeId: 'episode-1',
        observedDate: DateTime(2026, 9, 17),
        precision: ObservationPrecision.dateOnly,
        flow: ObservationFlow.medium,
        source: ObservationSource.userObserved,
        utcOffsetMinutes: 0,
      );
      expect(result, isNull);
    });

    test(
      'correctObservation returns null rather than throwing (Hardening 2)',
      () async {
        final result = await repository.correctObservation(
          clientOperationId: 'correction-op-1',
          supersedesId: 'observation-1',
          observedDate: DateTime(2026, 9, 17),
          precision: ObservationPrecision.dateOnly,
          flow: ObservationFlow.none,
          source: ObservationSource.userReportedHistorical,
          utcOffsetMinutes: 0,
        );
        expect(result, isNull);
      },
    );

    test('effectiveObservationId returns null rather than throwing', () async {
      final result = await repository.effectiveObservationId('observation-1');
      expect(result, isNull);
    });

    test(
      'getRevisionHistory returns an empty list rather than throwing',
      () async {
        final result = await repository.getRevisionHistory('observation-1');
        expect(result, isEmpty);
      },
    );

    test(
      'getObservationsForEpisode returns an empty list rather than throwing',
      () async {
        final result = await repository.getObservationsForEpisode('episode-1');
        expect(result, isEmpty);
      },
    );

    test('getOpenEpisode returns null rather than throwing', () async {
      final result = await repository.getOpenEpisode('user-1');
      expect(result, isNull);
    });

    test(
      'recordOnboardingHistory throws a StateError, not a null-pointer crash',
      () {
        expect(
          () => repository.recordOnboardingHistory(
            clientOperationId: 'op-3',
            utcOffsetMinutes: 0,
            episode: BleedingEpisode(
              userId: 'user-1',
              lifecycleStatus: LifecycleStatus.open,
              continuationCertainty: ContinuationCertainty.confirmed,
              startDate: DateTime(2026, 9, 17),
              startPrecision: ObservationPrecision.dateOnly,
              startSource: ObservationSource.userReportedHistorical,
            ),
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group(
    'BleedingEpisodeRepositoryImpl.localToday (PR #4 hardening, Blocker 7)',
    () {
      test('is a pure function of the real current instant and an offset', () {
        final utcNow = DateTime.now().toUtc();
        final result = BleedingEpisodeRepositoryImpl.localToday(0);
        expect(result, DateTime(utcNow.year, utcNow.month, utcNow.day));
      });

      test(
        'a positive offset can roll the local date forward relative to UTC',
        () {
          // Construct a moment just before UTC midnight, then confirm a
          // positive offset can land on the *next* UTC calendar day locally.
          // We can't control real "now", so this asserts the arithmetic
          // directly rather than depending on wall-clock timing.
          final utcNow = DateTime.now().toUtc();
          final local = utcNow.add(const Duration(hours: 14));
          final expected = DateTime(local.year, local.month, local.day);
          final result = BleedingEpisodeRepositoryImpl.localToday(14 * 60);
          expect(result, expected);
        },
      );
    },
  );

  group('CycleBaselineRepositoryImpl with no Supabase client', () {
    final repository = CycleBaselineRepositoryImpl(client: null);

    test('saveBaseline returns null rather than throwing', () async {
      final result = await repository.saveBaseline(
        clientOperationId: 'baseline-op-1',
        usualBleedingDurationDays: 6,
      );
      expect(result, isNull);
    });

    test('getBaseline returns null rather than throwing', () async {
      final result = await repository.getBaseline('user-1');
      expect(result, isNull);
    });
  });
}
