// Fiqh hardening regression tests (finding first proven failing on
// 2026-10-18): ClientFiqhStateProvider (the AI advisor's `clientFiqhState`)
// must agree with the dashboard for the same user — it reads the same
// canonical evidence through the same CanonicalFiqhAssessment.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/ai_advisor/client_fiqh_state_provider.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

class _Repo extends BleedingEpisodeRepositoryImpl {
  _Repo(this.episodes, this.observations, {this.quarantined = 0})
    : super(client: null);
  final List<BleedingEpisode> episodes;
  final List<BleedingObservation> observations;
  final int quarantined;
  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String u,
  ) async => LoadSuccess(episodes);
  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String u,
  ) async => quarantined > 0
      ? LoadDegraded(observations, quarantined)
      : LoadSuccess(observations);
}

int _n = 0;
BleedingObservation _o(String ep, DateTime d, ObservationFlow f) =>
    BleedingObservation(
      id: 'o${_n++}',
      userId: 'u',
      episodeId: ep,
      observedDate: d,
      precision: ObservationPrecision.dateOnly,
      flow: f,
      source: ObservationSource.userObserved,
      utcOffsetMinutes: 0,
    );

BleedingEpisode _episode(
  String id,
  DateTime start, {
  DateTime? end,
}) => BleedingEpisode(
  id: id,
  userId: 'u',
  lifecycleStatus: end == null ? LifecycleStatus.open : LifecycleStatus.ended,
  continuationCertainty: end == null ? ContinuationCertainty.confirmed : null,
  startDate: start,
  startPrecision: ObservationPrecision.dateOnly,
  startSource: ObservationSource.userObserved,
  endDate: end,
  endPrecision: end == null ? null : ObservationPrecision.dateOnly,
  endSource: end == null ? null : ObservationSource.userObserved,
);

final _now = DateTime(2026, 8, 18, 12);

/// Two completed cycles (June, July) + an open episode from [openStart].
_Repo _withHistory(DateTime openStart, {int quarantined = 0}) => _Repo(
  [
    _episode('jun', DateTime(2026, 6, 1), end: DateTime(2026, 6, 7)),
    _episode('jul', DateTime(2026, 7, 1), end: DateTime(2026, 7, 7)),
    _episode('open', openStart),
  ],
  [
    for (var d = 1; d <= 6; d++)
      _o('jun', DateTime(2026, 6, d), ObservationFlow.medium),
    _o('jun', DateTime(2026, 6, 7), ObservationFlow.none),
    for (var d = 1; d <= 6; d++)
      _o('jul', DateTime(2026, 7, d), ObservationFlow.medium),
    _o('jul', DateTime(2026, 7, 7), ObservationFlow.none),
    for (var d = openStart.day; d <= 18; d++)
      _o('open', DateTime(2026, 8, d), ObservationFlow.heavy),
  ],
  quarantined: quarantined,
);

Future<String?> _classify(_Repo repo, Madhhab? madhhab, {String? user = 'u'}) =>
    ClientFiqhStateProvider(
      repository: repo,
      currentUserId: () => user,
      clock: () => _now,
    ).currentClassification(madhhab);

void main() {
  test(
    'first-ever bleeding episode (insufficient history): the AI is never '
    'told "tahara" while the dashboard shows "Not enough history yet"',
    () async {
      final repo = _Repo(
        [_episode('open', DateTime(2026, 8, 15))],
        [
          for (var d = 15; d <= 18; d++)
            _o('open', DateTime(2026, 8, d), ObservationFlow.heavy),
        ],
      );
      expect(await _classify(repo, Madhhab.shafii), 'insufficientHistory');
    },
  );

  test('a canonical state is forwarded exactly as the dashboard shows '
      'it', () async {
    expect(
      await _classify(_withHistory(DateTime(2026, 8, 14)), Madhhab.shafii),
      'haid',
    );
    expect(
      await _classify(_withHistory(DateTime(2026, 8, 14)), null),
      'madhhabUnresolved',
    );
    // Hanafi day 2 of bleeding: below the 72h minimum -> not a ruling.
    expect(
      await _classify(_withHistory(DateTime(2026, 8, 17)), Madhhab.hanafi),
      'needsAdvisory',
    );
  });

  test('unverifiable evidence (quarantined row) or no session sends '
      'nothing', () async {
    expect(
      await _classify(
        _withHistory(DateTime(2026, 8, 14), quarantined: 1),
        Madhhab.shafii,
      ),
      isNull,
    );
    expect(
      await _classify(
        _withHistory(DateTime(2026, 8, 14)),
        Madhhab.shafii,
        user: null,
      ),
      isNull,
    );
  });
}
