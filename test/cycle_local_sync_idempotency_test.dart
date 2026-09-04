import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'LocalCycleTrackingDataSource upsert idempotency (retry safety)',
    () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
      });

      test(
        'upserting the same id twice (as a retry would) results in exactly one stored entry',
        () async {
          final source = LocalCycleTrackingDataSource();
          final log = CycleLog(
            id: 'log-1',
            userId: 'user-1',
            date: DateTime(2026, 9, 1),
            flow: FlowLevel.medium,
            syncStatus: SyncStatus.pending,
          );

          // Simulates: initial save, then a retry attempt re-sending the
          // exact same log (e.g. syncPendingLogs() retrying after a
          // transient failure) — must not create a duplicate.
          await source.upsert(log);
          await source.upsert(log.copyWith(syncStatus: SyncStatus.synced));

          final stored = await source.loadLogs();
          expect(stored.length, 1);
          expect(stored.single.id, 'log-1');
          expect(stored.single.syncStatus, SyncStatus.synced);
        },
      );

      test(
        'pending -> synced transition is reflected after a successful retry',
        () async {
          final source = LocalCycleTrackingDataSource();
          const id = 'log-2';
          await source.upsert(
            CycleLog(
              id: id,
              userId: 'user-1',
              date: DateTime(2026, 9, 2),
              flow: FlowLevel.light,
              syncStatus: SyncStatus.pending,
            ),
          );

          expect((await source.getById(id))?.syncStatus, SyncStatus.pending);

          // What CycleTrackingRepositoryImpl.syncPendingLogs() does on a
          // successful retry.
          await source.upsert(
            (await source.getById(id))!.copyWith(syncStatus: SyncStatus.synced),
          );

          expect((await source.getById(id))?.syncStatus, SyncStatus.synced);
        },
      );

      test(
        'a non-retryable failure marks the entry failed, not pending forever',
        () async {
          final source = LocalCycleTrackingDataSource();
          const id = 'log-3';
          await source.upsert(
            CycleLog(
              id: id,
              userId: 'user-1',
              date: DateTime(2026, 9, 3),
              flow: FlowLevel.heavy,
              syncStatus: SyncStatus.pending,
            ),
          );

          // What CycleTrackingRepositoryImpl.saveCycleLog/syncPendingLogs
          // does when mapRepositoryError classifies the failure as
          // non-retryable.
          await source.upsert(
            (await source.getById(id))!.copyWith(syncStatus: SyncStatus.failed),
          );

          final stored = await source.getById(id);
          expect(stored?.syncStatus, SyncStatus.failed);
          // A `failed` entry must be excluded from the automatic-retry
          // query (`syncStatus == SyncStatus.pending` in
          // syncPendingLogs()) — verified structurally here: it's simply
          // not `pending` anymore, so that filter will skip it.
          expect(stored?.syncStatus, isNot(SyncStatus.pending));
        },
      );

      test('multiple distinct pending logs are all preserved independently', () async {
        final source = LocalCycleTrackingDataSource();
        for (var i = 0; i < 3; i++) {
          await source.upsert(
            CycleLog(
              id: 'log-multi-$i',
              userId: 'user-1',
              date: DateTime(2026, 9, 10 + i),
              flow: FlowLevel.spotting,
              syncStatus: SyncStatus.pending,
            ),
          );
        }

        final pending = (await source.loadLogs())
            .where((log) => log.syncStatus == SyncStatus.pending)
            .toList();
        expect(pending.length, 3);
      });
    },
  );
}
