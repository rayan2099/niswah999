import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/auth/domain/account_deletion_orchestrator.dart';

/// Exercises `performAccountDeletion`'s sequencing/failure-isolation
/// contract directly with injected fakes — the exact orchestration
/// `AuthRepositoryImpl.deleteAccount` delegates to — proving the account
/// deletion resilience claims the prior wave made by code review only
/// (Reliability Evidence Closure wave, 2026-09-06).
void main() {
  group('performAccountDeletion', () {
    test(
      '1. RPC failure before remote deletion: local cleanup and signOut '
      'are never attempted, and the error propagates so the caller can '
      'never claim the account was deleted',
      () async {
        var cleanupCalled = false;
        var signOutCalled = false;

        Future<void> failingDelete() async {
          throw Exception('RPC rejected — network unreachable');
        }

        expect(
          () => performAccountDeletion(
            deleteRemote: failingDelete,
            cleanupLocal: () async {
              cleanupCalled = true;
            },
            signOutLocal: () async {
              signOutCalled = true;
            },
            onCleanupFailure: (_, _) {},
          ),
          throwsA(isA<Exception>()),
        );
        // Let the rejected future settle before asserting.
        await Future<void>.delayed(Duration.zero);

        expect(
          cleanupCalled,
          isFalse,
          reason: 'a failed remote deletion must never wipe local state',
        );
        expect(
          signOutCalled,
          isFalse,
          reason: 'a failed remote deletion must never sign the user out '
              'as if the account were actually gone',
        );
      },
    );

    test(
      '2+3. Remote deletion succeeds, local cleanup succeeds: outcome '
      'reports full success and both steps ran in the correct order',
      () async {
        final callOrder = <String>[];

        final outcome = await performAccountDeletion(
          deleteRemote: () async {
            callOrder.add('remote');
          },
          cleanupLocal: () async {
            callOrder.add('cleanup');
          },
          signOutLocal: () async {
            callOrder.add('signOut');
          },
          onCleanupFailure: (_, _) {
            fail('cleanup succeeded — onCleanupFailure must not fire');
          },
        );

        expect(callOrder, ['remote', 'cleanup', 'signOut']);
        expect(outcome.localCleanupSucceeded, isTrue);
        expect(outcome.signOutSucceeded, isTrue);
      },
    );

    test(
      '4. Remote deletion succeeds, local cleanup partially/fully fails: '
      'the failure is reported (not silently absorbed), signOut still '
      'runs, and the overall call does not throw — a local cleanup '
      'hiccup must never be reported as if the deletion itself failed',
      () async {
        Object? reportedError;
        var signOutCalled = false;

        final outcome = await performAccountDeletion(
          deleteRemote: () async {},
          cleanupLocal: () async {
            throw StateError('disk full, could not clear local cache');
          },
          signOutLocal: () async {
            signOutCalled = true;
          },
          onCleanupFailure: (error, stack) {
            reportedError = error;
          },
        );

        expect(
          reportedError,
          isNotNull,
          reason: 'cleanup failure must be observable, not silently '
              'swallowed',
        );
        expect(outcome.localCleanupSucceeded, isFalse);
        expect(
          signOutCalled,
          isTrue,
          reason: 'a local cleanup failure must not block sign-out',
        );
        expect(
          outcome.signOutSucceeded,
          isTrue,
          reason: 'signOut is independent of cleanup outcome',
        );
      },
    );

    test(
      '5. Auth/session cleanup (signOut) fails or is delayed: this is '
      'never conflated with a deletion failure — the overall call still '
      'completes normally, reporting the signOut outcome separately',
      () async {
        final outcome = await performAccountDeletion(
          deleteRemote: () async {},
          cleanupLocal: () async {},
          signOutLocal: () async {
            throw Exception('local session token already invalid');
          },
          onCleanupFailure: (_, _) {
            fail('cleanup succeeded — onCleanupFailure must not fire');
          },
        );

        expect(outcome.localCleanupSucceeded, isTrue);
        expect(
          outcome.signOutSucceeded,
          isFalse,
          reason: 'a signOut failure is recorded, not thrown as if the '
              'deletion failed',
        );
      },
    );

    test(
      '8. A repeated deletion attempt (e.g. a double-tap on the confirm '
      "button) is handled coherently: the second call's own deleteRemote "
      'is responsible for rejecting it (e.g. "already deleted"/no '
      'session) — the orchestrator does not itself attempt to recreate '
      "or recover a already-deleted account merely to finish cleanup",
      () async {
        var deleteAttempts = 0;

        Future<void> delete() async {
          deleteAttempts++;
          if (deleteAttempts > 1) {
            throw Exception('no active session — already deleted');
          }
        }

        await performAccountDeletion(
          deleteRemote: delete,
          cleanupLocal: () async {},
          signOutLocal: () async {},
          onCleanupFailure: (_, _) {},
        );

        // A second, redundant attempt (simulating a double-tap or a user
        // retrying after the first call already succeeded).
        var secondCleanupCalled = false;
        expect(
          () => performAccountDeletion(
            deleteRemote: delete,
            cleanupLocal: () async {
              secondCleanupCalled = true;
            },
            signOutLocal: () async {},
            onCleanupFailure: (_, _) {},
          ),
          throwsA(isA<Exception>()),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          secondCleanupCalled,
          isFalse,
          reason: 'a redundant deletion attempt must not run cleanup '
              'again or attempt to reconstruct account state',
        );
      },
    );

    test(
      '9. The caller is never told remote deletion succeeded when it did '
      'not — deleteRemote\'s exception is the only source of truth, never '
      'overridden by a swallowed catch',
      () async {
        final specificError = ArgumentError('a very specific backend error');

        try {
          await performAccountDeletion(
            deleteRemote: () async => throw specificError,
            cleanupLocal: () async {},
            signOutLocal: () async {},
            onCleanupFailure: (_, _) {},
          );
          fail('performAccountDeletion must rethrow a failed deleteRemote');
        } catch (error) {
          expect(
            error,
            same(specificError),
            reason: 'the exact original error must reach the caller, not '
                'a generic wrapper claiming ambiguous outcome',
          );
        }
      },
    );
  });
}
