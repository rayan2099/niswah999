import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

import '../support/secure_storage_test_support.dart';
import 'support/fake_supabase.dart';

/// Logging/sync hardening — getCycleLogs merges local and remote rows by
/// id. A remote row replaces its local copy only when that copy is already
/// synced; a local edit still `pending`/`failed` keeps precedence.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = 'user-A';
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  test('an unsynced local edit is hidden by the stale server row', () async {
    final fake = FakeSupabase((name, body) async => jsonResponse([]));
    await fake.signIn('user-A');
    fake.onTable = (request) async => jsonResponse([
      {
        'id': 'log-1',
        'user_id': 'user-A',
        'date': '2026-10-17',
        'flow': 'light',
        'flow_intensity': 'light',
        'cycle_day': 1,
        'data_provenance': 'user_observed',
        'sync_status': 'synced',
      },
    ]);

    final local = LocalCycleTrackingDataSource();
    // She edited the day offline: heavy, not yet synced.
    await local.upsert(
      CycleLog(
        id: 'log-1',
        userId: 'user-A',
        date: DateTime(2026, 10, 17),
        flow: FlowLevel.heavy,
        cycleDay: 1,
        syncStatus: SyncStatus.pending,
      ),
    );

    final logs = await CycleTrackingRepositoryImpl(
      client: fake.client,
      localDataSource: local,
    ).getCycleLogs();

    expect(
      logs.single.flow,
      FlowLevel.heavy,
      reason: 'the pending local edit is the newest fact she entered',
    );
  });

  test('a synced local copy is still refreshed from the server', () async {
    final fake = FakeSupabase((name, body) async => jsonResponse([]));
    await fake.signIn('user-A');
    fake.onTable = (request) async => jsonResponse([
      {
        'id': 'log-1',
        'user_id': 'user-A',
        'date': '2026-10-17',
        'flow': 'light',
        'flow_intensity': 'light',
        'cycle_day': 1,
        'data_provenance': 'user_observed',
        'sync_status': 'synced',
      },
    ]);
    final local = LocalCycleTrackingDataSource();
    await local.upsert(
      CycleLog(
        id: 'log-1',
        userId: 'user-A',
        date: DateTime(2026, 10, 17),
        flow: FlowLevel.heavy,
        cycleDay: 1,
        syncStatus: SyncStatus.synced,
      ),
    );

    final logs = await CycleTrackingRepositoryImpl(
      client: fake.client,
      localDataSource: local,
    ).getCycleLogs();

    expect(logs.single.flow, FlowLevel.light);
  });
}
