import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
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

/// Period corrections (PT-027, PT-051..PT-057, PT-060, PT-145, PT-148):
/// the app side of supabase/migrations/20261029100000_bleeding_episode_corrections.sql.
/// The server rules themselves are proven in
/// test/security/bleeding_episode_corrections.sql.

const _user = 'a0000000-0000-4000-8000-00000000000a';
const _episodeId = 'e0000000-0000-4000-8000-00000000000e';

BleedingEpisode _ended({String? token = '2026-10-20T10:00:00.123456+00:00'}) =>
    BleedingEpisode(
      id: _episodeId,
      userId: _user,
      lifecycleStatus: LifecycleStatus.ended,
      startDate: DateTime(2026, 10, 10),
      startPrecision: ObservationPrecision.dateOnly,
      startSource: ObservationSource.userReportedHistorical,
      endDate: DateTime(2026, 10, 15),
      endPrecision: ObservationPrecision.dateOnly,
      endSource: ObservationSource.userReportedHistorical,
      revisionToken: token,
    );

Map<String, dynamic> _obsJson(
  String id,
  String date,
  String flow, {
  String? supersedes,
}) => {
  'id': id,
  'user_id': _user,
  'episode_id': _episodeId,
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

/// Records what the mirror resync does to this device's cycle_entries.
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

  group('EpisodeCorrectionRepository', () {
    test(
      'PT-052: a saved end correction sends her revision token and brings '
      'the device mirror in line (old closing entry out, new one in)',
      () async {
        Map<String, dynamic>? sent;
        var reads = 0;
        final fake = FakeSupabase((name, body) async {
          sent = body;
          return jsonResponse([
            {'episode_id': _episodeId, 'revision_id': 'rev-1'},
          ]);
        });
        fake.onTable = (request) async {
          reads++;
          // Before: start + closing on the 15th. After: the closing entry is
          // superseded by a new one on the 17th.
          return jsonResponse(
            reads == 1
                ? [
                    _obsJson('o-start', '2026-10-10', 'medium'),
                    _obsJson('o-close', '2026-10-15', 'none'),
                  ]
                : [
                    _obsJson('o-start', '2026-10-10', 'medium'),
                    _obsJson('o-close', '2026-10-15', 'none'),
                    _obsJson(
                      'o-close2',
                      '2026-10-17',
                      'none',
                      supersedes: 'o-close',
                    ),
                  ],
          );
        };
        final logs = _RecordingCycleLogs();
        final repo = EpisodeCorrectionRepository(
          client: fake.client,
          cycleLogs: logs,
        );

        final result = await repo.correctEnd(
          clientOperationId: 'op-1',
          episode: _ended(),
          newEndDate: DateTime(2026, 10, 17),
          timezone: 'UTC',
          utcOffsetMinutes: 0,
        );

        expect(result.status, EpisodeEditStatus.saved);
        expect(result.revisionId, 'rev-1');
        expect(fake.rpcCalls, ['correct_episode_end']);
        expect(sent!['p_new_end_date'], '2026-10-17');
        expect(
          sent!['p_expected_updated_at'],
          '2026-10-20T10:00:00.123456+00:00',
        );
        expect(sent!['p_retract_conflicting'], isFalse);
        expect(logs.deleted, ['o-close']);
        expect(logs.saved, ['o-close2']);
      },
    );

    test('PT-056: removing a period deletes every mirrored entry of it on '
        'this device', () async {
      var reads = 0;
      final fake = FakeSupabase(
        (name, body) async => jsonResponse([
          {'episode_id': _episodeId, 'revision_id': 'rev-2'},
        ]),
      );
      fake.onTable = (request) async {
        reads++;
        return jsonResponse(
          reads == 1
              ? [
                  _obsJson('o-start', '2026-10-10', 'medium'),
                  _obsJson('o-close', '2026-10-15', 'none'),
                ]
              : <Object>[],
        );
      };
      final logs = _RecordingCycleLogs();
      final result = await EpisodeCorrectionRepository(
        client: fake.client,
        cycleLogs: logs,
      ).remove(clientOperationId: 'op-2', episode: _ended());

      expect(result.saved, isTrue);
      expect(logs.deleted, unorderedEquals(['o-start', 'o-close']));
      expect(logs.saved, isEmpty);
    });

    test('a change that would take out her entries is not applied and says '
        'how many (NW422)', () async {
      final fake = FakeSupabase(
        (name, body) async => jsonResponse({
          'code': 'NW422',
          'message': '2 entries are recorded after 2026-10-12',
          'details': '2',
          'hint': null,
        }, 400),
      );
      final logs = _RecordingCycleLogs();
      final result =
          await EpisodeCorrectionRepository(
            client: fake.client,
            cycleLogs: logs,
          ).correctEnd(
            clientOperationId: 'op-3',
            episode: _ended(),
            newEndDate: DateTime(2026, 10, 12),
            timezone: 'UTC',
            utcOffsetMinutes: 0,
          );

      expect(result.status, EpisodeEditStatus.needsConfirmation);
      expect(result.conflictingCount, 2);
      expect(logs.deleted, isEmpty, reason: 'nothing changed on the server');
    });

    test('PT-060/PT-148: a change made on another device first is reported, '
        'never overwritten (NW409)', () async {
      final fake = FakeSupabase(
        (name, body) async => pgError(
          'NW409',
          'episode changed since it was loaded; reload and try again',
        ),
      );
      final result =
          await EpisodeCorrectionRepository(
            client: fake.client,
            cycleLogs: _RecordingCycleLogs(),
          ).correctStart(
            clientOperationId: 'op-4',
            episode: _ended(),
            newStartDate: DateTime(2026, 10, 9),
            flow: ObservationFlow.light,
            timezone: 'UTC',
            utcOffsetMinutes: 0,
          );
      expect(result.status, EpisodeEditStatus.changedElsewhere);
    });

    test('PT-054: an overlap refusal is a rejection, not "offline"', () async {
      final fake = FakeSupabase(
        (name, body) async => pgError(
          'P0001',
          'start_date (2026-10-01) overlaps an episode that ended on 2026-10-02',
        ),
      );
      final result =
          await EpisodeCorrectionRepository(
            client: fake.client,
            cycleLogs: _RecordingCycleLogs(),
          ).correctStart(
            clientOperationId: 'op-5',
            episode: _ended(),
            newStartDate: DateTime(2026, 10, 1),
            flow: ObservationFlow.light,
            timezone: 'UTC',
            utcOffsetMinutes: 0,
          );
      expect(result.status, EpisodeEditStatus.rejected);
      expect(result.serverMessage, contains('overlaps'));
    });

    test('PT-150: no answer from the server is "offline" and nothing is '
        'queued or mirrored', () async {
      final fake = FakeSupabase(
        (name, body) async => throw http.ClientException('offline'),
      );
      fake.onTable = (request) async => throw http.ClientException('offline');
      final logs = _RecordingCycleLogs();
      final result = await EpisodeCorrectionRepository(
        client: fake.client,
        cycleLogs: logs,
      ).remove(clientOperationId: 'op-6', episode: _ended());
      expect(result.status, EpisodeEditStatus.offline);
      expect(logs.deleted, isEmpty);
      expect(
        await PendingBleedingOperationStore.loadPending(userId: _user),
        isEmpty,
      );
    });
  });

  group('queued operations she undid (PT-145, PT-156)', () {
    test('a queued end replayed after she undid that end is dropped, not '
        'retried and not flagged for her review (NW410)', () async {
      SecureLocalStore.debugUserIdOverride = _user;
      await PendingBleedingOperationStore.savePending(
        PendingBleedingOperation(
          operationId: 'op-end',
          type: PendingBleedingOperationType.endEpisode,
          params: {
            'episodeId': _episodeId,
            'endDate': DateTime(2026, 10, 15).toIso8601String(),
            'endPrecision': 'date_only',
            'observationPrecision': 'date_only',
            'timezone': 'UTC',
            'utcOffsetMinutes': 0,
          },
          createdAt: DateTime(2026, 10, 15),
        ),
      );
      final fake = FakeSupabase(
        (name, body) async => pgError(
          'NW410',
          'operation op-end was undone and cannot be applied again',
        ),
      );

      await BleedingEpisodeRepositoryImpl(client: fake.client)
          .reconcilePendingOperations();

      expect(fake.rpcCalls, ['end_bleeding_episode']);
      expect(await PendingBleedingOperationStore.loadPending(), isEmpty);
    });
  });

  group('EpisodeEditSheet', () {
    Future<_FakeCorrections> pumpSheet(
      WidgetTester tester, {
      BleedingEpisode? episode,
      bool isLatest = true,
      bool hasOpen = false,
      List<EpisodeEditResult>? results,
      void Function()? onChanged,
    }) async {
      final corrections = _FakeCorrections(results ?? const []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showEpisodeEditSheet(
                  context,
                  episode: episode ?? _ended(),
                  isLatestEpisode: isLatest,
                  hasOpenEpisode: hasOpen,
                  onChanged: onChanged,
                  episodes: _FakeEpisodes(),
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

    testWidgets('PT-027: "I\'m still bleeding" is offered only for her latest '
        'ended period with nothing else open', (tester) async {
      await pumpSheet(tester);
      expect(find.byKey(const Key('episode-edit-reopen')), findsOneWidget);
      expect(
        find.text('Started 10 October 2026 · no bleeding from 15 October 2026'),
        findsOneWidget,
        reason: 'Western digits and her recorded dates',
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await pumpSheet(tester, isLatest: false);
      expect(find.byKey(const Key('episode-edit-reopen')), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await pumpSheet(tester, hasOpen: true);
      expect(find.byKey(const Key('episode-edit-reopen')), findsNothing);
    });

    testWidgets('PT-056/PT-057: removing explains what changes, needs '
        'confirmation, and offers Undo that restores the same period', (
      tester,
    ) async {
      var changes = 0;
      final corrections = await pumpSheet(
        tester,
        results: const [
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'r1'),
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'r2'),
        ],
        onChanged: () => changes++,
      );

      await tester.tap(find.byKey(const Key('episode-edit-remove')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Predictions, reminders and Insights will be worked out again',
        ),
        findsOneWidget,
      );
      expect(corrections.calls, isEmpty, reason: 'nothing before she confirms');

      await tester.tap(find.byKey(const Key('episode-edit-confirm-remove')));
      await tester.pumpAndSettle();
      expect(corrections.calls, ['remove:$_episodeId']);
      expect(
        find.text('Edit this period'),
        findsNothing,
        reason: 'sheet closed',
      );
      expect(find.text('Period removed.'), findsOneWidget);
      expect(changes, 1);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(corrections.calls, ['remove:$_episodeId', 'restore:$_episodeId']);
      expect(find.text('Period restored.'), findsOneWidget);
      expect(changes, 2);
    });

    testWidgets('PT-150/PT-178: offline leaves the sheet open with her chosen '
        'date and says nothing changed', (tester) async {
      final corrections = await pumpSheet(
        tester,
        results: const [EpisodeEditResult(EpisodeEditStatus.offline)],
      );
      await tester.tap(find.byKey(const Key('episode-edit-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('17'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('17 October 2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('episode-edit-save')));
      await tester.pumpAndSettle();
      expect(corrections.calls, ['end:2026-10-17:false']);
      expect(
        find.textContaining("You're offline, so nothing was changed"),
        findsOneWidget,
      );
      expect(
        find.text('17 October 2026'),
        findsOneWidget,
        reason: 'selection kept',
      );
    });

    testWidgets('PT-178: Back with a picked, unsaved date asks before '
        'discarding; nothing is saved either way', (tester) async {
      final corrections = await pumpSheet(tester);
      await tester.tap(find.byKey(const Key('episode-edit-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('17'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // System Back.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard this change?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard-edit-keep')));
      await tester.pumpAndSettle();
      expect(find.text('17 October 2026'), findsOneWidget);

      // The Close button goes through the same question.
      await tester.tap(find.byKey(const Key('episode-edit-close')));
      await tester.pumpAndSettle();
      expect(find.text('Discard this change?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard-edit-discard')));
      await tester.pumpAndSettle();
      expect(find.text('Edit this period'), findsNothing);
      expect(corrections.calls, isEmpty);
    });

    testWidgets('PT-178: Back with nothing picked closes without asking', (
      tester,
    ) async {
      await pumpSheet(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard this change?'), findsNothing);
      expect(find.text('Edit this period'), findsNothing);
    });

    testWidgets(
      'PT-052: an earlier end over recorded bleeding is previewed and '
      'only applied after she agrees',
      (tester) async {
        final corrections = await pumpSheet(
          tester,
          results: const [
            EpisodeEditResult(
              EpisodeEditStatus.needsConfirmation,
              conflictingCount: 2,
            ),
            EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'r1'),
          ],
        );
        await tester.tap(find.byKey(const Key('episode-edit-end')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('12'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('episode-edit-save')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('2 entries with bleeding were recorded'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('episode-edit-confirm-retract')));
        await tester.pumpAndSettle();

        expect(corrections.calls, [
          'end:2026-10-12:false',
          'end:2026-10-12:true',
        ]);
        expect(
          corrections.operationIds.toSet(),
          hasLength(2),
          reason: 'the confirmed change is a different operation',
        );
        expect(find.text('End date updated.'), findsOneWidget);
      },
    );

    testWidgets('PT-051: moving the start to a day with no entry asks for that '
        "day's flow before it can save", (tester) async {
      final corrections = await pumpSheet(
        tester,
        results: const [
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'r1'),
        ],
      );
      await tester.tap(find.byKey(const Key('episode-edit-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final save = find.byKey(const Key('episode-edit-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.byKey(const Key('episode-edit-flow-light')));
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(corrections.calls, ['start:2026-10-08:light:false']);
      expect(find.text('Start date updated.'), findsOneWidget);
    });

    testWidgets('a refusal (overlap) is explained in her words and keeps the '
        'sheet open', (tester) async {
      await pumpSheet(
        tester,
        results: const [
          EpisodeEditResult(
            EpisodeEditStatus.rejected,
            serverMessage: 'end_date (2026-10-24) overlaps the next episode',
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('episode-edit-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('24'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('episode-edit-save')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'These dates overlap another period. Change that period first.',
        ),
        findsOneWidget,
      );
      expect(find.text('Edit this period'), findsOneWidget);
    });

    testWidgets('Arabic: the editor renders RTL with Western digits', (
      tester,
    ) async {
      AppLocaleController.instance.setArabic(true);
      await pumpSheet(tester);
      expect(find.text('تعديل هذا الحيض'), findsOneWidget);
      expect(
        find.text('بدأ 10 أكتوبر 2026 · بلا دم من 15 أكتوبر 2026'),
        findsOneWidget,
      );
      final direction = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.text('تعديل هذا الحيض'),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(direction.textDirection, TextDirection.rtl);
    });

    testWidgets('PT-002: a period whose end is unknown says so and lets her '
        'add the end, never inventing one', (tester) async {
      final unknownEnd = BleedingEpisode(
        id: _episodeId,
        userId: _user,
        lifecycleStatus: LifecycleStatus.ended,
        startDate: DateTime(2026, 10, 10),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userReportedHistorical,
        endSource: ObservationSource.userReportedHistorical,
        endUnknown: true,
        revisionToken: '2026-10-20T10:00:00.123456+00:00',
      );
      final corrections = await pumpSheet(tester, episode: unknownEnd);
      expect(
        find.text('Started 10 October 2026 · end date not recorded'),
        findsOneWidget,
      );
      expect(find.text('Add end date'), findsOneWidget);

      await tester.tap(find.byKey(const Key('episode-edit-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('17'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('episode-edit-save')));
      await tester.pumpAndSettle();
      expect(corrections.calls, ['end:2026-10-17:false']);
    });
  });
}

class _FakeEpisodes extends BleedingEpisodeRepositoryImpl {
  _FakeEpisodes() : super(client: null);

  @override
  Future<LoadResult<List<BleedingObservation>>> getObservationsForEpisode(
    String episodeId,
  ) async => LoadSuccess([
    BleedingObservation.fromJson(_obsJson('o-start', '2026-10-10', 'medium')),
    BleedingObservation.fromJson(_obsJson('o-close', '2026-10-15', 'none')),
  ]);
}

class _FakeCorrections extends EpisodeCorrectionRepository {
  _FakeCorrections(List<EpisodeEditResult> results)
    : _results = [...results],
      super(client: null);

  final List<EpisodeEditResult> _results;
  final calls = <String>[];
  final operationIds = <String>[];

  EpisodeEditResult _next(String call, String operationId) {
    calls.add(call);
    operationIds.add(operationId);
    return _results.isEmpty
        ? const EpisodeEditResult(EpisodeEditStatus.saved)
        : _results.removeAt(0);
  }

  static String _d(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Future<EpisodeEditResult> correctStart({
    required String clientOperationId,
    required BleedingEpisode episode,
    required DateTime newStartDate,
    required ObservationFlow flow,
    required String? timezone,
    required int utcOffsetMinutes,
    bool retractConflicting = false,
  }) async => _next(
    'start:${_d(newStartDate)}:${flow.value}:$retractConflicting',
    clientOperationId,
  );

  @override
  Future<EpisodeEditResult> correctEnd({
    required String clientOperationId,
    required BleedingEpisode episode,
    required DateTime newEndDate,
    required String? timezone,
    required int utcOffsetMinutes,
    bool retractConflicting = false,
  }) async =>
      _next('end:${_d(newEndDate)}:$retractConflicting', clientOperationId);

  @override
  Future<EpisodeEditResult> reopen({
    required String clientOperationId,
    required String episodeId,
    required String? revisionToken,
  }) async => _next('reopen:$episodeId', clientOperationId);

  @override
  Future<EpisodeEditResult> remove({
    required String clientOperationId,
    required BleedingEpisode episode,
  }) async => _next('remove:${episode.id}', clientOperationId);

  @override
  Future<EpisodeEditResult> restore({
    required String clientOperationId,
    required String episodeId,
  }) async => _next('restore:$episodeId', clientOperationId);
}
