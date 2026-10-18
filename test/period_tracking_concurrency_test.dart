import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/core/storage/local_sensitive_data_cleanup.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

import 'support/secure_storage_test_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = 'owner-a';
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  PendingBleedingOperation operation(String id) => PendingBleedingOperation(
    operationId: id,
    type: PendingBleedingOperationType.startEpisode,
    params: const {'flow': 'light'},
    createdAt: DateTime.utc(2026, 10, 18),
  );
  CycleLog log(String id) => CycleLog(
    id: id,
    userId: 'owner-a',
    date: DateTime(2026, 10, 1),
    flow: FlowLevel.light,
  );

  test(
    'concurrent pending saves preserve every intended retry across callers',
    () async {
      await Future.wait([
        for (var i = 0; i < 20; i++)
          PendingBleedingOperationStore.savePending(operation('operation-$i')),
      ]);
      final stored = await PendingBleedingOperationStore.loadPending();
      expect(stored.map((o) => o.operationId).toSet(), {
        for (var i = 0; i < 20; i++) 'operation-$i',
      });
    },
  );

  test(
    'clearing an acknowledged operation cannot be undone by another save',
    () async {
      await PendingBleedingOperationStore.savePending(
        operation('acknowledged'),
      );
      await PendingBleedingOperationStore.savePending(operation('keep'));
      await Future.wait([
        PendingBleedingOperationStore.clearPending('acknowledged'),
        PendingBleedingOperationStore.savePending(operation('new')),
      ]);
      expect(
        (await PendingBleedingOperationStore.loadPending())
            .map((o) => o.operationId)
            .toSet(),
        {'keep', 'new'},
      );
    },
  );

  test(
    'pending writes keep their starting owner across an awaited account change',
    () async {
      final writing = PendingBleedingOperationStore.savePending(
        operation('owned-by-a'),
      );
      SecureLocalStore.debugUserIdOverride = 'owner-b';
      await writing;
      expect(
        await PendingBleedingOperationStore.loadPending(userId: 'owner-b'),
        isEmpty,
      );
      expect(
        (await PendingBleedingOperationStore.loadPending(userId: 'owner-a'))
            .single
            .operationId,
        'owned-by-a',
      );
    },
  );

  test(
    'concurrent local log saves across instances do not lose observations',
    () async {
      await Future.wait([
        for (var i = 0; i < 20; i++)
          LocalCycleTrackingDataSource().upsert(log('log-$i')),
      ]);
      expect(
        (await LocalCycleTrackingDataSource().loadLogs())
            .map((l) => l.id)
            .toSet(),
        {for (var i = 0; i < 20; i++) 'log-$i'},
      );
    },
  );

  test(
    'a local deletion cannot be resurrected by a concurrent insert',
    () async {
      final source = LocalCycleTrackingDataSource();
      await source.upsert(log('remove'));
      await source.upsert(log('keep'));
      await Future.wait([
        source.delete('remove'),
        LocalCycleTrackingDataSource().upsert(log('new')),
      ]);
      expect((await source.loadLogs()).map((l) => l.id).toSet(), {
        'keep',
        'new',
      });
    },
  );

  test(
    'a local save cannot move to an account selected while storage is awaited',
    () async {
      final source = LocalCycleTrackingDataSource();
      final writing = source.upsert(log('owned-by-a'));
      SecureLocalStore.debugUserIdOverride = 'owner-b';
      await writing;
      expect(await source.loadLogs(), isEmpty);
      SecureLocalStore.debugUserIdOverride = 'owner-a';
      expect((await source.loadLogs()).single.id, 'owned-by-a');
    },
  );

  test(
    'account deletion removes queued operation payloads as well as logs',
    () async {
      await PendingBleedingOperationStore.savePending(
        operation('delete-with-account'),
      );
      await cleanUpLocalSensitiveDataForDeletedAccount('owner-a');
      expect(
        await PendingBleedingOperationStore.loadPending(userId: 'owner-a'),
        isEmpty,
      );
    },
  );
}
