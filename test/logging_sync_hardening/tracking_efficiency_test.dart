import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

import '../support/secure_storage_test_support.dart';
import 'support/fake_supabase.dart';

/// Tracking-efficiency audit (2026-10-21): the local queue/cache writes,
/// the two background sync passes and the replay's projection read.
PendingBleedingOperation _op(String id) => PendingBleedingOperation(
  operationId: id,
  type: PendingBleedingOperationType.dailyOrBackfillObservation,
  params: {
    'episodeId': '11111111-1111-1111-1111-111111111111',
    'observedDate': DateTime(2026, 10, 17).toIso8601String(),
    'precision': 'date_only',
    'flow': 'medium',
    'utcOffsetMinutes': 180,
    'timezone': 'Asia/Riyadh',
  },
  createdAt: DateTime(2026, 10, 17),
);

CycleLog _log(String id, {FlowLevel flow = FlowLevel.light, String? notes}) =>
    CycleLog(
      id: id,
      userId: 'user-A',
      date: DateTime(2026, 10, 17),
      flow: flow,
      notes: notes,
      syncStatus: SyncStatus.pending,
    );

Map<String, dynamic> _observationRow(String id) => {
  'id': id,
  'user_id': 'user-A',
  'episode_id': '11111111-1111-1111-1111-111111111111',
  'observed_date': '2026-10-17',
  'precision': 'date_only',
  'flow': 'medium',
  'source': 'user_observed',
  'utc_offset_minutes': 180,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = 'user-A';
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  group('local read-modify-write is serialized', () {
    test('two overlapping queue writes both survive', () async {
      await Future.wait([
        PendingBleedingOperationStore.savePending(_op('op-1')),
        PendingBleedingOperationStore.savePending(_op('op-2')),
      ]);
      final ids = (await PendingBleedingOperationStore.loadPending())
          .map((op) => op.operationId)
          .toSet();
      expect(ids, {'op-1', 'op-2'});
    });

    test(
      'a clear overlapping a new queued write keeps the new write',
      () async {
        await PendingBleedingOperationStore.savePending(_op('op-1'));
        await Future.wait([
          PendingBleedingOperationStore.clearPending('op-1'),
          PendingBleedingOperationStore.savePending(_op('op-2')),
        ]);
        final ids = (await PendingBleedingOperationStore.loadPending())
            .map((op) => op.operationId)
            .toList();
        expect(ids, ['op-2']);
      },
    );

    test('two overlapping cycle log saves both survive', () async {
      final local = LocalCycleTrackingDataSource();
      await Future.wait([local.upsert(_log('a')), local.upsert(_log('b'))]);
      expect((await local.loadLogs()).map((l) => l.id).toSet(), {'a', 'b'});
    });
  });

  group('syncPendingLogs', () {
    test('an edit saved while its older version uploads stays pending '
        'with the new content', () async {
      final local = LocalCycleTrackingDataSource();
      await local.upsert(_log('log-1'));
      final fake = FakeSupabase((name, body) async => jsonResponse([]));
      await fake.signIn('user-A');
      fake.onTable = (request) async {
        if (request.method == 'POST') {
          // She edits the same day while the old version is in flight.
          await local.upsert(
            _log('log-1', flow: FlowLevel.heavy, notes: 'cramps'),
          );
        }
        return jsonResponse([]);
      };

      await CycleTrackingRepositoryImpl(
        client: fake.client,
        localDataSource: local,
      ).syncPendingLogs();

      final stored = (await local.loadLogs()).single;
      expect(stored.flow, FlowLevel.heavy);
      expect(stored.notes, 'cramps');
      expect(
        stored.syncStatus,
        SyncStatus.pending,
        reason: 'the server still holds the older version',
      );
    });

    test('an unchanged row is marked synced', () async {
      final local = LocalCycleTrackingDataSource();
      await local.upsert(_log('log-1'));
      final fake = FakeSupabase((name, body) async => jsonResponse([]));
      await fake.signIn('user-A');

      final result = await CycleTrackingRepositoryImpl(
        client: fake.client,
        localDataSource: local,
      ).syncPendingLogs();

      expect(result.synced, 1);
      expect((await local.loadLogs()).single.syncStatus, SyncStatus.synced);
    });

    test('a row deleted while it uploads is not brought back', () async {
      final local = LocalCycleTrackingDataSource();
      await local.upsert(_log('log-1'));
      final fake = FakeSupabase((name, body) async => jsonResponse([]));
      await fake.signIn('user-A');
      fake.onTable = (request) async {
        if (request.method == 'POST') await local.delete('log-1');
        return jsonResponse([]);
      };

      await CycleTrackingRepositoryImpl(
        client: fake.client,
        localDataSource: local,
      ).syncPendingLogs();

      expect(await local.loadLogs(), isEmpty);
    });

    test(
      'overlapping triggers (app start + resume) upload each row once',
      () async {
        final local = LocalCycleTrackingDataSource();
        await local.upsert(_log('log-1'));
        await local.upsert(_log('log-2'));
        final fake = FakeSupabase((name, body) async => jsonResponse([]));
        await fake.signIn('user-A');
        var uploads = 0;
        fake.onTable = (request) async {
          if (request.method == 'POST') uploads++;
          return jsonResponse([]);
        };
        final repository = CycleTrackingRepositoryImpl(
          client: fake.client,
          localDataSource: local,
        );

        final results = await Future.wait([
          repository.syncPendingLogs(),
          repository.syncPendingLogs(),
        ]);

        expect(uploads, 2);
        expect(results.first.synced, 2);
        expect(results.last.synced, 2);
      },
    );
  });

  group('reconcilePendingOperations', () {
    test('overlapping passes replay each queued operation once', () async {
      final fake = FakeSupabase(
        (name, body) async => jsonResponse([
          {'observation_id': 'obs-1'},
        ]),
      );
      await fake.signIn('user-A');
      await PendingBleedingOperationStore.savePending(_op('op-1'));

      await Future.wait([
        BleedingEpisodeRepositoryImpl(client: fake.client)
            .reconcilePendingOperations(),
        BleedingEpisodeRepositoryImpl(client: fake.client)
            .reconcilePendingOperations(),
      ]);

      expect(fake.rpcCalls, ['record_bleeding_observation']);
      expect(await PendingBleedingOperationStore.loadPending(), isEmpty);
    });

    test(
      'a forced retry during an automatic pass still runs its own pass',
      () async {
        final fake = FakeSupabase(
          (name, body) async => pgError('P0001', 'episode is not open'),
        );
        await fake.signIn('user-A');
        await PendingBleedingOperationStore.savePending(_op('op-1'));

        await Future.wait([
          BleedingEpisodeRepositoryImpl(client: fake.client)
              .reconcilePendingOperations(),
          BleedingEpisodeRepositoryImpl(client: fake.client)
              .reconcilePendingOperations(forceAll: true),
        ]);

        // The automatic pass files it as validation; the forced one (which
        // ignores that) still retries it.
        expect(fake.rpcCalls, [
          'record_bleeding_observation',
          'record_bleeding_observation',
        ]);
      },
    );

    test(
      'the replayed observation is read by id, not the whole history',
      () async {
        final fake = FakeSupabase(
          (name, body) async => jsonResponse([
            {'observation_id': 'obs-1'},
          ]),
        );
        await fake.signIn('user-A');
        final reads = <Uri>[];
        fake.onTable = (request) async {
          reads.add(request.url);
          final row = _observationRow('obs-1');
          final wantsObject =
              request.headers['Accept']?.contains('object') ?? false;
          return jsonResponse(wantsObject ? row : [row]);
        };
        await PendingBleedingOperationStore.savePending(_op('op-1'));

        await BleedingEpisodeRepositoryImpl(client: fake.client)
            .reconcilePendingOperations();

        final observationReads = reads
            .where((u) => u.path.endsWith('/bleeding_observations'))
            .toList();
        expect(observationReads, hasLength(1));
        expect(observationReads.single.queryParameters['id'], 'eq.obs-1');
        expect(
          observationReads.single.queryParameters.containsKey('user_id'),
          isFalse,
        );
      },
    );

    test(
      'a failed replay does not put back an operation cleared meanwhile',
      () async {
        final fake = FakeSupabase((name, body) async {
          // The sheet's own retry of the same operation completes and clears
          // it while this replay is still waiting for the network.
          await PendingBleedingOperationStore.clearPending('op-1');
          throw http.ClientException('Connection reset', Uri());
        });
        await fake.signIn('user-A');
        await PendingBleedingOperationStore.savePending(_op('op-1'));

        await BleedingEpisodeRepositoryImpl(client: fake.client)
            .reconcilePendingOperations();

        expect(await PendingBleedingOperationStore.loadPending(), isEmpty);
      },
    );
  });
}
