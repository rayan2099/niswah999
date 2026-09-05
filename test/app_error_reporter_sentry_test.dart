import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/errors/app_error_reporter.dart';
import 'package:niswah/main.dart' show scrubSecretsForSentry;

void main() {
  group('AppErrorReporter -> Sentry funnel wiring (OB-006)', () {
    tearDown(() {
      // Every existing call site (FlutterError.onError, PlatformDispatcher's
      // handler, runZonedGuarded, and ~40+ repository catch blocks) shares
      // this one static hook — a test that forgets to reset it would leak
      // into every other test in the suite.
      AppErrorReporter.onReport = null;
    });

    test(
      'report() forwards error, stack, and all context fields to onReport unchanged',
      () {
        Object? capturedError;
        StackTrace? capturedStack;
        String? capturedContext;
        String? capturedFeature;
        int? capturedRetryAttempt;
        String? capturedRecordId;

        AppErrorReporter.onReport =
            (error, stack, {context, feature, retryAttempt, recordId}) {
              capturedError = error;
              capturedStack = stack;
              capturedContext = context;
              capturedFeature = feature;
              capturedRetryAttempt = retryAttempt;
              capturedRecordId = recordId;
            };

        final error = Exception('boom');
        final stack = StackTrace.current;

        AppErrorReporter.report(
          error,
          stack,
          context: 'test.context',
          feature: 'test_feature',
          retryAttempt: 2,
          recordId: 'record-123',
        );

        // This is the exact contract main.dart's AppErrorReporter.onReport
        // wiring depends on: Sentry.captureException(error, stackTrace: stack)
        // plus scope tags/contexts built from these same fields. If report()
        // ever stopped forwarding one of these unchanged, Sentry would either
        // lose the original exception or lose its grouping/diagnostic context
        // silently — this test would fail immediately.
        expect(capturedError, same(error));
        expect(capturedStack, same(stack));
        expect(capturedContext, 'test.context');
        expect(capturedFeature, 'test_feature');
        expect(capturedRetryAttempt, 2);
        expect(capturedRecordId, 'record-123');
      },
    );

    test('report() is a no-op destination-wise when onReport is unset', () {
      // The exact OB-006 gap this integration closes: with no destination
      // wired (e.g. no SENTRY_DSN configured), report() must not throw —
      // it just doesn't reach anywhere beyond debugPrint.
      AppErrorReporter.onReport = null;
      expect(
        () => AppErrorReporter.report(
          Exception('no destination configured'),
          StackTrace.current,
          context: 'test.no-destination',
        ),
        returnsNormally,
      );
    });

    test(
      'a second report() call invokes onReport exactly once per call — no '
      'duplicate delivery for a single reported error',
      () {
        var invocationCount = 0;
        AppErrorReporter.onReport = (error, stack, {
          context,
          feature,
          retryAttempt,
          recordId,
        }) {
          invocationCount++;
        };

        AppErrorReporter.report(
          Exception('single error'),
          StackTrace.current,
          context: 'test.single-delivery',
        );

        expect(invocationCount, 1);
      },
    );
  });

  group('scrubSecretsForSentry (defense-in-depth secret redaction)', () {
    test('redacts a Bearer token', () {
      final input = 'request failed: Authorization: Bearer abc123.def-456_ghi';
      final scrubbed = scrubSecretsForSentry(input);

      expect(scrubbed, isNot(contains('abc123.def-456_ghi')));
      expect(scrubbed, contains('Bearer [redacted]'));
    });

    test('redacts a JWT-shaped string (e.g. a leaked Supabase access token)', () {
      const fakeJwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLTEifQ.c2lnbmF0dXJl';
      final input = 'unexpected token in header: $fakeJwt';
      final scrubbed = scrubSecretsForSentry(input);

      expect(scrubbed, isNot(contains(fakeJwt)));
      expect(scrubbed, contains('[redacted-jwt]'));
    });

    test('leaves ordinary diagnostic text (e.g. a Postgres error) untouched', () {
      const pgError =
          'duplicate key value violates unique constraint "pregnancy_profile_user_id_key"';
      expect(scrubSecretsForSentry(pgError), pgError);
    });
  });
}
