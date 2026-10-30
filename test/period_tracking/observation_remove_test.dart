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
import 'package:niswah/features/cycle_tracking/presentation/widgets/observation_detail_sheet.dart';

import '../logging_sync_hardening/support/fake_supabase.dart';
import '../support/device_timezone_test_support.dart';
import '../support/secure_storage_test_support.dart';

/// PT-055: deleting one day's entry, with Undo. The app side of
/// supabase/migrations/20261029120000_bleeding_observation_removal.sql; the
/// server rules (archive, protected entries, restore, isolation) are proven
/// in test/security/bleeding_observation_removal.sql.

const _user = 'a0000000-0000-4000-8000-00000000000a';
const _episodeId = 'e0000000-0000-4000-8000-00000000000e';
const _token = '2026-10-20T10:00:00.123456+00:00';

BleedingEpisode _episode({bool ended = true}) => BleedingEpisode(
  id: _episodeId,
  userId: _user,
  lifecycleStatus: ended ? LifecycleStatus.ended : LifecycleStatus.open,
  continuationCertainty: ended ? null : ContinuationCertainty.confirmed,
  startDate: DateTime(2026, 10, 10),
  startPrecision: ObservationPrecision.dateOnly,
  startSource: ObservationSource.userReportedHistorical,
  endDate: ended ? DateTime(2026, 10, 15) : null,
  endPrecision: ended ? ObservationPrecision.dateOnly : null,
  endSource: ended ? ObservationSource.userReportedHistorical : null,
  revisionToken: _token,
);

Map<String, dynamic> _obsJson(String id, String date, String flow) => {
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
  'supersedes_id': null,
  'client_operation_id': null,
};

BleedingObservation _obs(String id, String date, String flow) =>
    BleedingObservation.fromJson(_obsJson(id, date, flow));

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

class _FakeCorrections extends EpisodeCorrectionRepository {
  _FakeCorrections(List<EpisodeEditResult> results)
    : _results = [...results],
      super(client: null);

  final List<EpisodeEditResult> _results;
  final calls = <String>[];

