// Fiqh hardening regression tests (finding first proven failing on
// 2026-10-18): the dashboard's unconditional _PrayerStatusCard rendered
// "Salah is obligatory" for every FiqhState except haid /
// evidenceUnresolved / insufficientHistory — including madhhabUnresolved
// and needsAdvisory. It now shows "Select your Madhhab" / "consult" copy
// and an "Unknown" status per prayer for those states.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/preferences/madhhab_controller.dart';
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

/// Two completed cycles (June, July) + an open episode starting [openStart],
/// logged daily through 2026-08-18 (ParityTestHarness's AppClock date).
_Repo _fixture(DateTime openStart) {
  final obs = <BleedingObservation>[
    for (var d = 1; d <= 6; d++)
      _o('jun', DateTime(2026, 6, d), ObservationFlow.medium),
    _o('jun', DateTime(2026, 6, 7), ObservationFlow.none),
    for (var d = 1; d <= 6; d++)
      _o('jul', DateTime(2026, 7, d), ObservationFlow.medium),
    _o('jul', DateTime(2026, 7, 7), ObservationFlow.none),
    for (var d = openStart.day; d <= 18; d++)
      _o('open', DateTime(2026, 8, d), ObservationFlow.heavy),
  ];
  return _Repo([
    _ended('jun', DateTime(2026, 6, 1), DateTime(2026, 6, 7)),
    _ended('jul', DateTime(2026, 7, 1), DateTime(2026, 7, 7)),
    BleedingEpisode(
      id: 'open',
      userId: 'user-1',
      lifecycleStatus: LifecycleStatus.open,
      continuationCertainty: ContinuationCertainty.confirmed,
      startDate: openStart,
      startPrecision: ObservationPrecision.dateOnly,
      startSource: ObservationSource.userObserved,
    ),
  ], obs);
}

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  await ParityTestHarness.pump(
    tester,
    arabic: false,
    homeOverride: DashboardScreen(
      canonicalRepositoryOverride: repo,
      canonicalUserIdOverride: 'user-1',
    ),
  );
  await tester.pumpAndSettle();
  final s = tester.state<ScrollableState>(find.byType(Scrollable).first);
  s.position.jumpTo(s.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('madhhab UNSET + currently bleeding: prayer card must not '
      'assert "Salah is obligatory"', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await MadhhabController.instance.load(); // empty prefs -> unset
    expect(MadhhabController.instance.selectedOrNull, isNull);
    await _pump(tester, _fixture(DateTime(2026, 8, 14)));

    // owner-e4-menstrual-journey.md §14: "Failure signal: a specific
    // ruling (Haid/Tahara/Istihadah) appears anyway, with no Madhhab
    // ever selected."
    expect(find.text('Salah is obligatory'), findsNothing);
    expect(find.text('Select your Madhhab'), findsWidgets);
    expect(find.text('Unknown'), findsNWidgets(5));
  });

  testWidgets('Hanafi, day 2 of bleeding (needsAdvisory "awaiting '
      'confirmation"): prayer card still asserts "Salah is obligatory"', (
    tester,
  ) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
    await _pump(tester, _fixture(DateTime(2026, 8, 17)));
    expect(find.text('Salah is obligatory'), findsNothing);
    expect(find.text('Please consult a trusted source'), findsOneWidget);
    expect(find.text('Unknown'), findsNWidgets(5));
  });

  testWidgets('Hanafi, day 5 of bleeding (confident haid): prayer card says '
      '"Salah is lifted"', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
    await _pump(tester, _fixture(DateTime(2026, 8, 14)));
    expect(find.text('Salah is obligatory'), findsNothing);
    expect(find.text('Salah is lifted'), findsWidgets);
  });
}
