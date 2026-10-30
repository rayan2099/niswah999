import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

import 'logging_sync_hardening/support/fake_supabase.dart';

class PausedLocalSource extends LocalCycleTrackingDataSource {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> upsert(CycleLog log) async {
    entered.complete();
    await release.future;
  }

  @override
  Future<bool> setSyncStatusIfUnchanged(
    CycleLog log,
    SyncStatus status,
  ) async => true;
}

class PausedReadSource extends LocalCycleTrackingDataSource {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<CycleLog>> loadLogs({String? userId}) async {
    entered.complete();
    await release.future;
    return [
      CycleLog(
        id: 'private-entry-a',
        userId: 'owner-a',
        date: DateTime(2026, 10, 1),
        flow: FlowLevel.light,
      ),
    ];
  }
}

class PausedEntryReadSource extends LocalCycleTrackingDataSource {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<CycleLog?> getById(String id) async {
    entered.complete();
    await release.future;
    return CycleLog(
      id: id,
      userId: 'owner-a',
      date: DateTime(2026, 10, 1),
      flow: FlowLevel.light,
    );
  }
}

void main() {
  test('switching accounts during local save never uploads the old record as the new account', () async {
    final fake = FakeSupabase((_, __) async => jsonResponse({}));
    final uploads = <Map<String, dynamic>>[];
    fake.onTable = (request) async {
      if (request.method == 'POST') {
        uploads.add(jsonDecode(request.body) as Map<String, dynamic>);
      }
      return jsonResponse([]);
    };
    await fake.signIn('owner-a');
    final local = PausedLocalSource();
    final repository = CycleTrackingRepositoryImpl(
      client: fake.client,
      localDataSource: local,
    );
    final save = repository.saveCycleLog(
      CycleLog(
        id: 'entry-a',
        userId: 'owner-a',
        date: DateTime(2026, 10, 1),
        flow: FlowLevel.light,
      ),
    );
    await local.entered.future;
    await fake.signIn('owner-b');
    local.release.complete();
    try {
      await save;
    } catch (_) {
      // Failing closed is acceptable; redirecting the write is not.
    }
    expect(uploads.where((row) => row['user_id'] == 'owner-b'), isEmpty);
  });
  test(
    'signed-out save remains pending rather than claiming a server sync',
    () async {
      final fake = FakeSupabase((_, __) async => jsonResponse({}));
      var requests = 0;
      fake.onTable = (request) async {
        requests++;
        return jsonResponse([]);
      };
      final local = PausedLocalSource();
      local.release.complete();
      final repository = CycleTrackingRepositoryImpl(
        client: fake.client,
        localDataSource: local,
      );
      final status = await repository.saveCycleLog(
        CycleLog(
          id: 'offline-entry',
          userId: 'owner-a',
          date: DateTime(2026, 10, 1),
          flow: FlowLevel.light,
        ),
      );
      expect(status, SyncStatus.pending);
      expect(requests, 0);
    },
  );

  test(
    'account switch during local read never returns the previous account data',
    () async {
      final fake = FakeSupabase((_, __) async => jsonResponse({}));
      await fake.signIn('owner-a');
      final local = PausedReadSource();
      final repository = CycleTrackingRepositoryImpl(
        client: fake.client,
        localDataSource: local,
      );
      final read = repository.getCycleLogs();
      await local.entered.future;
      await fake.signIn('owner-b');
      local.release.complete();
      try {
        final result = await read;
        expect(result.where((entry) => entry.userId == 'owner-a'), isEmpty);
      } on StateError {
        // A rejected stale read is an acceptable fail-closed result.
      }
    },
  );

  test(
    'single-entry remote read rejects a response after account switch',
    () async {
      final fake = FakeSupabase((_, __) async => jsonResponse({}));
      await fake.signIn('owner-a');
      final entered = Completer<void>();
      final release = Completer<void>();
      final originalToken = fake.client.auth.currentSession!.accessToken;
      fake.onTable = (request) async {
        expect(request.headers['authorization'], 'Bearer $originalToken');
        expect(request.url.queryParameters['user_id'], 'eq.owner-a');
        entered.complete();
        await release.future;
        return jsonResponse(
          CycleLog(
            id: 'entry-a',
            userId: 'owner-a',
            date: DateTime(2026, 10, 1),
            flow: FlowLevel.light,
          ).toJson(),
        );
      };
      final repository = CycleTrackingRepositoryImpl(client: fake.client);
      final read = repository.getCycleLogById('entry-a');
      final rejected = expectLater(read, throwsStateError);
      await entered.future;
      await fake.signIn('owner-b');
      release.complete();
      await rejected;
    },
  );

  for (final signedIn in [true, false]) {
    test(
      'single-entry local fallback rejects account change (signed in: $signedIn)',
      () async {
        final fake = FakeSupabase((_, __) async => jsonResponse({}));
        if (signedIn) await fake.signIn('owner-a');
        fake.onTable = (_) async => jsonResponse(null);
        final local = PausedEntryReadSource();
        final repository = CycleTrackingRepositoryImpl(
          client: fake.client,
          localDataSource: local,
        );
        final read = repository.getCycleLogById('entry-a');
        final rejected = expectLater(read, throwsStateError);
        await local.entered.future;
        await fake.signIn('owner-b');
        local.release.complete();
        await rejected;
      },
    );
  }
}
