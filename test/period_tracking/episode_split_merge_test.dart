import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/episode_correction_repository.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/episode_edit_sheet.dart';

import '../logging_sync_hardening/support/fake_supabase.dart';
import '../support/device_timezone_test_support.dart';
import '../support/secure_storage_test_support.dart';

/// Splitting one period in two and joining two into one (PT-045, PT-046):
/// the app side of
/// supabase/migrations/20261030012106_bleeding_episode_split_merge.sql.
/// The server rules (entries moved never rewritten, gap days left
/// unanswered, preview before confirm, undo, tombstones) are proven in
/// test/security/bleeding_episode_split_merge.sql.

const _user = 'a0000000-0000-4000-8000-00000000000a';
const _first = 'e0000000-0000-4000-8000-00000000000e';
const _second = 'e0000000-0000-4000-8000-00000000000f';

BleedingEpisode _episode({
  String id = _first,
  required DateTime start,
  DateTime? end,
  String token = '2026-10-20T10:00:00.123456+00:00',
}) => BleedingEpisode(
  id: id,
  userId: _user,
  lifecycleStatus: end == null ? LifecycleStatus.open : LifecycleStatus.ended,
  continuationCertainty: end == null ? ContinuationCertainty.confirmed : null,
  startDate: start,
  startPrecision: ObservationPrecision.dateOnly,
  startSource: ObservationSource.userReportedHistorical,
  endDate: end,
  endPrecision: end == null ? null : ObservationPrecision.dateOnly,
  endSource: end == null ? null : ObservationSource.userReportedHistorical,
  revisionToken: token,
);

Map<String, dynamic> _obsJson(
  String id,
  String episodeId,
  String date,
  String flow, {
  String? supersedes,
}) => {
  'id': id,
  'user_id': _user,
  'episode_id': episodeId,
  'observed_date': date,
  'observed_time': null,
  'precision': 'date_only',
  'flow': flow,
  'source': 'user_reported_historical',
  'reported_at': '2026-10-20T10:00:00Z',
  'timezone': 'UTC',
  'utc_offset_minutes': 0,
  'symptoms': null,
  'notes': null,
  'supersedes_id': supersedes,
  'client_operation_id': null,
};

class _RecordingCycleLogs extends CycleTrackingRepositoryImpl {
  _RecordingCycleLogs() : super(client: null);

  final deleted = <String>[];
  final saved = <String>[];

  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async => const [];

  @override
  Future<void> deleteCycleLog(String id) async => deleted.add(id);

  @override
  Future<SyncStatus> saveCycleLog(CycleLog log) async {
    saved.add(log.id);
    return SyncStatus.synced;
  }
}

/// Serves `bleeding_observations` per episode from [before] until the RPC
/// ran, then from [after].
class _Server {
  _Server({
    required this.before,
    required this.after,
    required http.Response Function(String name, Map<String, dynamic>? body)
    rpc,
  }) {
    fake = FakeSupabase((name, body) async {
      sent = body;
      rpcDone = true;
      return rpc(name, body);
    });
    fake.onTable = (request) async {
      final query = request.url.query;
      final episodes = rpcDone ? after : before;
      for (final entry in episodes.entries) {
        if (query.contains(entry.key)) return jsonResponse(entry.value);
      }
      return jsonResponse(<Object>[]);
    };
  }

  final Map<String, List<Map<String, dynamic>>> before;
  final Map<String, List<Map<String, dynamic>>> after;
  late final FakeSupabase fake;
  Map<String, dynamic>? sent;
  bool rpcDone = false;

