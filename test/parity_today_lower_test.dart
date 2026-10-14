import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import 'support/parity_test_harness.dart';

/// New critical finding (Fiqh regression fix), mirrored from
/// parity_today_stepper_consistency_test.dart's own [_FakeCanonicalRepository]
/// (private to that file, so redefined here rather than shared): a fake,
/// in-memory canonical repository so this real Haid-state scenario can
/// supply genuine canonical evidence without a real Supabase backend.
/// This test's own goal (the lower Fiqh-state banner showing a real
/// Haid ruling) is unreachable through the full NiswahApp shell at all --
/// NiswahApp always constructs DashboardScreen with a null Supabase
/// client, which makes canonical evidence LoadUnavailable, which in turn
/// renders _FiqhEvidenceUnresolvedCard instead of a real ruling (see
/// dashboard_screen.dart's own doc comment: "a Fiqh ruling must never be
/// drawn from evidence that is unavailable"). Mounting DashboardScreen
/// directly with this override, the same pattern the stepper-consistency
/// test already established, is the only way to exercise a real ruling.
class _FakeCanonicalRepository extends BleedingEpisodeRepositoryImpl {
  _FakeCanonicalRepository({
    this.episodes = const [],
    this.observations = const [],
  }) : super(client: null);

  final List<BleedingEpisode> episodes;
  final List<BleedingObservation> observations;

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async => LoadSuccess(episodes);

  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String userId,
  ) async => LoadSuccess(observations);
}

void main() {
  testWidgets('Today lower Fiqh state matches the Arabic mobile reference', (
    tester,
  ) async {
    // Fixed clock (via ParityTestHarness.pump) is 2026-08-18 12:00 --
    // matched below so the open August episode is a real, currently
    // in-progress Haid, not a stale/future one.
    final episodes = [
      BleedingEpisode(
        id: 'episode-june',
        userId: 'user-1',
        lifecycleStatus: LifecycleStatus.ended,
        startDate: DateTime(2026, 6, 1),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userObserved,
        endDate: DateTime(2026, 6, 8),
        endPrecision: ObservationPrecision.dateOnly,
        endSource: ObservationSource.userObserved,
      ),
      BleedingEpisode(
        id: 'episode-august',
        userId: 'user-1',
        lifecycleStatus: LifecycleStatus.open,
        continuationCertainty: ContinuationCertainty.confirmed,
        startDate: DateTime(2026, 8, 15),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userObserved,
      ),
    ];
    final observations = [
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
      for (var day = 15; day <= 18; day++)
        BleedingObservation(
          id: 'obs-aug-$day',
          userId: 'user-1',
          episodeId: 'episode-august',
          observedDate: DateTime(2026, 8, day),
          precision: ObservationPrecision.dateOnly,
          flow: ObservationFlow.medium,
          source: ObservationSource.userObserved,
          utcOffsetMinutes: 0,
        ),
    ];

    // Legacy-shaped logs still back the ring's own "is there enough
    // history" gate independently of canonical evidence (see
    // parity_today_stepper_consistency_test.dart's own
    // pumpDashboardWithCanonicalEvidence) -- without these, the Istihadah
    // toggle and ring never render regardless of what canonical evidence
    // says, since that gate is still legacy-derived.
    final legacyLogsJson = jsonEncode([
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
        'date': '2026-06-08T08:00:00.000',
        'flow': 'none',
        'cycle_day': 8,
        'sync_status': 'synced',
      },
      {
        'id': '3',
        'user_id': 'local-user',
        'date': '2026-08-15T08:00:00.000',
        'flow': 'medium',
        'cycle_day': 1,
        'sync_status': 'synced',
      },
    ]);

    await ParityTestHarness.pump(
      tester,
      arabic: true,
      extraPrefs: {
        'niswah_cycle_tracking_logs': legacyLogsJson,
        'flutter.niswah_cycle_tracking_logs': legacyLogsJson,
      },
      homeOverride: DashboardScreen(
        canonicalRepositoryOverride: _FakeCanonicalRepository(
          episodes: episodes,
          observations: observations,
        ),
        canonicalUserIdOverride: 'user-1',
      ),
    );
    // Must come after the harness's own pump() — that call is what
    // installs the SharedPreferences mock this selection needs to
    // persist against (same ordering constraint documented in
    // parity_cycle_log_sheet_test.dart).
    await MadhhabController.instance.selectMadhhab(Madhhab.hanbali);
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(900);
    await tester.pumpAndSettle();

    expect(find.text('وضع الاستحاضة'), findsOneWidget);
    expect(find.text('الصلاة مرفوعة عنكِ'), findsWidgets);
    expect(find.text('بناءً على المذهب الHANBALI'), findsOneWidget);
    await expectLater(
      find.byType(DashboardScreen),
      matchesGoldenFile('goldens/today_lower_ar_390x844.png'),
    );
  });
}
