import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/core/errors/failures.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

import 'logging_sync_hardening/support/fake_supabase.dart';
import 'support/secure_storage_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = 'owner-b';
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  CycleLog entry(String owner) => CycleLog(
    id: 'synthetic-entry',
    userId: owner,
    date: DateTime(2026, 10, 1),
    flow: FlowLevel.light,
    notes: 'private synthetic notes',
  );

  test(
    'foreign record is rejected before entering the active local cache',
    () async {
      final source = LocalCycleTrackingDataSource();
      final repository = CycleTrackingRepositoryImpl(localDataSource: source);
      await expectLater(
        repository.saveCycleLog(entry('owner-a')),
        throwsA(isA<NetworkFailure>()),
      );
      expect(await source.loadLogs(), isEmpty);
      SecureLocalStore.debugUserIdOverride = 'owner-a';
      expect(await source.loadLogs(), isEmpty);
    },
  );

  test('injected authenticated session rejects foreign record before any upload', () async {
    final fake = FakeSupabase((_, __) async => jsonResponse({}));
    await fake.signIn('owner-b');
    var requests = 0;
    fake.onTable = (_) async {
      requests++;
      return jsonResponse([]);
    };
    // An injected client's identity is still checked when the global local
    // store has no signed-in session (the production providers normally agree).
    SecureLocalStore.debugUserIdOverride = null;
    final source = LocalCycleTrackingDataSource();
    await expectLater(
      CycleTrackingRepositoryImpl(
        client: fake.client,
        localDataSource: source,
      ).saveCycleLog(entry('owner-a')),
      throwsA(isA<NetworkFailure>()),
    );
    expect(requests, 0);
    expect(await source.loadLogs(), isEmpty);
  });

  test('same-owner offline save remains durable and pending', () async {
    final source = LocalCycleTrackingDataSource();
    final status = await CycleTrackingRepositoryImpl(localDataSource: source)
        .saveCycleLog(entry('owner-b'));
    expect(status, SyncStatus.pending);
    expect((await source.loadLogs()).single.userId, 'owner-b');
    expect((await source.loadLogs()).single.notes, 'private synthetic notes');
    SecureLocalStore.debugUserIdOverride = 'owner-a';
    expect(await source.loadLogs(), isEmpty);
  });
}
