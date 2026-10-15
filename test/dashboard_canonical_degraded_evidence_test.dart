import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import 'support/parity_test_harness.dart';

/// F5(B)/(C) — genuine canonical load failure (episodes) and genuine
/// canonical *degradation* (a partially-parsed observations read),
/// exercised against the real [DashboardScreen] and its real
/// [BleedingEpisodeRepositoryImpl]-shaped injection points — never a
/// decorative test-only stand-in.
class _FakeCanonicalRepository extends BleedingEpisodeRepositoryImpl {
  _FakeCanonicalRepository({
    this.episodes = const [],
    this.observations = const [],
    this.quarantinedCount = 0,
    bool episodesFailFirstCallThenSucceed = false,
  }) : _episodesFailFirstCallThenSucceed = episodesFailFirstCallThenSucceed,
       super(client: null);

  final List<BleedingEpisode> episodes;
  final List<BleedingObservation> observations;

  /// > 0 makes [getAllObservationsForUser] return [LoadDegraded] instead
  /// of [LoadSuccess] — a partially-parsed read, never conflated with a
  /// clean one.
  final int quarantinedCount;

  final bool _episodesFailFirstCallThenSucceed;
  bool _episodesCalledOnce = false;

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async {
    if (_episodesFailFirstCallThenSucceed && !_episodesCalledOnce) {
      _episodesCalledOnce = true;
      return const LoadUnavailable(LoadErrorCategory.network);
    }
    return LoadSuccess(episodes);
  }

  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String userId,
  ) async {
    if (quarantinedCount > 0) {
      return LoadDegraded(observations, quarantinedCount);
    }
    return LoadSuccess(observations);
  }
}

Map<String, Object?> log({
  required String id,
  required String date,
  required String flow,
  int cycleDay = 1,
}) => {
  'id': id,
  'user_id': 'local-user',
  'date': date,
  'flow': flow,
  'cycle_day': cycleDay,
  'sync_status': 'synced',
};

