/// Result of one [performAccountDeletion] run — lets a caller distinguish
/// "everything succeeded" from "the account is gone but local cleanup
/// needs a retry" without inferring it from exception shape alone.
class AccountDeletionOutcome {
  const AccountDeletionOutcome({
    required this.localCleanupSucceeded,
    required this.signOutSucceeded,
  });

  final bool localCleanupSucceeded;
  final bool signOutSucceeded;
}

/// The account-deletion sequencing contract, extracted from
/// `AuthRepositoryImpl.deleteAccount` so it is directly unit-testable
/// with injected fakes instead of a live/mocked Supabase client
/// (Reliability Evidence Closure wave, 2026-09-06).
///
/// Contract (destructive-action reliability, per the Reliability/
/// Resilience Final Closure wave's REMOTE_AUTHORITATIVE model, applied at
/// its strictest since this action is irreversible):
/// 1. [deleteRemote] must succeed before anything else runs — a failure
///    here propagates immediately, local state is untouched, and the
///    caller must never claim the account was deleted.
/// 2. Once remote deletion is confirmed, [cleanupLocal] runs best-effort:
///    a failure is reported via [onCleanupFailure], not rethrown — the
///    account is genuinely deleted server-side by this point, and a local
///    cleanup hiccup must not make the app claim the deletion itself
///    failed, nor may it be silently treated as though nothing went wrong.
/// 3. [signOutLocal] always runs last, best-effort — its own failure is
///    swallowed here too, since the account is already gone server-side
///    regardless of whether the local session clears cleanly.
Future<AccountDeletionOutcome> performAccountDeletion({
  required Future<void> Function() deleteRemote,
  required Future<void> Function() cleanupLocal,
  required Future<void> Function() signOutLocal,
  required void Function(Object error, StackTrace stack) onCleanupFailure,
}) async {
  // Step 1: no local state is touched, and no success is claimed, unless
  // this succeeds. A thrown error here propagates to the caller verbatim.
  await deleteRemote();

  // Step 2: remote deletion is confirmed at this point — local cleanup is
  // best-effort and must not undo or misreport that fact.
  var localCleanupSucceeded = true;
  try {
    await cleanupLocal();
  } catch (error, stack) {
    localCleanupSucceeded = false;
    onCleanupFailure(error, stack);
  }

  // Step 3: best-effort, independent of cleanup's outcome.
  var signOutSucceeded = true;
  try {
    await signOutLocal();
  } catch (_) {
    signOutSucceeded = false;
  }

  return AccountDeletionOutcome(
    localCleanupSucceeded: localCleanupSucceeded,
    signOutSucceeded: signOutSucceeded,
  );
}
