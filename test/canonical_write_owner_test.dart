import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';

import 'support/secure_storage_test_support.dart';

class _DelayedReplay extends BleedingEpisodeRepositoryImpl {
  final entered = Completer<void>();
  final release = Completer<void>();
  String? expectedOwner;

  @override
  Future<({BleedingEpisode episode, BleedingObservation observation})>
  startEpisode({
    required String clientOperationId,
    String? expectedUserId,
    required DateTime startDate,
    required ObservationPrecision startPrecision,
    DateTime? startTime,
    required ObservationFlow flow,
    DateTime? observedTime,
    required ObservationPrecision observationPrecision,
    String? timezone,
    required int utcOffsetMinutes,
    List<String>? symptoms,
    String? notes,
  }) async {
    expectedOwner = expectedUserId;
    entered.complete();
    await release.future;
    return (
      episode: BleedingEpisode(
        userId: 'owner-a',
        lifecycleStatus: LifecycleStatus.open,
        continuationCertainty: ContinuationCertainty.confirmed,
        startDate: startDate,
        startPrecision: startPrecision,
        startSource: ObservationSource.userObserved,
      ),
      observation: BleedingObservation(
        id: 'observation',
        userId: 'owner-a',
        episodeId: 'episode',
        observedDate: startDate,
        precision: observationPrecision,
        flow: flow,
        source: ObservationSource.userObserved,
        utcOffsetMinutes: utcOffsetMinutes,
      ),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = 'owner-a';
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  test(
    'a replay response clears only its original owner after an account change',
    () async {
      final operation = PendingBleedingOperation(
        operationId: 'same-id',
        type: PendingBleedingOperationType.startEpisode,
        createdAt: DateTime.utc(2026, 10, 18),
        params: {
          'startDate': '2026-10-18',
          'startPrecision': 'date_only',
          'flow': 'light',
          'observationPrecision': 'date_only',
          'utcOffsetMinutes': 0,
        },
      );
      await PendingBleedingOperationStore.savePending(
        operation,
        userId: 'owner-a',
      );
      await PendingBleedingOperationStore.savePending(
        operation,
        userId: 'owner-b',
      );
      final repository = _DelayedReplay();
      final replaying = repository.reconcilePendingOperations();
      await repository.entered.future;
      SecureLocalStore.debugUserIdOverride = 'owner-b';
      repository.release.complete();
      await replaying;
      expect(repository.expectedOwner, 'owner-a');
      expect(
        await PendingBleedingOperationStore.loadPending(userId: 'owner-a'),
        isEmpty,
      );
      expect(
        (await PendingBleedingOperationStore.loadPending(userId: 'owner-b'))
            .single
            .operationId,
        'same-id',
      );
    },
  );

  test('canonical writes validate account ownership and retain it across a response', () async {
    var rpcCalls = 0;
    late final SupabaseClient client;
    client = SupabaseClient(
      'https://example.test',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.contains('/token')) {
          final other =
              (jsonDecode(request.body) as Map)['email'] ==
              'other@example.test';
          return http.Response(
            jsonEncode({
              'access_token': other ? 'other-token' : 'synthetic-token',
              'refresh_token': 'synthetic-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': other ? 'owner-a' : 'owner-b',
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'synthetic@example.test',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-10-18T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        rpcCalls++;
        expect(request.headers['authorization'], 'Bearer synthetic-token');
        // The original account's request completes after another account signs in.
        await client.auth.signInWithPassword(
          email: 'other@example.test',
          password: 'synthetic-password',
        );
        return http.Response(
          '[{"episode_id":"episode","observation_id":"observation"}]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'synthetic@example.test',
      password: 'synthetic-password',
    );
    final repository = BleedingEpisodeRepositoryImpl(client: client);
    await expectLater(
      repository.startEpisode(
        clientOperationId: 'operation',
        expectedUserId: 'owner-a',
        startDate: DateTime(2026, 10, 18),
        startPrecision: ObservationPrecision.dateOnly,
        flow: ObservationFlow.light,
        observationPrecision: ObservationPrecision.dateOnly,
        utcOffsetMinutes: 0,
      ),
      throwsStateError,
    );
    expect(rpcCalls, 0);
    final saved = await repository.startEpisode(
      clientOperationId: 'operation',
      expectedUserId: 'owner-b',
      startDate: DateTime(2026, 10, 18),
      startPrecision: ObservationPrecision.dateOnly,
      flow: ObservationFlow.light,
      observationPrecision: ObservationPrecision.dateOnly,
      utcOffsetMinutes: 0,
    );
    expect(rpcCalls, 1);
    expect(client.auth.currentUser!.id, 'owner-a');
    expect(saved.episode.userId, 'owner-b');
    expect(saved.observation.userId, 'owner-b');
  });
}