// Reaches the branch-4 ring/Fiqh-card render path (legacy calculation
// has sufficient history) — the exact same fixture test 1 in
// parity_today_stepper_consistency_test.dart already establishes.
const _sufficientLegacyLogs = [
  {
    'id': '1',
    'user_id': 'local-user',
    'date': '2026-06-01T08:00:00.000',
    'flow': 'medium',
    'cycle_day': 1,
    'sync_status': 'synced',
  },
  {
    'id': '2',
    'user_id': 'local-user',
    'date': '2026-06-05T08:00:00.000',
    'flow': 'none',
    'cycle_day': 1,
    'sync_status': 'synced',
  },
  {
    'id': '3',
    'user_id': 'local-user',
    'date': '2026-07-20T08:00:00.000',
    'flow': 'medium',
    'cycle_day': 1,
    'sync_status': 'synced',
  },
  {
    'id': '4',
    'user_id': 'local-user',
    'date': '2026-07-24T08:00:00.000',
    'flow': 'none',
    'cycle_day': 1,
    'sync_status': 'synced',
  },
];

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester, {
    required BleedingEpisodeRepositoryImpl repository,
    List<Map<String, Object?>> legacyLogs = const [],
  }) async {
    final logsJson = jsonEncode(legacyLogs);
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      extraPrefs: {
        'niswah_cycle_tracking_logs': logsJson,
        'flutter.niswah_cycle_tracking_logs': logsJson,
      },
      homeOverride: DashboardScreen(
        canonicalRepositoryOverride: repository,
        canonicalUserIdOverride: 'user-1',
      ),
    );
  }

  group('F5(B) — genuine episodes-read failure', () {
    testWidgets(
      'shows the honest "couldn\'t verify" card, never fabricated empty '
      'history, and its retry button is real',
      (tester) async {
        await pumpDashboard(
          tester,
          repository: _FakeCanonicalRepository(
            episodesFailFirstCallThenSucceed: true,
          ),
        );

        expect(
          find.text("We couldn't verify your tracking data right now."),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
        // Must never simultaneously show a confident "no history" claim.
        expect(find.textContaining('two Haid'), findsNothing);
      },
    );

    testWidgets('tapping retry against a repository that now succeeds replaces '
        'the unavailable card with the real, verified state — a full, '
        'genuine retry round trip (no real backend needed, since the fake '
        'repository itself is what changes state on the second call)', (
      tester,
    ) async {
      final repository = _FakeCanonicalRepository(
        episodesFailFirstCallThenSucceed: true,
      );
      await pumpDashboard(tester, repository: repository);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(
        find.text("We couldn't verify your tracking data right now."),
        findsNothing,
        reason:
            'the retried read succeeded — the unavailable card must '
            'be gone, not merely re-rendered alongside real data',
      );
    });
  });

  group(
    'F5(C) — degraded canonical evidence restricts the Fiqh conclusion',
    () {
      testWidgets(
        'a quarantined (unparseable) row alone is enough to withhold a '
        'confident ruling, even though the rows that DID parse look '
        'perfectly ordinary',
        (tester) async {
          await pumpDashboard(
            tester,
            legacyLogs: _sufficientLegacyLogs,
            repository: _FakeCanonicalRepository(
              observations: const [],
              quarantinedCount: 1,
            ),
          );

          expect(find.textContaining('لا يمكن تأكيد'), findsNothing);
          expect(
            find.text(
              'Your tracking is still saved — we just could not verify '
              'it well enough for a Fiqh conclusion.',
            ),
            findsOneWidget,
            reason:
                'a quarantined row is itself materially incomplete '
                'evidence — never confidently ruled from',
          );
        },
      );

      // Shared by both materiality tests below — a completed June
      // episode plus several real, unambiguous medium-flow days on the
      // open August episode, so fiqhCalculation.hasSufficientHistory is
      // satisfied by the real data alone. This isolates the one thing
      // each test actually varies (WHERE the excluded uncertain day
      // falls) from the separate, already-covered "insufficient
      // history" guard — otherwise a too-thin fixture could pass for
      // the wrong reason.
      final endedJuneEpisode = BleedingEpisode(
        id: 'episode-june',
        userId: 'user-1',
        lifecycleStatus: LifecycleStatus.ended,
        startDate: DateTime(2026, 6, 1),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userObserved,
        endDate: DateTime(2026, 6, 8),
        endPrecision: ObservationPrecision.dateOnly,
        endSource: ObservationSource.userObserved,
      );
      List<BleedingObservation> juneObservations() => [
        BleedingObservation(
          id: 'obs-june-start',
          userId: 'user-1',
          episodeId: 'episode-june',
          observedDate: DateTime(2026, 6, 1),
          precision: ObservationPrecision.dateOnly,
          flow: ObservationFlow.medium,
          source: ObservationSource.userObserved,
          utcOffsetMinutes: 0,
        ),
        BleedingObservation(
          id: 'obs-june-end',
          userId: 'user-1',
          episodeId: 'episode-june',
          observedDate: DateTime(2026, 6, 8),
          precision: ObservationPrecision.dateOnly,
          flow: ObservationFlow.none,
          source: ObservationSource.userObserved,
          utcOffsetMinutes: 0,
        ),
      ];
      final openAugustEpisode = BleedingEpisode(
        id: 'episode-open',
        userId: 'user-1',
        lifecycleStatus: LifecycleStatus.open,
        continuationCertainty: ContinuationCertainty.confirmed,
        startDate: DateTime(2026, 8, 10),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userObserved,
      );
      List<BleedingObservation> augustRealObservations() => [
        for (var day = 10; day <= 13; day++)
          BleedingObservation(
            id: 'obs-aug-$day',
            userId: 'user-1',
            episodeId: 'episode-open',
            observedDate: DateTime(2026, 8, day),
            precision: ObservationPrecision.dateOnly,
            flow: ObservationFlow.medium,
            source: ObservationSource.userObserved,
            utcOffsetMinutes: 0,
          ),
      ];

      testWidgets(
        'an excluded "I\'m not sure" day ON/AFTER the open episode\'s own '
        'start date is material — restricts the conclusion',
        (tester) async {
          final uncertainDuringEpisode = BleedingObservation(
            id: 'obs-uncertain',
            userId: 'user-1',
            episodeId: 'episode-open',
            observedDate: DateTime(2026, 8, 14),
            precision: ObservationPrecision.dateOnly,
            flow: ObservationFlow.uncertain,
            source: ObservationSource.userObserved,
            utcOffsetMinutes: 0,
          );

          await pumpDashboard(
            tester,
            legacyLogs: _sufficientLegacyLogs,
            repository: _FakeCanonicalRepository(
              episodes: [endedJuneEpisode, openAugustEpisode],
              observations: [
                ...juneObservations(),
                ...augustRealObservations(),
                uncertainDuringEpisode,
              ],
            ),
          );

          // A real open episode routes the dashboard to the factual
          // "bleeding right now" card (_FactualOpenEpisodeCard), not the
          // ring/_FiqhEvidenceUnresolvedCard branch — _PrayerStatusCard
          // is the unconditional surface that still must show this
          // restriction regardless of which branch renders above it.
          final scrollable = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
          await tester.pumpAndSettle();

          expect(
            find.text(
              "We couldn't verify your tracking data right now — your "
              "Fiqh state can't be confirmed.",
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'an excluded "I\'m not sure" day BEFORE the open episode started '
        'is old, already-concluded history — not material, does not '
        'restrict today\'s conclusion',
        (tester) async {
          final uncertainLongBefore = BleedingObservation(
            id: 'obs-uncertain-old',
            userId: 'user-1',
            episodeId: 'episode-june',
            observedDate: DateTime(2026, 5, 1),
            precision: ObservationPrecision.dateOnly,
            flow: ObservationFlow.uncertain,
            source: ObservationSource.userObserved,
            utcOffsetMinutes: 0,
          );

          await pumpDashboard(
            tester,
            legacyLogs: _sufficientLegacyLogs,
            repository: _FakeCanonicalRepository(
              episodes: [endedJuneEpisode, openAugustEpisode],
              observations: [
                uncertainLongBefore,
                ...juneObservations(),
                ...augustRealObservations(),
              ],
            ),
          );

          final scrollable = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
          await tester.pumpAndSettle();

          expect(
            find.text(
              "We couldn't verify your tracking data right now — your "
              "Fiqh state can't be confirmed.",
            ),
            findsNothing,
            reason:
                'a gap from already-concluded, months-old history must '
                'not restrict a conclusion about the present',
          );
        },
      );
    },
  );
}
