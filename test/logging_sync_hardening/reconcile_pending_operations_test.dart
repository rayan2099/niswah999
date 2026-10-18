import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';

import '../support/secure_storage_test_support.dart';
import 'support/fake_supabase.dart';

/// Logging/sync hardening — the background replay of queued bleeding
/// operations (BleedingEpisodeRepositoryImpl.reconcilePendingOperations),
/// driven through a real Supabase client over a scripted HTTP transport.
PendingBleedingOperation _dailyOp(String id) => PendingBleedingOperation(
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = 'user-A';
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  test(
    'a deterministic RPC rejection (P0001 "episode is not open") of a '
    'queued observation is filed as validation and not auto-retried',
    () async {
      final fake = FakeSupabase(
        (name, body) async => pgError(
          'P0001',
          'cannot add a new observation to episode — it is not open',
        ),
      );
      await PendingBleedingOperationStore.savePending(_dailyOp('op-daily'));
      final repo = BleedingEpisodeRepositoryImpl(client: fake.client);

      await repo.reconcilePendingOperations();
      await repo.reconcilePendingOperations();

      final op = (await PendingBleedingOperationStore.loadPending()).single;
      expect(
        op.lastFailureCategory,
        PendingOperationFailureCategory.validation,
      );
      expect(op.syncState, SyncState.needsAttention);
      expect(fake.rpcCalls, ['record_bleeding_observation']);
    },
  );

  test('an offline replay (transport exception) is filed as network and kept '
      'for the next attempt', () async {
    final fake = FakeSupabase(
      (name, body) async =>
          throw http.ClientException('Failed host lookup', Uri()),
    );
    await PendingBleedingOperationStore.savePending(_dailyOp('op-daily'));

    await BleedingEpisodeRepositoryImpl(client: fake.client)
        .reconcilePendingOperations();

    final op = (await PendingBleedingOperationStore.loadPending()).single;
    expect(op.lastFailureCategory, PendingOperationFailureCategory.network);
    expect(op.eligibleForAutomaticRetry, isTrue);
  });

  test('a queued onboarding submission whose RPC answers '
      'episode_conflict=true stays pending (needs review) instead of being '
      'cleared as if it had saved', () async {
    final fake = FakeSupabase(
      (name, body) async => jsonResponse([
        {
          'episode_id': null,
          'baseline_id': '22222222-2222-2222-2222-222222222222',
          'episode_conflict': true,
          'conflicting_episode_id': '33333333-3333-3333-3333-333333333333',
          'conflicting_start_date': '2026-10-01',
        },
      ]),
    );
    await fake.signIn('user-A');
    await PendingBleedingOperationStore.savePending(
      PendingBleedingOperation(
        operationId: 'op-onboarding',
        type: PendingBleedingOperationType.onboardingHistory,
        params: {
          'utcOffsetMinutes': 180,
          'episode': {
            'lifecycleStatus': 'open',
            'continuationCertainty': 'confirmed',
            'startDate': DateTime(2026, 10, 15).toIso8601String(),
            'startPrecision': 'date_only',
            'startSource': 'user_reported_historical',
          },
        },
        createdAt: DateTime(2026, 10, 15),
      ),
    );

    await BleedingEpisodeRepositoryImpl(client: fake.client)
        .reconcilePendingOperations();

    expect(fake.rpcCalls, ['record_onboarding_menstrual_history']);
    final pending = await PendingBleedingOperationStore.loadPending();
    expect(pending.single.operationId, 'op-onboarding');
    expect(
      pending.single.lastFailureCategory,
      PendingOperationFailureCategory.validation,
    );
  });

  test("an account switch while the sync's RPC is in flight never moves user "
      "A's operation into user B's queue, and the pass stops", () async {
    final fake = FakeSupabase((name, body) async {
      // User A signs out and user B signs in while the request is in
      // flight; the request then fails (5xx from the gateway).
      SecureLocalStore.debugUserIdOverride = 'user-B';
      return http.Response('upstream error', 503);
    });
    await PendingBleedingOperationStore.savePending(
      _dailyOp('op-1-of-A'),
      userId: 'user-A',
    );
    await PendingBleedingOperationStore.savePending(
      _dailyOp('op-2-of-A'),
      userId: 'user-A',
    );

    await BleedingEpisodeRepositoryImpl(client: fake.client)
        .reconcilePendingOperations();

    expect(
      await PendingBleedingOperationStore.loadPending(userId: 'user-B'),
      isEmpty,
    );
    final aBucket = await PendingBleedingOperationStore.loadPending(
      userId: 'user-A',
    );
    expect(aBucket.map((op) => op.operationId), ['op-1-of-A', 'op-2-of-A']);
    expect(aBucket.first.retryCount, 1, reason: 'failure recorded for A');
    expect(
      fake.rpcCalls,
      hasLength(1),
      reason: "A's second operation is never sent under B's session",
    );
  });

  test('a replayed start that hits the one-open-episode constraint (23505) '
      'is filed as validation and not re-sent on every app start', () async {
    final fake = FakeSupabase(
      (name, body) async => pgError(
        '23505',
        'duplicate key value violates unique constraint '
            '"bleeding_episodes_one_open_per_user"',
        409,
      ),
    );
    await PendingBleedingOperationStore.savePending(
      PendingBleedingOperation(
        operationId: 'op-start',
        type: PendingBleedingOperationType.startEpisode,
        params: {
          'startDate': DateTime(2026, 10, 16).toIso8601String(),
          'startPrecision': 'date_only',
          'flow': 'medium',
          'observationPrecision': 'date_only',
          'timezone': 'Asia/Riyadh',
          'utcOffsetMinutes': 180,
        },
        createdAt: DateTime(2026, 10, 16),
      ),
    );

    final repo = BleedingEpisodeRepositoryImpl(client: fake.client);
    for (var i = 0; i < 5; i++) {
      await repo.reconcilePendingOperations();
    }
    final pending = await PendingBleedingOperationStore.loadPending();
    expect(fake.rpcCalls, hasLength(1));
    expect(
      pending.single.lastFailureCategory,
      PendingOperationFailureCategory.validation,
    );
  });
}