  EpisodeEditResult _next(String call) {
    calls.add(call);
    return _results.isEmpty
        ? const EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'rev')
        : _results.removeAt(0);
  }

  @override
  Future<EpisodeEditResult> removeObservation({
    required String clientOperationId,
    required String episodeId,
    required String observationId,
    required String? revisionToken,
  }) async => _next('remove:$observationId:$revisionToken');

  @override
  Future<EpisodeEditResult> restoreObservation({
    required String clientOperationId,
    required String episodeId,
    required String removalRevisionId,
  }) async => _next('restore:$removalRevisionId');
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

  group('EpisodeCorrectionRepository.removeObservation', () {
    test('sends the entry and her revision token, and takes only that entry '
        'off this device', () async {
      Map<String, dynamic>? sent;
      var reads = 0;
      final fake = FakeSupabase((name, body) async {
        sent = body;
        return jsonResponse([
          {'episode_id': _episodeId, 'revision_id': 'rev-rm'},
        ]);
      });
      fake.onTable = (request) async {
        reads++;
        return jsonResponse([
          _obsJson('o-start', '2026-10-10', 'medium'),
          if (reads == 1) _obsJson('o-mid', '2026-10-12', 'light'),
          _obsJson('o-close', '2026-10-15', 'none'),
        ]);
      };
      final logs = _RecordingCycleLogs();

      final result =
          await EpisodeCorrectionRepository(
            client: fake.client,
            cycleLogs: logs,
          ).removeObservation(
            clientOperationId: 'op-rm',
            episodeId: _episodeId,
            observationId: 'o-mid',
            revisionToken: _token,
          );

      expect(result.saved, isTrue);
      expect(result.revisionId, 'rev-rm');
      expect(fake.rpcCalls, ['remove_observation']);
      expect(sent, {
        'p_client_operation_id': 'op-rm',
        'p_observation_id': 'o-mid',
        'p_expected_updated_at': _token,
      });
      expect(logs.deleted, ['o-mid']);
      expect(logs.saved, isEmpty);
    });

    test('Undo puts the same entry back on this device', () async {
      Map<String, dynamic>? sent;
      var reads = 0;
      final fake = FakeSupabase((name, body) async {
        sent = body;
        return jsonResponse([
          {'episode_id': _episodeId, 'revision_id': 'rev-undo'},
        ]);
      });
      fake.onTable = (request) async {
        reads++;
        return jsonResponse([
          _obsJson('o-start', '2026-10-10', 'medium'),
          if (reads > 1) _obsJson('o-mid', '2026-10-12', 'light'),
          _obsJson('o-close', '2026-10-15', 'none'),
        ]);
      };
      final logs = _RecordingCycleLogs();

      final result =
          await EpisodeCorrectionRepository(
            client: fake.client,
            cycleLogs: logs,
          ).restoreObservation(
            clientOperationId: 'op-undo',
            episodeId: _episodeId,
            removalRevisionId: 'rev-rm',
          );

      expect(result.saved, isTrue);
      expect(fake.rpcCalls, ['restore_observation']);
      expect(sent, {
        'p_client_operation_id': 'op-undo',
        'p_removal_revision_id': 'rev-rm',
      });
      expect(logs.saved, ['o-mid']);
      expect(logs.deleted, isEmpty);
    });

    test('a protected entry (NW423) is a rejection and changes nothing on '
        'this device', () async {
      final fake = FakeSupabase(
        (name, body) async => pgError(
          'NW423',
          "this is the period's start entry; edit the period's start instead",
        ),
      );
      fake.onTable = (request) async =>
          jsonResponse([_obsJson('o-start', '2026-10-10', 'medium')]);
      final logs = _RecordingCycleLogs();
      final result =
          await EpisodeCorrectionRepository(
            client: fake.client,
            cycleLogs: logs,
          ).removeObservation(
            clientOperationId: 'op-p',
            episodeId: _episodeId,
            observationId: 'o-start',
            revisionToken: _token,
          );
      expect(result.status, EpisodeEditStatus.rejected);
      expect(logs.deleted, isEmpty);
    });

    test('PT-164: reminders are re-planned once after a saved change, '
        'never after a refused one', () async {
      final refreshed = <String>[];
      Future<void> refresh(String userId) async => refreshed.add(userId);

      final ok = FakeSupabase(
        (name, body) async => jsonResponse([
          {'episode_id': _episodeId, 'revision_id': 'rev-r'},
        ]),
      );
      ok.onTable = (request) async =>
          jsonResponse([_obsJson('o-start', '2026-10-10', 'medium')]);
      final saved =
          await EpisodeCorrectionRepository(
            client: ok.client,
            cycleLogs: _RecordingCycleLogs(),
            refreshReminders: refresh,
            currentUserId: () => 'user-1',
          ).removeObservation(
            clientOperationId: 'op-r',
            episodeId: _episodeId,
            observationId: 'o-mid',
            revisionToken: _token,
          );
      await Future<void>.delayed(Duration.zero);
      expect(saved.saved, isTrue);
      expect(refreshed, ['user-1']);

      final refused = FakeSupabase(
        (name, body) async => pgError('NW409', 'episode changed'),
      );
      refused.onTable = ok.onTable;
      await EpisodeCorrectionRepository(
        client: refused.client,
        cycleLogs: _RecordingCycleLogs(),
        refreshReminders: refresh,
        currentUserId: () => 'user-1',
      ).removeObservation(
        clientOperationId: 'op-r2',
        episodeId: _episodeId,
        observationId: 'o-mid',
        revisionToken: _token,
      );
      await Future<void>.delayed(Duration.zero);
      expect(refreshed, [
        'user-1',
      ], reason: 'nothing changed, nothing re-planned');
    });

    test('a stale token (NW409) is "changed elsewhere"; no answer is '
        '"offline"', () async {
      final stale =
          await EpisodeCorrectionRepository(
            client: FakeSupabase(
              (name, body) async => pgError('NW409', 'episode changed'),
            ).client,
            cycleLogs: _RecordingCycleLogs(),
          ).removeObservation(
            clientOperationId: 'op-s',
            episodeId: _episodeId,
            observationId: 'o-mid',
            revisionToken: _token,
          );
      expect(stale.status, EpisodeEditStatus.changedElsewhere);

      final offlineFake = FakeSupabase(
        (name, body) async => throw http.ClientException('offline'),
      );
      offlineFake.onTable = (request) async =>
          throw http.ClientException('offline');
      final logs = _RecordingCycleLogs();
      final offline =
          await EpisodeCorrectionRepository(
            client: offlineFake.client,
            cycleLogs: logs,
          ).removeObservation(
            clientOperationId: 'op-o',
            episodeId: _episodeId,
            observationId: 'o-mid',
            revisionToken: _token,
          );
      expect(offline.status, EpisodeEditStatus.offline);
      expect(logs.deleted, isEmpty);
    });
  });

  group('day sheet: "Delete this entry"', () {
    Future<_FakeCorrections> open(
      WidgetTester tester, {
      required DateTime day,
      required List<BleedingObservation> observations,
      BleedingEpisode? episode,
      List<EpisodeEditResult> results = const [],
      VoidCallback? onEpisodeChanged,
    }) async {
      final corrections = _FakeCorrections(results);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showObservationDetailSheet(
                  context,
                  day: day,
                  episodeForDay: episode ?? _episode(),
                  observationsForDay: observations,
                  repository: BleedingEpisodeRepositoryImpl(client: null),
                  onEpisodeChanged: onEpisodeChanged,
                  correctionsOverride: corrections,
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

    final removeButton = find.byKey(
      const Key('observation-detail-remove-entry'),
    );
    final protectedHint = find.byKey(
      const Key('observation-detail-protected-hint'),
    );

    testWidgets('a middle day: confirm, delete, then Undo restores it', (
      tester,
    ) async {
      var changed = 0;
      final corrections = await open(
        tester,
        day: DateTime(2026, 10, 12),
        observations: [_obs('o-mid', '2026-10-12', 'light')],
        results: const [
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'rev-rm'),
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'rev-undo'),
        ],
        onEpisodeChanged: () => changed++,
      );

      expect(protectedHint, findsNothing);
      await tester.ensureVisible(removeButton);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);
      expect(corrections.calls, isEmpty, reason: 'nothing before confirming');

      await tester.tap(
        find.byKey(const Key('observation-detail-confirm-remove')),
      );
      await tester.pumpAndSettle();

      expect(corrections.calls, ['remove:o-mid:$_token']);
      expect(changed, 1);
      expect(
        find.text('Delete this entry'),
        findsNothing,
        reason: 'sheet closed',
      );
      expect(
        find.byKey(const Key('observation-detail-removed-snackbar')),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(corrections.calls.last, 'restore:rev-rm');
      expect(changed, 2);
      expect(find.text('Entry restored.'), findsOneWidget);
    });

    testWidgets('Cancel in the confirmation deletes nothing', (tester) async {
      final corrections = await open(
        tester,
        day: DateTime(2026, 10, 12),
        observations: [_obs('o-mid', '2026-10-12', 'light')],
      );
      await tester.ensureVisible(removeButton);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(corrections.calls, isEmpty);
      expect(removeButton, findsOneWidget, reason: 'sheet still open');
    });

    testWidgets('the start day and the end of an ended period are protected', (
      tester,
    ) async {
      await open(
        tester,
        day: DateTime(2026, 10, 10),
        observations: [_obs('o-start', '2026-10-10', 'medium')],
      );
      expect(removeButton, findsNothing);
      expect(find.textContaining("period's first day"), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await open(
        tester,
        day: DateTime(2026, 10, 15),
        observations: [_obs('o-close', '2026-10-15', 'none')],
      );
      expect(removeButton, findsNothing);
      expect(find.textContaining("period's end"), findsOneWidget);
    });

    testWidgets('a "no bleeding" entry in an open period can be deleted', (
      tester,
    ) async {
      await open(
        tester,
        day: DateTime(2026, 10, 13),
        episode: _episode(ended: false),
        observations: [_obs('o-none', '2026-10-13', 'none')],
      );
      expect(protectedHint, findsNothing);
      expect(removeButton, findsOneWidget);
    });

    testWidgets('an unrecorded day offers no delete', (tester) async {
      await open(tester, day: DateTime(2026, 10, 12), observations: const []);
      expect(removeButton, findsNothing);
      expect(protectedHint, findsNothing);
    });

    testWidgets('offline: she is told nothing changed, and the sheet stays', (
      tester,
    ) async {
      var changed = 0;
      final corrections = await open(
        tester,
        day: DateTime(2026, 10, 12),
        observations: [_obs('o-mid', '2026-10-12', 'light')],
        results: const [EpisodeEditResult(EpisodeEditStatus.offline)],
        onEpisodeChanged: () => changed++,
      );
      await tester.ensureVisible(removeButton);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('observation-detail-confirm-remove')),
      );
      await tester.pumpAndSettle();

      expect(corrections.calls, hasLength(1));
      expect(changed, 0);
      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(removeButton, findsOneWidget);
    });

    testWidgets('Undo refused over a newer entry says so', (tester) async {
      await open(
        tester,
        day: DateTime(2026, 10, 12),
        observations: [_obs('o-mid', '2026-10-12', 'light')],
        results: const [
          EpisodeEditResult(EpisodeEditStatus.saved, revisionId: 'rev-rm'),
          EpisodeEditResult(
            EpisodeEditStatus.rejected,
            serverMessage: 'a newer entry exists on 2026-10-12',
          ),
        ],
      );
      await tester.ensureVisible(removeButton);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('observation-detail-confirm-remove')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A newer entry was added'), findsOneWidget);
    });

    testWidgets('Arabic labels', (tester) async {
      AppLocaleController.instance.setArabic(true);
      await open(
        tester,
        day: DateTime(2026, 10, 12),
        observations: [_obs('o-mid', '2026-10-12', 'light')],
      );
      expect(find.text('حذف هذا الإدخال'), findsOneWidget);
    });
  });
}