  EpisodeCorrectionRepository repository(_RecordingCycleLogs logs) =>
      EpisodeCorrectionRepository(
        client: fake.client,
        cycleLogs: logs,
        refreshReminders: (_) async {},
        currentUserId: () => _user,
      );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    mockDeviceTimezoneForTest();
    AppLocaleController.instance.setArabic(false);
    AppClock.now = () => DateTime(2026, 10, 25, 12);
  });
  tearDown(() {
    AppClock.reset();
    SecureLocalStore.debugUserIdOverride = null;
  });

  group('EpisodeCorrectionRepository split/merge', () {
    final start = _obsJson('o-1', _first, '2026-10-01', 'medium');
    final day3 = _obsJson('o-3', _first, '2026-10-03', 'light');
    final day8 = _obsJson('o-8', _first, '2026-10-08', 'heavy');
    final day9 = _obsJson('o-9', _first, '2026-10-09', 'medium');

    test('PT-045: a split preview sends confirm=false and reports how many '
        'entries would move, changing nothing (NW422)', () async {
      final server = _Server(
        before: {
          _first: [start, day3, day8, day9],
        },
        after: {
          _first: [start, day3, day8, day9],
        },
        rpc: (name, body) => jsonResponse({
          'code': 'NW422',
          'message': '2 entries would move to the second period',
          'details': '2',
          'hint': null,
        }, 400),
      );
      final logs = _RecordingCycleLogs();
      final result = await server
          .repository(logs)
          .splitEpisode(
            clientOperationId: 'op-1',
            episode: _episode(start: DateTime(2026, 10, 1)),
            secondStartDate: DateTime(2026, 10, 8),
            firstEndDate: DateTime(2026, 10, 5),
            timezone: 'UTC',
            utcOffsetMinutes: 0,
          );

      expect(server.fake.rpcCalls, ['split_episode']);
      expect(server.sent!['p_second_start_date'], '2026-10-08');
      expect(server.sent!['p_first_end_date'], '2026-10-05');
      expect(server.sent!['p_confirm'], isFalse);
      expect(
        server.sent!['p_expected_updated_at'],
        '2026-10-20T10:00:00.123456+00:00',
      );
      expect(result.status, EpisodeEditStatus.needsConfirmation);
      expect(result.conflictingCount, 2);
      expect(logs.deleted, isEmpty);
      expect(logs.saved, isEmpty);
    });

    test('PT-045: an unknown first end is sent as null, never a guessed '
        'date; moved entries keep their mirror and only the clean day she '
        'gave is added', () async {
      final server = _Server(
        before: {
          _first: [start, day3, day8, day9],
        },
        after: {
          _first: [
            start,
            day3,
            _obsJson('o-clean', _first, '2026-10-05', 'none'),
          ],
          _second: [
            _obsJson('o-8', _second, '2026-10-08', 'heavy'),
            _obsJson('o-9', _second, '2026-10-09', 'medium'),
          ],
        },
        rpc: (name, body) => jsonResponse([
          {
            'episode_id': _first,
            'second_episode_id': _second,
            'revision_id': 'rev-split',
          },
        ]),
      );
      final logs = _RecordingCycleLogs();
      final repo = server.repository(logs);

      final unknown = await repo.splitEpisode(
        clientOperationId: 'op-2',
        episode: _episode(start: DateTime(2026, 10, 1)),
        secondStartDate: DateTime(2026, 10, 8),
        firstEndDate: null,
        timezone: 'UTC',
        utcOffsetMinutes: 0,
        confirm: true,
      );
      expect(server.sent!.containsKey('p_first_end_date'), isTrue);
      expect(server.sent!['p_first_end_date'], isNull);
      expect(server.sent!['p_confirm'], isTrue);
      expect(unknown.saved, isTrue);
      expect(unknown.revisionId, 'rev-split');
      expect(unknown.secondEpisodeId, _second);
      expect(
        logs.deleted,
        isEmpty,
        reason: 'moved entries are the same entries; nothing is re-created',
      );
      expect(logs.saved, ['o-clean']);
    });

    test('PT-045: undoing a split deletes only the clean day the split added '
        'from this device', () async {
      final server = _Server(
        before: {
          _first: [
            start,
            day3,
            _obsJson('o-clean', _first, '2026-10-05', 'none'),
          ],
          _second: [
            _obsJson('o-8', _second, '2026-10-08', 'heavy'),
            _obsJson('o-9', _second, '2026-10-09', 'medium'),
          ],
        },
        after: {
          _first: [start, day3, day8, day9],
        },
        rpc: (name, body) => jsonResponse([
          {'episode_id': _first, 'revision_id': 'rev-undo'},
        ]),
      );
      final logs = _RecordingCycleLogs();
      final result = await server
          .repository(logs)
          .undoSplit(
            clientOperationId: 'op-3',
            episodeId: _first,
            secondEpisodeId: _second,
            splitRevisionId: 'rev-split',
          );
      expect(server.fake.rpcCalls, ['undo_episode_split']);
      expect(server.sent!['p_split_revision_id'], 'rev-split');
      expect(result.saved, isTrue);
      expect(logs.deleted, ['o-clean']);
      expect(logs.saved, isEmpty);
    });

    test('PT-046: a merge sends both revision tokens; the entries of both '
        'periods stay mirrored, none deleted or added', () async {
      final a = [start, _obsJson('o-close', _first, '2026-10-04', 'none')];
      final b = [
        _obsJson('o-10', _second, '2026-10-10', 'medium'),
        _obsJson('o-13', _second, '2026-10-13', 'none'),
      ];
      final server = _Server(
        before: {_first: a, _second: b},
        after: {
          _first: [
            ...a,
            for (final o in b) {...o, 'episode_id': _first},
          ],
        },
        rpc: (name, body) => jsonResponse([
          {'episode_id': _first, 'revision_id': 'rev-merge'},
        ]),
      );
      final logs = _RecordingCycleLogs();
      final result = await server
          .repository(logs)
          .mergeEpisodes(
            clientOperationId: 'op-4',
            first: _episode(
              start: DateTime(2026, 10, 1),
              end: DateTime(2026, 10, 4),
            ),
            second: _episode(
              id: _second,
              start: DateTime(2026, 10, 10),
              end: DateTime(2026, 10, 13),
              token: '2026-10-21T10:00:00.000001+00:00',
            ),
            confirm: true,
          );
      expect(server.fake.rpcCalls, ['merge_episodes']);
      expect(server.sent!['p_first_episode_id'], _first);
      expect(server.sent!['p_second_episode_id'], _second);
      expect(
        server.sent!['p_expected_first_updated_at'],
        '2026-10-20T10:00:00.123456+00:00',
      );
      expect(
        server.sent!['p_expected_second_updated_at'],
        '2026-10-21T10:00:00.000001+00:00',
      );
      expect(server.sent!['p_confirm'], isTrue);
      expect(result.saved, isTrue);
      expect(logs.deleted, isEmpty);
      expect(logs.saved, isEmpty);
    });

    test('an undo refused because the period changed since is reported as '
        'changed, never applied (NW409)', () async {
      final server = _Server(
        before: const {},
        after: const {},
        rpc: (name, body) => pgError(
          'NW409',
          'the period changed after the merge; it can no longer be undone',
        ),
      );
      final logs = _RecordingCycleLogs();
      final result = await server
          .repository(logs)
          .undoMerge(
            clientOperationId: 'op-5',
            episodeId: _first,
            mergeRevisionId: 'rev-merge',
          );
      expect(result.status, EpisodeEditStatus.changedElsewhere);
      expect(logs.deleted, isEmpty);
    });
  });

  group('Edit sheet split/merge', () {
    Future<_FakeCorrections> pumpSheet(
      WidgetTester tester, {
      required BleedingEpisode episode,
      List<BleedingEpisode> others = const [],
      List<Map<String, dynamic>>? observations,
      List<EpisodeEditResult> results = const [],
      void Function()? onChanged,
    }) async {
      final corrections = _FakeCorrections(results);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showEpisodeEditSheet(
                  context,
                  episode: episode,
                  isLatestEpisode: false,
                  hasOpenEpisode: false,
                  onChanged: onChanged,
                  episodes: _FakeEpisodes(
                    episodes: [episode, ...others],
                    observations:
                        observations ??
                        [
                          _obsJson('o-1', _first, '2026-10-01', 'medium'),
                          _obsJson('o-3', _first, '2026-10-03', 'light'),
                          _obsJson('o-8', _first, '2026-10-08', 'heavy'),
                          _obsJson('o-9', _first, '2026-10-09', 'medium'),
                          _obsJson('o-close', _first, '2026-10-12', 'none'),
                        ],
                  ),
                  repositoryOverride: corrections,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return corrections;
    }

    Future<void> scrollTo(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('PT-045: only recorded bleeding days are offered as the '
        'second start; the preview says how many entries move and nothing '
        'is saved before she confirms; Undo undoes that split', (tester) async {
      var changes = 0;
      final corrections = await pumpSheet(
        tester,
        episode: _episode(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 12),
        ),
        results: const [
          EpisodeEditResult(
            EpisodeEditStatus.needsConfirmation,
            conflictingCount: 2,
          ),
          EpisodeEditResult(
            EpisodeEditStatus.saved,
            revisionId: 'rev-split',
            secondEpisodeId: _second,
          ),
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'rev-undo'),
        ],
        onChanged: () => changes++,
      );

      await tester.tap(find.byKey(const Key('episode-edit-split')));
      await tester.pumpAndSettle();
      // The start day, the clean day and unrecorded days are not choices.
      expect(
        find.byKey(const Key('episode-split-day-2026-10-01')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('episode-split-day-2026-10-12')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('episode-split-day-2026-10-05')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('episode-split-day-2026-10-03')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('episode-split-day-2026-10-08')));
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('episode-split-save'));
      await scrollTo(tester, save);
      expect(
        tester.widget<FilledButton>(save).onPressed,
        isNull,
        reason: 'the first part needs an end or an explicit "I don\'t know"',
      );

      await scrollTo(
        tester,
        find.byKey(const Key('episode-split-end-unknown')),
      );
      await tester.tap(find.byKey(const Key('episode-split-end-unknown')));
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(corrections.calls, ['split:2026-10-08:unknown:false']);
      expect(
        find.textContaining('2 entries from 8 October 2026 on will move'),
        findsOneWidget,
      );
      expect(find.textContaining('stay unrecorded'), findsOneWidget);

      await tester.tap(find.byKey(const Key('episode-split-confirm')));
      await tester.pumpAndSettle();
      expect(corrections.calls, [
        'split:2026-10-08:unknown:false',
        'split:2026-10-08:unknown:true',
      ]);
      expect(find.text('Edit this period'), findsNothing, reason: 'closed');
      expect(find.text('Period split in two.'), findsOneWidget);
      expect(changes, 1);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(corrections.calls.last, 'undo-split:$_first:$_second:rev-split');
      expect(find.text('Split undone.'), findsOneWidget);
      expect(changes, 2);
    });

    testWidgets('PT-045: the first clean day she picks is sent as given', (
      tester,
    ) async {
      final corrections = await pumpSheet(
        tester,
        episode: _episode(start: DateTime(2026, 10, 1)),
        results: const [
          EpisodeEditResult(
            EpisodeEditStatus.needsConfirmation,
            conflictingCount: 2,
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('episode-edit-split')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('episode-split-day-2026-10-08')));
      await tester.pumpAndSettle();
      final pick = find.byKey(const Key('episode-split-first-end'));
      await scrollTo(tester, pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('5 October 2026'), findsOneWidget);
      final save = find.byKey(const Key('episode-split-save'));
      await scrollTo(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(corrections.calls, ['split:2026-10-08:2026-10-05:false']);
    });

    testWidgets('PT-045: cancelling the preview saves nothing and keeps her '
        'choices', (tester) async {
      final corrections = await pumpSheet(
        tester,
        episode: _episode(start: DateTime(2026, 10, 1)),
        results: const [
          EpisodeEditResult(
            EpisodeEditStatus.needsConfirmation,
            conflictingCount: 2,
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('episode-edit-split')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('episode-split-day-2026-10-08')));
      await tester.pumpAndSettle();
      await scrollTo(
        tester,
        find.byKey(const Key('episode-split-end-unknown')),
      );
      await tester.tap(find.byKey(const Key('episode-split-end-unknown')));
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('episode-split-save'));
      await scrollTo(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(corrections.calls, ['split:2026-10-08:unknown:false']);
      expect(find.text('Edit this period'), findsOneWidget);
    });

    testWidgets('PT-045: a period with no later bleeding day explains why it '
        'cannot be split', (tester) async {
      await pumpSheet(
        tester,
        episode: _episode(start: DateTime(2026, 10, 1)),
        observations: [_obsJson('o-1', _first, '2026-10-01', 'medium')],
      );
      await tester.tap(find.byKey(const Key('episode-edit-split')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('episode-split-no-days')), findsOneWidget);
    });

    testWidgets('PT-046: "Join with the next period" is offered only for an '
        'ended period with a later one; it previews, then joins, and Undo '
        'undoes that merge', (tester) async {
      final first = _episode(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 4),
      );
      final next = _episode(
        id: _second,
        start: DateTime(2026, 10, 10),
        end: DateTime(2026, 10, 13),
      );
      final later = _episode(
        id: 'e0000000-0000-4000-8000-000000000010',
        start: DateTime(2026, 10, 20),
      );
      final corrections = await pumpSheet(
        tester,
        episode: first,
        others: [later, next],
        results: const [
          EpisodeEditResult(
            EpisodeEditStatus.needsConfirmation,
            conflictingCount: 2,
          ),
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'rev-merge'),
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'rev-undo'),
        ],
      );
      final merge = find.byKey(const Key('episode-edit-merge'));
      expect(merge, findsOneWidget);
      expect(
        find.textContaining('The next one started 10 October 2026'),
        findsOneWidget,
        reason: 'the neighbour, not a later period',
      );

      await tester.tap(merge);
      await tester.pumpAndSettle();
      expect(corrections.calls, ['merge:$_first:$_second:false']);
      expect(find.textContaining('stay unrecorded'), findsOneWidget);
      await tester.tap(find.byKey(const Key('episode-merge-confirm')));
      await tester.pumpAndSettle();
      expect(corrections.calls.last, 'merge:$_first:$_second:true');
      expect(find.text('Periods joined.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(corrections.calls.last, 'undo-merge:$_first:rev-merge');
      expect(find.text('Join undone.'), findsOneWidget);
    });

    testWidgets('PT-046: no join is offered for an open period or the last '
        'one', (tester) async {
      await pumpSheet(
        tester,
        episode: _episode(start: DateTime(2026, 10, 1)),
        others: [
          _episode(
            id: _second,
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 6),
          ),
        ],
      );
      expect(find.byKey(const Key('episode-edit-merge')), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await pumpSheet(
        tester,
        episode: _episode(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 4),
        ),
        others: [
          _episode(
            id: _second,
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 6),
          ),
        ],
      );
      expect(find.byKey(const Key('episode-edit-merge')), findsNothing);
    });

    testWidgets('an Undo refused because the period changed since says so', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        episode: _episode(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 4),
        ),
        others: [
          _episode(
            id: _second,
            start: DateTime(2026, 10, 10),
            end: DateTime(2026, 10, 13),
          ),
        ],
        results: const [
          EpisodeEditResult(
            EpisodeEditStatus.needsConfirmation,
            conflictingCount: 1,
          ),
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'rev-merge'),
          EpisodeEditResult(
            EpisodeEditStatus.changedElsewhere,
            serverMessage:
                'the period changed after the merge; it can no longer be '
                'undone',
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('episode-edit-merge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('episode-merge-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'can no longer be undone because the period '
          'changed',
        ),
        findsOneWidget,
      );
    });
  });
}

