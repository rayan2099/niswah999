import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/errors/failures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapRepositoryError classification (RR-001/OB-007/AB-010)', () {
    test('a plain network exception is retryable', () {
      final failure = mapRepositoryError(
        Exception('Connection reset'),
        StackTrace.empty,
        context: 'test.network',
      );

      expect(failure, isA<NetworkFailure>());
      expect(failure.retryable, isTrue);
      expect(failure.context, 'test.network');
      expect(failure.cause, isNotNull);
    });

    test(
      'a real AuthApiException (session/credential rejection) is AuthFailure, non-retryable',
      () {
        final failure = mapRepositoryError(
          const AuthApiException('Invalid login credentials', statusCode: '400'),
          StackTrace.empty,
          context: 'test.auth',
        );

        expect(failure, isA<AuthFailure>());
        expect(failure.retryable, isFalse);
      },
    );

    test(
      'a real AuthRetryableFetchException (network blip during auth) IS retryable',
      () {
        // Despite the type name containing "Auth", this specifically means
        // the request to refresh/validate a session failed at the network
        // level — retrying is correct, unlike an actual credential
        // rejection (AuthApiException, above). A blanket "any type named
        // *Auth* -> non-retryable" rule would have gotten this wrong.
        final failure = mapRepositoryError(
          AuthRetryableFetchException(),
          StackTrace.empty,
          context: 'test.auth-retryable-fetch',
        );

        expect(failure, isA<NetworkFailure>());
        expect(failure.retryable, isTrue);
      },
    );

    test(
      'a user-safe message never leaks the raw exception text',
      () {
        const rawSecret = 'password authentication failed for user "svc_role_xyz"';
        final failure = mapRepositoryError(
          Exception(rawSecret),
          StackTrace.empty,
          context: 'test.safe-message',
        );

        expect(failure.message, isNot(contains('svc_role_xyz')));
        // The raw detail is preserved only in `cause`, for
        // AppErrorReporter/diagnostics — never in the user-facing message.
        expect(failure.cause.toString(), contains(rawSecret));
      },
    );

    test('Failure retains the original cause and stack trace (OB-007)', () {
      final originalError = Exception('boom');
      final stack = StackTrace.current;
      final failure = mapRepositoryError(
        originalError,
        stack,
        context: 'test.cause-preserved',
      );

      expect(failure.cause, same(originalError));
      expect(failure.stackTrace, same(stack));
    });

    group('real PostgrestException classification', () {
      test('a known-transient code (query_canceled) is retryable', () {
        final failure = mapRepositoryError(
          const PostgrestException(
            message: 'canceling statement due to timeout',
            code: '57014',
          ),
          StackTrace.empty,
          context: 'test.pg-transient',
        );

        expect(failure, isA<NetworkFailure>());
        expect(failure.retryable, isTrue);
      });

      test('an RLS/policy rejection (42501) is non-retryable', () {
        final failure = mapRepositoryError(
          const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
          StackTrace.empty,
          context: 'test.pg-rls',
        );

        expect(failure.retryable, isFalse);
      });

      test(
        'a gateway-level failure (PostgREST unreachable, surfaced as code '
        '"502" instead of a Postgres SQLSTATE) is retryable — PJ-002 '
        'regression: discovered via a real forced-outage test where '
        'stopping the backend produced exactly this shape and was wrongly '
        'classified permanently failed instead of pending-for-retry',
        () {
          final failure = mapRepositoryError(
            const PostgrestException(
              message:
                  'An invalid response was received from the upstream server',
              code: '502',
            ),
            StackTrace.empty,
            context: 'test.pg-gateway-502',
          );

          expect(failure.retryable, isTrue);
        },
      );

      test('a unique-constraint violation (23505) is non-retryable', () {
        final failure = mapRepositoryError(
          const PostgrestException(
            message: 'duplicate key value violates unique constraint',
            code: '23505',
          ),
          StackTrace.empty,
          context: 'test.pg-unique-violation',
        );

        expect(
          failure.retryable,
          isFalse,
          reason:
              'retrying an identical insert would fail identically every time — must not be retried blindly',
        );
      });
    });
  });

  group('Failure hierarchy backward compatibility', () {
    test('existing two-argument construction still compiles and works', () {
      // This is the exact call shape used at ~120+ existing call sites
      // across the app — must keep working unchanged.
      const failure = NetworkFailure('Something went wrong.');
      expect(failure.message, 'Something went wrong.');
      expect(failure.cause, isNull);
      expect(failure.retryable, isTrue); // NetworkFailure's own default
    });

    test('ValidationFailure defaults to non-retryable', () {
      const failure = ValidationFailure('Invalid input.');
      expect(failure.retryable, isFalse);
    });
  });
}
