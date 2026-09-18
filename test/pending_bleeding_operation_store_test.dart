import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';

import 'support/secure_storage_test_support.dart';

/// Menstrual Data Integrity charter, PR #4 completion wave — Fix D. The
/// real failure mode this store exists for (the app process is killed
/// after the server has already committed a start/end request but before
/// the response reaches the sheet) cannot be reproduced in a plain unit
/// test — that would need a real device/process-kill (E4). What a unit
/// test *can* prove: the store itself round-trips correctly, and
/// `reconcilePendingOperations` genuinely attempts to replay whatever is
/// still pending rather than silently ignoring it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
  });

  group('PendingBleedingOperationStore', () {
    test('a saved pending operation round-trips exactly', () async {
      final operation = PendingBleedingOperation(
        operationId: 'op-1',
        type: PendingBleedingOperationType.startEpisode,
        params: {'startDate': '2026-09-17T00:00:00.000', 'flow': 'medium'},
        createdAt: DateTime(2026, 9, 17, 8, 0),
      );

      await PendingBleedingOperationStore.savePending(operation);
      final loaded = await PendingBleedingOperationStore.loadPending();

      expect(loaded, hasLength(1));
      expect(loaded.single.operationId, 'op-1');
      expect(loaded.single.type, PendingBleedingOperationType.startEpisode);
      expect(loaded.single.params['flow'], 'medium');
    });

    test('clearPending removes only the matching operation', () async {
      await PendingBleedingOperationStore.savePending(
        PendingBleedingOperation(
          operationId: 'op-1',
          type: PendingBleedingOperationType.startEpisode,
          params: const {},
          createdAt: DateTime(2026, 9, 17),
        ),
      );
      await PendingBleedingOperationStore.savePending(
        PendingBleedingOperation(
          operationId: 'op-2',
          type: PendingBleedingOperationType.endEpisode,
          params: const {},
          createdAt: DateTime(2026, 9, 18),
        ),
      );

      await PendingBleedingOperationStore.clearPending('op-1');
      final loaded = await PendingBleedingOperationStore.loadPending();

      expect(loaded, hasLength(1));
      expect(loaded.single.operationId, 'op-2');
    });

    test(
      'saving the same operationId twice replaces rather than duplicates',
      () async {
        await PendingBleedingOperationStore.savePending(
          PendingBleedingOperation(
            operationId: 'op-1',
            type: PendingBleedingOperationType.startEpisode,
            params: const {'flow': 'medium'},
            createdAt: DateTime(2026, 9, 17),
          ),
        );
        await PendingBleedingOperationStore.savePending(
          PendingBleedingOperation(
            operationId: 'op-1',
            type: PendingBleedingOperationType.startEpisode,
            params: const {'flow': 'heavy'},
            createdAt: DateTime(2026, 9, 17),
          ),
        );

        final loaded = await PendingBleedingOperationStore.loadPending();
        expect(loaded, hasLength(1));
        expect(loaded.single.params['flow'], 'heavy');
      },
    );

    test(
      'a malformed persisted record is quarantined, not crashed on',
      () async {
        // Directly exercises tryFromJson's honest-failure path rather than
        // the store's own read plumbing.
        final parsed = PendingBleedingOperation.tryFromJson({
          'operation_id': 'op-1',
          'type': 'not_a_real_type',
          'params': <String, dynamic>{},
          'created_at': DateTime(2026, 9, 17).toIso8601String(),
        });
        expect(parsed, isNull);
      },
    );

    test('loadPending on an empty store returns an empty list', () async {
      final loaded = await PendingBleedingOperationStore.loadPending();
      expect(loaded, isEmpty);
    });
  });

  group('BleedingEpisodeRepositoryImpl.reconcilePendingOperations', () {
    test('attempts to replay a pending operation rather than silently '
        'ignoring it — leaves it pending when the replay itself cannot '
        'succeed (no Supabase session, matching a real cold app start '
        'before sign-in)', () async {
      await PendingBleedingOperationStore.savePending(
        PendingBleedingOperation(
          operationId: 'op-1',
          type: PendingBleedingOperationType.startEpisode,
          params: {
            'startDate': DateTime(2026, 9, 17).toIso8601String(),
            'startPrecision': 'date_only',
            'flow': 'medium',
            'observationPrecision': 'date_only',
            'timezone': 'UTC',
            'utcOffsetMinutes': 0,
          },
          createdAt: DateTime(2026, 9, 17),
        ),
      );

      await BleedingEpisodeRepositoryImpl(client: null)
          .reconcilePendingOperations();

      final stillPending = await PendingBleedingOperationStore.loadPending();
      expect(
        stillPending,
        hasLength(1),
        reason:
            'a replay that cannot succeed must leave the operation '
            'pending for the next reconciliation attempt, never '
            'silently drop it',
      );
    });

    test('with nothing pending, reconciliation is a safe no-op', () async {
      await BleedingEpisodeRepositoryImpl(client: null)
          .reconcilePendingOperations();
      final stillPending = await PendingBleedingOperationStore.loadPending();
      expect(stillPending, isEmpty);
    });
  });
}
