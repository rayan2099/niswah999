// Pregnancy/notifications hardening (2026-10-21) — regression test for
// finding 1: during active nifas the dashboard used to show the Nifas card
// ("salah is lifted while bleeding continues") AND the Haid-engine-driven
// prayer card asserting "Salah is obligatory". The prayer card now defers
// to the Nifas card (unresolved, "Unknown" per prayer) and the Fiqh banner
// is hidden.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import '../support/parity_test_harness.dart';

class _Repo extends BleedingEpisodeRepositoryImpl {
  _Repo(this.episodes, this.observations) : super(client: null);
  final List<BleedingEpisode> episodes;
  final List<BleedingObservation> observations;
  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String u,
  ) async => LoadSuccess(episodes);
  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String u,
  ) async => LoadSuccess(observations);
}

int _n = 0;
BleedingObservation _o(String ep, DateTime d, ObservationFlow f) =>
    BleedingObservation(
      id: 'o${_n++}',
      userId: 'user-1',
      episodeId: ep,
      observedDate: d,
      precision: ObservationPrecision.dateOnly,
      flow: f,
      source: ObservationSource.userObserved,
      utcOffsetMinutes: 0,
    );

BleedingEpisode _ended(String id, DateTime s, DateTime e) => BleedingEpisode(
  id: id,
  userId: 'user-1',
  lifecycleStatus: LifecycleStatus.ended,
  startDate: s,
  startPrecision: ObservationPrecision.dateOnly,
  startSource: ObservationSource.userObserved,
  endDate: e,
  endPrecision: ObservationPrecision.dateOnly,
  endSource: ObservationSource.userObserved,
);

/// Pre-pregnancy history: two completed cycles, nothing open.
_Repo _history() => _Repo(
  [
    _ended('a', DateTime(2025, 10, 1), DateTime(2025, 10, 7)),
    _ended('b', DateTime(2025, 10, 29), DateTime(2025, 11, 4)),
  ],
  [
    for (var d = 1; d <= 6; d++)
      _o('a', DateTime(2025, 10, d), ObservationFlow.medium),
    _o('a', DateTime(2025, 10, 7), ObservationFlow.none),
    for (var d = 29; d <= 31; d++)
      _o('b', DateTime(2025, 10, d), ObservationFlow.medium),
    for (var d = 1; d <= 3; d++)
      _o('b', DateTime(2025, 11, d), ObservationFlow.medium),
    _o('b', DateTime(2025, 11, 4), ObservationFlow.none),
  ],
);

void main() {
  testWidgets('nifas day 3: prayer card defers to the Nifas card', (
    tester,
  ) async {
    // Harness clock: 2026-08-18 12:00. Birth logged 2026-08-16 10:00.
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      extraPrefs: {'niswah_nifas_started_at': '2026-08-16T10:00:00.000'},
    );
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      extraPrefs: {'niswah_nifas_started_at': '2026-08-16T10:00:00.000'},
      homeOverride: DashboardScreen(
        canonicalRepositoryOverride: _history(),
        canonicalUserIdOverride: 'user-1',
      ),
    );
    await tester.pumpAndSettle();
    expect(PregnancyStatusController.instance.isNifasActive, isTrue);
    expect(
      find.byKey(const Key('nifas-status')),
      findsOneWidget,
      reason: 'precondition: the Nifas card is on screen',
    );
    expect(
      find.textContaining('salah is lifted while bleeding continues'),
      findsOneWidget,
    );

    final s = tester.state<ScrollableState>(find.byType(Scrollable).first);
    s.position.jumpTo(s.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Salah is obligatory'), findsNothing);
    expect(find.textContaining('obligatory'), findsNothing);
    expect(find.text('Salah is lifted'), findsNothing);
    expect(find.text('See your Nifas status above'), findsOneWidget);
    expect(find.text('Unknown'), findsNWidgets(5));
  });
}
