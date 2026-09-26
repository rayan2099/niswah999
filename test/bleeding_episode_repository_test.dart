import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/app_clock.dart';

import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';

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
      'getRevisionHistory returns LoadUnavailable rather than throwing or '
      'silently returning an empty list (Closure Blocker 1: a read '
      'failure must never be conflated with a verified-empty result)',
      () async {
        final result = await repository.getRevisionHistory('observation-1');
        expect(result, isA<LoadUnavailable<List<BleedingObservation>>>());
      },
    );

    test(
      'getObservationsForEpisode returns LoadUnavailable rather than '
      'throwing or silently returning an empty list (Closure Blocker 1)',
      () async {
        final result = await repository.getObservationsForEpisode('episode-1');
        expect(result, isA<LoadUnavailable<List<BleedingObservation>>>());
      },
    );

    test('getOpenEpisode returns LoadUnavailable rather than throwing or '
        'silently returning null (Closure Blocker 1)', () async {
      final result = await repository.getOpenEpisode('user-1');
      expect(result, isA<LoadUnavailable<BleedingEpisode?>>());
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
      // localToday derives from AppClock.now (default DateTime.now —
      // production behavior unchanged); pinning it makes every case
      // exact instead of racing the real wall clock at a day boundary.
      tearDown(AppClock.reset);

      DateTime at(DateTime instant, int offsetMinutes) {
        AppClock.now = () => instant;
        return BleedingEpisodeRepositoryImpl.localToday(offsetMinutes);
      }

      test('zero offset is the UTC calendar date', () {
        expect(
          at(DateTime.utc(2030, 1, 15, 23, 59, 59), 0),
          DateTime(2030, 1, 15),
        );
        expect(at(DateTime.utc(2030, 1, 16), 0), DateTime(2030, 1, 16));
      });

      test('a positive offset rolls the local date FORWARD past UTC', () {
        // 21:07Z is already 00:07 tomorrow in Riyadh (+3) — the exact
        // wall-clock window in which CI first disagreed with itself.
        expect(
          at(DateTime.utc(2030, 1, 15, 21, 7), 3 * 60),
          DateTime(2030, 1, 16),
        );
        expect(
          at(DateTime.utc(2030, 1, 15, 20, 59, 59), 3 * 60),
          DateTime(2030, 1, 15),
        );
        expect(
          at(DateTime.utc(2030, 1, 15, 10), 14 * 60),
          DateTime(2030, 1, 16),
        );
      });

      test('a negative offset holds the local date BEHIND UTC', () {
        expect(
          at(DateTime.utc(2030, 1, 16, 7, 59, 59), -8 * 60),
          DateTime(2030, 1, 15),
        );
        expect(
          at(DateTime.utc(2030, 1, 16, 8), -8 * 60),
          DateTime(2030, 1, 16),
        );
        expect(
          at(DateTime.utc(2030, 1, 16, 10), -11 * 60),
          DateTime(2030, 1, 15),
        );
      });

      test('a half-hour offset lands on the correct side of midnight', () {
        expect(
          at(DateTime.utc(2030, 1, 15, 18, 29, 59), 5 * 60 + 30),
          DateTime(2030, 1, 15),
        );
        expect(
          at(DateTime.utc(2030, 1, 15, 18, 30), 5 * 60 + 30),
          DateTime(2030, 1, 16),
        );
      });

      test('month and year boundaries roll correctly', () {
        expect(
          at(DateTime.utc(2030, 12, 31, 21), 3 * 60),
          DateTime(2031, 1, 1),
        );
        expect(at(DateTime.utc(2030, 2, 28, 23), 2 * 60), DateTime(2030, 3, 1));
      });

      test('with AppClock untouched it is still the real current instant', () {
        AppClock.reset();
        final before = DateTime.now().toUtc();
        final result = BleedingEpisodeRepositoryImpl.localToday(0);
        final after = DateTime.now().toUtc();
        // Either side of a possible midnight tick is acceptable — this
        // only proves the default clock is the real one.
        expect([
          DateTime(before.year, before.month, before.day),
          DateTime(after.year, after.month, after.day),
        ], contains(result));
      });
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
