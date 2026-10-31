import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/core/errors/failures.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

import 'support/secure_storage_test_support.dart';
import 'logging_sync_hardening/support/fake_supabase.dart';

class _DelayedRepository extends CycleTrackingRepositoryImpl {
  _DelayedRepository(this.release, {this.fail = false, super.client});
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
  Future<List<CycleLog>> readFor(String owner) async {
    final previous = SecureLocalStore.debugUserIdOverride;
    SecureLocalStore.debugUserIdOverride = owner;
    try {
      return await LocalCycleTrackingDataSource().loadLogs();
    } finally {
      SecureLocalStore.debugUserIdOverride = previous;
    }
  }

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
    expect(await readFor('owner-b'), isEmpty);
    expect((await readFor('owner-a')).single.syncStatus, SyncStatus.synced);
  });

  test('an observation owned by another signed-in account cannot enter the current cache', () async {
    SecureLocalStore.debugUserIdOverride = 'owner-b';
    await expectLater(
      CycleTrackingRepositoryImpl().saveCycleLog(log(FlowLevel.light)),
      throwsA(isA<NetworkFailure>()),
    );
    expect(await readFor('owner-b'), isEmpty);
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

  test(
    'a delayed permanent failure updates A without changing B cache',
    () async {
      final release = Completer<void>();
      final repository = _DelayedRepository(release, fail: true);
      final saving = repository.saveCycleLog(log(FlowLevel.light));
      await repository.entered.future;
      SecureLocalStore.debugUserIdOverride = 'owner-b';
      await LocalCycleTrackingDataSource().upsert(
        log(FlowLevel.heavy).copyWith(userId: 'owner-b'),
      );
      release.complete();
      expect(await saving, SyncStatus.failed);
      expect((await readFor('owner-a')).single.syncStatus, SyncStatus.failed);
      final other = (await readFor('owner-b')).single;
      expect(other.flow, FlowLevel.heavy);
      expect(other.syncStatus, SyncStatus.pending);
    },
  );

  for (final fail in [false, true]) {
    test(
      'background ${fail ? 'failure' : 'success'} acknowledges the original bucket',
      () async {
        final fake = FakeSupabase((_, __) async => jsonResponse({}));
        await fake.signIn('owner-a');
        await LocalCycleTrackingDataSource().upsert(log(FlowLevel.light));
        final release = Completer<void>();
        final repository = _DelayedRepository(
          release,
          fail: fail,
          client: fake.client,
        );
        final syncing = repository.syncPendingLogs();
        await repository.entered.future;
        SecureLocalStore.debugUserIdOverride = 'owner-b';
        await fake.signIn('owner-b');
        await LocalCycleTrackingDataSource().upsert(
          log(FlowLevel.heavy).copyWith(userId: 'owner-b'),
        );
        release.complete();
        await syncing;
        expect(
          (await readFor('owner-a')).single.syncStatus,
          fail ? SyncStatus.failed : SyncStatus.synced,
        );
        final other = (await readFor('owner-b')).single;
        expect(other.flow, FlowLevel.heavy);
        expect(other.syncStatus, SyncStatus.pending);
      },
    );
  }
}
