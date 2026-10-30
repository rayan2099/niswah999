import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';

import 'logging_sync_hardening/support/fake_supabase.dart';

class _HeldDeletion extends LocalCycleTrackingDataSource {
  final entered = Completer<void>();
  final release = Completer<void>();
  String? startingOwner;

  @override
  Future<void> delete(String id) async {
    startingOwner = SecureLocalStore.currentUserId();
    entered.complete();
    await release.future;
  }
}

void main() {
  setUp(() => SecureLocalStore.debugUserIdOverride = 'owner-a');
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  for (final switchAccount in [false, true]) {
    test(
      'delete pins the initiating account and token (switch: $switchAccount)',
      () async {
        final fake = FakeSupabase((_, __) async => jsonResponse({}));
        await fake.signIn('owner-a');
        final token = fake.client.auth.currentSession!.accessToken;
        final local = _HeldDeletion();
        var deletes = 0;
        fake.onTable = (request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/rest/v1/cycle_entries');
          expect(request.url.queryParameters['id'], 'eq.shared-record');
          expect(request.url.queryParameters['user_id'], 'eq.owner-a');
          expect(request.headers['authorization'], 'Bearer $token');
          deletes++;
          return jsonResponse([]);
        };
        final deleting = CycleTrackingRepositoryImpl(
          client: fake.client,
          localDataSource: local,
        ).deleteCycleLog('shared-record');
        await local.entered.future;
        expect(local.startingOwner, 'owner-a');
        expect(deletes, 0);
        if (switchAccount) {
          SecureLocalStore.debugUserIdOverride = 'owner-b';
          await fake.signIn('owner-b');
        }
        local.release.complete();
        await deleting;
        expect(deletes, 1);
      },
    );
  }

  test('a signed-out local deletion cannot adopt an account that signs in during storage', () async {
    SecureLocalStore.debugUserIdOverride = null;
    final fake = FakeSupabase((_, __) async => jsonResponse({}));
    final local = _HeldDeletion();
    var requests = 0;
    fake.onTable = (_) async {
      requests++;
      return jsonResponse([]);
    };
    final deleting = CycleTrackingRepositoryImpl(
      client: fake.client,
      localDataSource: local,
    ).deleteCycleLog('shared-record');
    await local.entered.future;
    SecureLocalStore.debugUserIdOverride = 'owner-b';
    await fake.signIn('owner-b');
    local.release.complete();
    await deleting;
    expect(requests, 0);
  });
}