class _FakeEpisodes extends BleedingEpisodeRepositoryImpl {
  _FakeEpisodes({required this.episodes, required this.observations})
    : super(client: null);

  final List<BleedingEpisode> episodes;
  final List<Map<String, dynamic>> observations;

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async => LoadSuccess(episodes);

  @override
  Future<LoadResult<List<BleedingObservation>>> getObservationsForEpisode(
    String episodeId,
  ) async => LoadSuccess([
    for (final o in observations) BleedingObservation.fromJson(o),
  ]);
}

class _FakeCorrections extends EpisodeCorrectionRepository {
  _FakeCorrections(List<EpisodeEditResult> results)
    : _results = [...results],
      super(client: null);

  final List<EpisodeEditResult> _results;
  final calls = <String>[];

  EpisodeEditResult _next(String call) {
    calls.add(call);
    return _results.isEmpty
        ? const EpisodeEditResult(EpisodeEditStatus.saved)
        : _results.removeAt(0);
  }

  static String _d(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Future<EpisodeEditResult> splitEpisode({
    required String clientOperationId,
    required BleedingEpisode episode,
    required DateTime secondStartDate,
    required DateTime? firstEndDate,
    required String? timezone,
    required int utcOffsetMinutes,
    bool confirm = false,
  }) async => _next(
    'split:${_d(secondStartDate)}:'
    '${firstEndDate == null ? 'unknown' : _d(firstEndDate)}:$confirm',
  );

  @override
  Future<EpisodeEditResult> mergeEpisodes({
    required String clientOperationId,
    required BleedingEpisode first,
    required BleedingEpisode second,
    bool confirm = false,
  }) async => _next('merge:${first.id}:${second.id}:$confirm');

  @override
  Future<EpisodeEditResult> undoSplit({
    required String clientOperationId,
    required String episodeId,
    required String secondEpisodeId,
    required String splitRevisionId,
  }) async => _next('undo-split:$episodeId:$secondEpisodeId:$splitRevisionId');

  @override
  Future<EpisodeEditResult> undoMerge({
    required String clientOperationId,
    required String episodeId,
    required String mergeRevisionId,
  }) async => _next('undo-merge:$episodeId:$mergeRevisionId');
}
