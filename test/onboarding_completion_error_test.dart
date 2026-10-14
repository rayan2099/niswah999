import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manual QA fix (2026-10-11), Part 2/6: a real onboarding-completion
/// save failure on staging was traced to `_completeOnboarding()`'s
/// `catch (_)` discarding the actual `PostgrestException` entirely —
/// there was no way to tell a transient failure (network, timeout) from
/// a deterministic one (she already has an open bleeding episode, so
/// `record_onboarding_menstrual_history`'s unique-violation on
/// `bleeding_episodes_one_open_per_user` will reject an identical retry
/// every single time) from the generic message alone.
///
/// These tests cover [isNonRetryableDuplicateEpisodeError] — the pure
/// classification function extracted from that catch block. Widget-level
/// coverage of `_completeOnboarding()` itself isn't possible here: it
/// only ever reaches the RPC call when a real authenticated Supabase
/// session exists, and no widget test in this suite has one (confirmed
/// by the existing "truthful last period" test, which explicitly relies
/// on the local-fallback no-session path instead).
void main() {
  test(
    'the exact known duplicate-open-episode constraint violation is '
    'classified as non-retryable',
    () {
      final error = PostgrestException(
        message:
            'duplicate key value violates unique constraint '
            '"bleeding_episodes_one_open_per_user"',
        code: '23505',
      );
      expect(isNonRetryableDuplicateEpisodeError(error), isTrue);
    },
  );

  test(
    'a different unique-violation (same error code, unrelated constraint) '
    'is NOT classified as this specific non-retryable case',
    () {
      final error = PostgrestException(
        message:
            'duplicate key value violates unique constraint '
            '"some_other_constraint_entirely"',
        code: '23505',
      );
      expect(isNonRetryableDuplicateEpisodeError(error), isFalse);
    },
  );

  test(
    'a PostgrestException with a different error code is not classified '
    'as non-retryable, even if the message happens to mention the '
    'constraint name',
    () {
      final error = PostgrestException(
        message: 'bleeding_episodes_one_open_per_user mentioned here',
        code: '57014', // query_canceled -- a genuinely transient case
      );
      expect(isNonRetryableDuplicateEpisodeError(error), isFalse);
    },
  );

  test(
    'a plain network/timeout exception (not a PostgrestException at all) '
    'is never classified as non-retryable — it stays "Try again"-eligible',
    () {
      final error = Exception('SocketException: Failed host lookup');
      expect(isNonRetryableDuplicateEpisodeError(error), isFalse);
    },
  );
}
