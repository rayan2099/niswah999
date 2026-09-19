import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/storage/secure_local_store.dart';
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

  tearDown(() {
    SecureLocalStore.debugUserIdOverride = null;
  });

  group(
    'Commit H — account switch with pending operations (per-user isolation)',
    () {
      test("User B signing in on the same device never sees User A's "
          'still-pending operation — SecureLocalStore is scoped per user, '
          'so an account switch structurally cannot leak it, not merely by '
          'convention', () async {
        SecureLocalStore.debugUserIdOverride = 'user-A';
        await PendingBleedingOperationStore.savePending(
          PendingBleedingOperation(
            operationId: 'user-a-op-1',
            type: PendingBleedingOperationType.startEpisode,
            params: const {'flow': 'medium'},
            createdAt: DateTime(2026, 9, 18),
          ),
        );
        expect(await PendingBleedingOperationStore.loadPending(), hasLength(1));

        // Account switch.
        SecureLocalStore.debugUserIdOverride = 'user-B';
        expect(
          await PendingBleedingOperationStore.loadPending(),
          isEmpty,
          reason:
              "User B's own store is a genuinely different key — User "
              "A's pending operation is invisible, not merely filtered",
        );

        // Switching back to User A: their own pending operation is
        // still there, untouched by User B ever having been active.
        SecureLocalStore.debugUserIdOverride = 'user-A';
        final userAAgain = await PendingBleedingOperationStore.loadPending();
        expect(userAAgain, hasLength(1));
        expect(userAAgain.single.operationId, 'user-a-op-1');
      });

      test('User B can save their own pending operation independently while '
          "User A's remains untouched", () async {
        SecureLocalStore.debugUserIdOverride = 'user-A';
        await PendingBleedingOperationStore.savePending(
          PendingBleedingOperation(
            operationId: 'user-a-op-1',
            type: PendingBleedingOperationType.startEpisode,
            params: const {},
            createdAt: DateTime(2026, 9, 18),
          ),
        );

        SecureLocalStore.debugUserIdOverride = 'user-B';
        await PendingBleedingOperationStore.savePending(
          PendingBleedingOperation(
            operationId: 'user-b-op-1',
            type: PendingBleedingOperationType.endEpisode,
            params: const {},
            createdAt: DateTime(2026, 9, 18),
          ),
        );
        final userB = await PendingBleedingOperationStore.loadPending();
        expect(userB, hasLength(1));
        expect(userB.single.operationId, 'user-b-op-1');

        SecureLocalStore.debugUserIdOverride = 'user-A';
        final userA = await PendingBleedingOperationStore.loadPending();
        expect(userA, hasLength(1));
        expect(userA.single.operationId, 'user-a-op-1');
      });
    },
  );

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

    group('Closure Blocker 11 — corrupt persisted data must not crash '
        'health tracking or block every other pending operation', () {
      // Mirrors the store's own private `_category` key — there is no
      // public constant to import, and duplicating this one literal
      // string is simpler than widening the class's own encapsulation
      // just for these tests.
      const category = 'cycle_tracking_pending_bleeding_operations';

      test('invalid JSON syntax is quarantined, not thrown', () async {
        await SecureLocalStore.write(category, '{not valid json at all');

        final loaded = await PendingBleedingOperationStore.loadPending();

        expect(loaded, isEmpty);
      });

      test('a wrong top-level shape (a JSON object instead of a list) is '
          'quarantined, not thrown', () async {
        await SecureLocalStore.write(category, '{"oops": "not a list"}');

        final loaded = await PendingBleedingOperationStore.loadPending();

        expect(loaded, isEmpty);
      });

      test('one invalid item among otherwise-valid items is quarantined '
          'alone — every valid operation around it still loads', () async {
        final valid1 = PendingBleedingOperation(
          operationId: 'op-1',
          type: PendingBleedingOperationType.startEpisode,
          params: const {'flow': 'medium'},
          createdAt: DateTime(2026, 9, 17),
        ).toJson();
        final valid2 = PendingBleedingOperation(
          operationId: 'op-2',
          type: PendingBleedingOperationType.endEpisode,
          params: const {},
          createdAt: DateTime(2026, 9, 18),
        ).toJson();

        // A bare string in the list where an object is expected — the
        // old `item as Map<String, dynamic>` cast would have thrown
        // here, losing op-1 and op-2 both.
        await SecureLocalStore.write(
          category,
          '[${jsonEncode(valid1)}, "not an object", ${jsonEncode(valid2)}]',
        );

        final loaded = await PendingBleedingOperationStore.loadPending();

        expect(loaded, hasLength(2));
        expect(loaded.map((o) => o.operationId), ['op-1', 'op-2']);
      });

      test('an unknown operation type is quarantined alone', () async {
        final valid = PendingBleedingOperation(
          operationId: 'op-1',
          type: PendingBleedingOperationType.startEpisode,
          params: const {},
          createdAt: DateTime(2026, 9, 17),
        ).toJson();
        final unknownType = {
          'operation_id': 'op-2',
          'type': 'some_future_type_this_build_does_not_know',
          'params': <String, dynamic>{},
          'created_at': DateTime(2026, 9, 18).toIso8601String(),
        };

        await SecureLocalStore.write(
          category,
          jsonEncode([valid, unknownType]),
        );

        final loaded = await PendingBleedingOperationStore.loadPending();

        expect(loaded, hasLength(1));
        expect(loaded.single.operationId, 'op-1');
      });

      test('an invalid timestamp is quarantined alone', () async {
        final valid = PendingBleedingOperation(
          operationId: 'op-1',
          type: PendingBleedingOperationType.startEpisode,
          params: const {},
          createdAt: DateTime(2026, 9, 17),
        ).toJson();
        final invalidTimestamp = {
          'operation_id': 'op-2',
          'type': PendingBleedingOperationType.endEpisode.name,
          'params': <String, dynamic>{},
          'created_at': 'not-a-real-timestamp',
        };

        await SecureLocalStore.write(
          category,
          jsonEncode([valid, invalidTimestamp]),
        );

        final loaded = await PendingBleedingOperationStore.loadPending();

        expect(loaded, hasLength(1));
        expect(loaded.single.operationId, 'op-1');
      });
    });

    group('getPendingByType (Hardening 1)', () {
      test('returns the pending operation of the requested type', () async {
        await PendingBleedingOperationStore.savePending(
          PendingBleedingOperation(
            operationId: 'onboarding-op-1',
            type: PendingBleedingOperationType.onboardingHistory,
            params: const {'utcOffsetMinutes': 180},
            createdAt: DateTime(2026, 9, 18),
          ),
        );
        await PendingBleedingOperationStore.savePending(
          PendingBleedingOperation(
            operationId: 'start-op-1',
            type: PendingBleedingOperationType.startEpisode,
            params: const {},
            createdAt: DateTime(2026, 9, 18),
          ),
        );

        final found = await PendingBleedingOperationStore.getPendingByType(
          PendingBleedingOperationType.onboardingHistory,
        );
        expect(found?.operationId, 'onboarding-op-1');
      });

      test('returns null when no operation of that type is pending', () async {
        final found = await PendingBleedingOperationStore.getPendingByType(
          PendingBleedingOperationType.onboardingHistory,
        );
        expect(found, isNull);
      });
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

    test(
      'Hardening 1: attempts to replay a pending onboardingHistory '
      'operation and leaves it pending when there is no session to '
      'replay it against (a real device/process-kill round trip is E4 — '
      'the server-side idempotent replay of record_onboarding_menstrual_'
      'history was verified directly against local Postgres; see the '
      'commit message and docs/menstrual-data-integrity-contract.md)',
      () async {
        await PendingBleedingOperationStore.savePending(
          PendingBleedingOperation(
            operationId: 'onboarding-op-1',
            type: PendingBleedingOperationType.onboardingHistory,
            params: {
              'utcOffsetMinutes': 180,
              'episode': {
                'lifecycleStatus': 'open',
                'continuationCertainty': 'confirmed',
                'startDate': DateTime(2026, 9, 15).toIso8601String(),
                'startPrecision': 'date_only',
                'startSource': 'user_reported_historical',
              },
              'baseline': {
                'usualBleedingDurationDays': 6,
                'usualCycleLengthDays': 28,
              },
            },
            createdAt: DateTime(2026, 9, 18),
          ),
        );

        await BleedingEpisodeRepositoryImpl(client: null)
            .reconcilePendingOperations();

        final stillPending = await PendingBleedingOperationStore.loadPending();
        expect(
          stillPending,
          hasLength(1),
          reason:
              'no session means the replay itself cannot succeed — it '
              'must stay pending for the next reconciliation attempt, '
              'never be silently dropped nor treated as if it had '
              'succeeded',
        );
        expect(stillPending.single.operationId, 'onboarding-op-1');
      },
    );

    test('Commit D9: attempts to replay a pending dailyOrBackfillObservation '
        'operation and leaves it pending when there is no session', () async {
      await PendingBleedingOperationStore.savePending(
        PendingBleedingOperation(
          operationId: 'daily-op-1',
          type: PendingBleedingOperationType.dailyOrBackfillObservation,
          params: {
            'episodeId': 'episode-1',
            'observedDate': DateTime(2026, 9, 17).toIso8601String(),
            'precision': 'date_only',
            'flow': 'medium',
            'source': 'user_observed',
            'utcOffsetMinutes': 180,
          },
          createdAt: DateTime(2026, 9, 17),
        ),
      );

      await BleedingEpisodeRepositoryImpl(client: null)
          .reconcilePendingOperations();

      final stillPending = await PendingBleedingOperationStore.loadPending();
      expect(stillPending, hasLength(1));
      expect(stillPending.single.operationId, 'daily-op-1');
    });

    test('Commit D9: attempts to replay a pending correction operation and '
        'leaves it pending when there is no session — the exact behavior '
        'that also protects a genuine D7 conflict from being silently '
        'dropped (see correction_sheet.dart\'s own conflict handling, '
        'verified live against local Postgres for the RPC side)', () async {
      await PendingBleedingOperationStore.savePending(
        PendingBleedingOperation(
          operationId: 'correction-op-1',
          type: PendingBleedingOperationType.correction,
          params: {
            'supersedesId': 'observation-1',
            'observedDate': DateTime(2026, 9, 17).toIso8601String(),
            'precision': 'date_only',
            'flow': 'spotting',
            'source': 'user_observed',
            'utcOffsetMinutes': 180,
          },
          createdAt: DateTime(2026, 9, 17),
        ),
      );

      await BleedingEpisodeRepositoryImpl(client: null)
          .reconcilePendingOperations();

      final stillPending = await PendingBleedingOperationStore.loadPending();
      expect(stillPending, hasLength(1));
      expect(stillPending.single.operationId, 'correction-op-1');
    });

    test('Commit D9: attempts to replay a pending baselineEstimate operation '
        'and leaves it pending when there is no session', () async {
      await PendingBleedingOperationStore.savePending(
        PendingBleedingOperation(
          operationId: 'baseline-op-2',
          type: PendingBleedingOperationType.baselineEstimate,
          params: {'usualBleedingDurationDays': 6, 'usualCycleLengthDays': 28},
          createdAt: DateTime(2026, 9, 17),
        ),
      );

      await BleedingEpisodeRepositoryImpl(client: null)
          .reconcilePendingOperations();

      final stillPending = await PendingBleedingOperationStore.loadPending();
      expect(stillPending, hasLength(1));
      expect(stillPending.single.operationId, 'baseline-op-2');
    });
  });

  group('New critical finding — three honest sync states', () {
    test('a fresh pending operation (never yet attempted) is savedSyncing', () {
      final operation = PendingBleedingOperation(
        operationId: 'op-1',
        type: PendingBleedingOperationType.startEpisode,
        params: const {},
        createdAt: DateTime(2026, 9, 17),
      );
      expect(operation.syncState, SyncState.savedSyncing);
      expect(operation.eligibleForAutomaticRetry, isTrue);
    });

    test('network/auth/unknown failures stay savedSyncing until the retry '
        'threshold, then become needsAttention — never dead-lettered, '
        'still eligible for automatic retry the whole time', () {
      var operation = PendingBleedingOperation(
        operationId: 'op-1',
        type: PendingBleedingOperationType.startEpisode,
        params: const {},
        createdAt: DateTime(2026, 9, 17),
      );

      for (var i = 0; i < 2; i++) {
        operation = operation.withFailure(
          PendingOperationFailureCategory.network,
          attemptedAt: DateTime(2026, 9, 17),
        );
        expect(
          operation.syncState,
          SyncState.savedSyncing,
          reason: 'attempt ${i + 1} — still under the threshold',
        );
        expect(operation.eligibleForAutomaticRetry, isTrue);
      }

      operation = operation.withFailure(
        PendingOperationFailureCategory.network,
        attemptedAt: DateTime(2026, 9, 17),
      );
      expect(operation.syncState, SyncState.needsAttention);
      expect(
        operation.eligibleForAutomaticRetry,
        isTrue,
        reason:
            'needsAttention is about visibility, not giving up — '
            'automatic reconciliation keeps trying',
      );
    });

    test('a validation failure is needsAttention immediately, on the very '
        'first failure, and is never automatically retried again', () {
      final operation =
          PendingBleedingOperation(
            operationId: 'op-1',
            type: PendingBleedingOperationType.startEpisode,
            params: const {},
            createdAt: DateTime(2026, 9, 17),
          ).withFailure(
            PendingOperationFailureCategory.validation,
            attemptedAt: DateTime(2026, 9, 17),
          );

      expect(operation.syncState, SyncState.needsAttention);
      expect(operation.eligibleForAutomaticRetry, isFalse);
    });

    test('a correction conflict is needsAttention immediately and is never '
        'automatically retried (blind retry would just conflict again)', () {
      final operation =
          PendingBleedingOperation(
            operationId: 'op-1',
            type: PendingBleedingOperationType.correction,
            params: const {},
            createdAt: DateTime(2026, 9, 17),
          ).withFailure(
            PendingOperationFailureCategory.correctionConflict,
            attemptedAt: DateTime(2026, 9, 17),
          );

      expect(operation.syncState, SyncState.needsAttention);
      expect(operation.eligibleForAutomaticRetry, isFalse);
    });

    test('withFailure increments retryCount and stamps lastAttemptAt/'
        'lastFailureCategory, all of which round-trip through JSON', () {
      final operation =
          PendingBleedingOperation(
            operationId: 'op-1',
            type: PendingBleedingOperationType.startEpisode,
            params: const {},
            createdAt: DateTime(2026, 9, 17),
          ).withFailure(
            PendingOperationFailureCategory.network,
            attemptedAt: DateTime(2026, 9, 18, 10),
          );

      expect(operation.retryCount, 1);
      expect(
        operation.lastFailureCategory,
        PendingOperationFailureCategory.network,
      );
      expect(operation.lastAttemptAt, DateTime(2026, 9, 18, 10));

      final restored = PendingBleedingOperation.tryFromJson(
        operation.toJson(),
      )!;
      expect(restored.retryCount, 1);
      expect(
        restored.lastFailureCategory,
        PendingOperationFailureCategory.network,
      );
      expect(restored.lastAttemptAt, DateTime(2026, 9, 18, 10));
    });

    test('a record persisted before retry-tracking existed (no retry_count/'
        'category/timestamp fields at all) restores honestly as '
        'never-failed, not quarantined over an optional field', () {
      final restored = PendingBleedingOperation.tryFromJson({
        'operation_id': 'op-1',
        'type': 'startEpisode',
        'params': <String, dynamic>{},
        'created_at': DateTime(2026, 9, 17).toIso8601String(),
      });
      expect(restored, isNotNull);
      expect(restored!.retryCount, 0);
      expect(restored.lastFailureCategory, isNull);
      expect(restored.syncState, SyncState.savedSyncing);
    });
  });

  group('New critical finding — reconcilePendingOperations retry tracking '
      '(auth/differentiated failure categories)', () {
    test('a real reconciliation failure (no session — an auth condition) '
        'persists retryCount/category back to the store, visible on the '
        'next load', () async {
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
      expect(stillPending, hasLength(1));
      expect(stillPending.single.retryCount, 1);
      expect(
        stillPending.single.lastFailureCategory,
        PendingOperationFailureCategory.auth,
        reason:
            'startEpisode throws a StateError mentioning "session" '
            'when there is no Supabase client at all',
      );
    });

    test(
      'a validation-categorized pending operation is skipped by '
      'automatic reconciliation (forceAll: false, the default) but '
      'still attempted when forceAll: true (a deliberate manual retry)',
      () async {
        final validationFailed =
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
            ).withFailure(
              PendingOperationFailureCategory.validation,
              attemptedAt: DateTime(2026, 9, 17),
            );
        await PendingBleedingOperationStore.savePending(validationFailed);

        await BleedingEpisodeRepositoryImpl(client: null)
            .reconcilePendingOperations();
        var stillPending = await PendingBleedingOperationStore.loadPending();
        expect(
          stillPending.single.retryCount,
          1,
          reason:
              'automatic reconciliation must not have touched it — '
              'retryCount stays exactly where withFailure left it',
        );

        await BleedingEpisodeRepositoryImpl(client: null)
            .reconcilePendingOperations(forceAll: true);
        stillPending = await PendingBleedingOperationStore.loadPending();
        expect(
          stillPending.single.retryCount,
          2,
          reason: 'forceAll: true genuinely attempted it again',
        );
      },
    );
  });
}
