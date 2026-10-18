import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/core/errors/failures.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

import 'support/secure_storage_test_support.dart';

class _DelayedRepository extends CycleTrackingRepositoryImpl {
  _DelayedRepository(this.release, {this.fail = false});
  final Completer<void> release;
  final bool fail;
  final entered = Completer<void>();

  @override
  Future<void> upsertCycleLog(CycleLog log) async {
    entered.complete();
    await release.future;
    if (fail) throw const NetworkFailure('Rejected.', retryable: false);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = 'owner-a';
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);
  CycleLog log(FlowLevel flow) => CycleLog(
    id: 'same-record',
    userId: 'owner-a',
    date: DateTime(2026, 10, 1),
    flow: flow,
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: DateTime.utc(2026, 10, 18),
  );

  for (final fail in [false, true]) {
    test(
      'an older ${fail ? "failure" : "success"} cannot overwrite a newer edit',
      () async {
        final release = Completer<void>();
        final repository = _DelayedRepository(release, fail: fail);
        final saving = repository.saveCycleLog(log(FlowLevel.light));
        await repository.entered.future;
        final source = LocalCycleTrackingDataSource();
        await source.upsert(log(FlowLevel.heavy));
        release.complete();
        await saving;
        final stored = (await source.loadLogs()).single;
        expect(stored.flow, FlowLevel.heavy);
        expect(stored.syncStatus, SyncStatus.pending);
      },
    );
  }

  test(
    'an old acknowledgement cannot resurrect a deleted local record',
    () async {
      final release = Completer<void>();
      final repository = _DelayedRepository(release);
      final saving = repository.saveCycleLog(log(FlowLevel.light));
      await repository.entered.future;
      final source = LocalCycleTrackingDataSource();
      await source.delete('same-record');
      release.complete();
      await saving;
      expect(await source.loadLogs(), isEmpty);
    },
  );

  test('an acknowledgement remains in its starting account bucket', () async {
    final release = Completer<void>();
    final repository = _DelayedRepository(release);
    final saving = repository.saveCycleLog(log(FlowLevel.light));
    await repository.entered.future;
    SecureLocalStore.debugUserIdOverride = 'owner-b';
    release.complete();
    await saving;
    final source = LocalCycleTrackingDataSource();
    expect(await source.loadLogs(userId: 'owner-b'), isEmpty);
    expect(
      (await source.loadLogs(userId: 'owner-a')).single.syncStatus,
      SyncStatus.synced,
    );
  });

  test('an observation owned by another signed-in account cannot enter the current cache', () async {
    SecureLocalStore.debugUserIdOverride = 'owner-b';
    await expectLater(
      CycleTrackingRepositoryImpl().saveCycleLog(log(FlowLevel.light)),
      throwsA(isA<NetworkFailure>()),
    );
    expect(
      await LocalCycleTrackingDataSource().loadLogs(userId: 'owner-b'),
      isEmpty,
    );
  });

  test(
    'no configured server cannot be reported as a successful sync',
    () async {
      final repository = CycleTrackingRepositoryImpl();
      expect(
        await repository.saveCycleLog(log(FlowLevel.light)),
        SyncStatus.pending,
      );
      expect(
        (await LocalCycleTrackingDataSource().loadLogs()).single.syncStatus,
        SyncStatus.pending,
      );
    },
  );
}
