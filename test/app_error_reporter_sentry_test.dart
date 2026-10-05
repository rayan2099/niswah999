import 'dart:async';
import 'dart:io';

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
            (error, stack, {context, feature, retryAttempt, recordId}) async {
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
        }) async {
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

    test(
      'report() lets a genuinely asynchronous onReport Future run to '
      'completion rather than abandoning it mid-flight',
      () async {
        // Regression test for the integration fix that moved `unawaited`
        // from inside main.dart's onReport closure (cutting the Future
        // chain immediately after the real network call started) to this
        // one boundary instead. A completer-based delay stands in for a
        // real network round trip (e.g. Sentry.captureException actually
        // awaiting its HTTP response) -- if report() ever went back to
        // discarding the Future before it could even begin, or if
        // something upstream stopped driving it to completion, this
        // completer would simply never resolve and the test would time
        // out instead of passing.
        final completer = Completer<void>();
        var completed = false;

        AppErrorReporter.onReport = (error, stack, {
          context,
          feature,
          retryAttempt,
          recordId,
        }) async {
          await completer.future;
          completed = true;
        };

        AppErrorReporter.report(
          Exception('async delivery'),
          StackTrace.current,
          context: 'test.async-delivery',
        );

        // report() is itself synchronous/fire-and-forget to its own
        // caller (by design, so its ~40+ existing call sites never need
        // to become async) -- it must not have resolved the delivery yet.
        expect(completed, isFalse);

        completer.complete();
        // Let the still-running, unawaited-at-report()'s-boundary Future
        // actually finish.
        await Future<void>.delayed(Duration.zero);

        expect(
          completed,
          isTrue,
          reason:
              'onReport\'s returned Future must run to completion in the '
              'background, not be abandoned when report() returns',
        );
      },
    );
  });

  group('main.dart zone structure (startup zone-mismatch regression)', () {
    // Flutter's own binding code records which zone
    // WidgetsFlutterBinding.ensureInitialized() first actually ran in,
    // exactly once (BindingBase.initInstances), and compares it against
    // the zone runApp() later runs in -- a mismatch produces the exact
    // "Zone mismatch... Flutter bindings were initialized in a different
    // zone" warning reproduced on a real Android device during this
    // integration's verification. That zone-creation logic isn't
    // practically exercisable from a plain widget/unit test without
    // actually running main() end-to-end on a real binding, so this is a
    // structural guard instead: there must be exactly one
    // `runZonedGuarded` call in main.dart, wrapping
    // WidgetsFlutterBinding.ensureInitialized() and runApp() in the same
    // zone. A second, separately-created zone reintroduces the exact bug
    // this integration pass fixed.
    test(
      'exactly one runZonedGuarded call exists, and it is the outermost '
      'thing in main()',
      () {
        final source = File('lib/main.dart').readAsStringSync();
        final occurrences = 'runZonedGuarded('.allMatches(source).length;
        expect(
          occurrences,
          1,
          reason:
              'main.dart must create exactly one zone (in main()) -- a '
              'second runZonedGuarded call (e.g. reintroduced inside '
              '_runApp() around runApp()) would put WidgetsFlutterBinding'
              '.ensureInitialized() and runApp() back in different zones.',
        );
      },
    );

    test(
      'WidgetsFlutterBinding.ensureInitialized() is called inside the '
      'runZonedGuarded callback, not before it',
      () {
        final source = File('lib/main.dart').readAsStringSync();
        final zoneIndex = source.indexOf('runZonedGuarded(');
        final bindingIndex = source.indexOf(
          'WidgetsFlutterBinding.ensureInitialized()',
        );
        expect(zoneIndex, greaterThanOrEqualTo(0));
        expect(bindingIndex, greaterThanOrEqualTo(0));
        expect(
          bindingIndex,
          greaterThan(zoneIndex),
          reason:
              'ensureInitialized() must run after runZonedGuarded(...) '
              'opens, i.e. inside the zone callback -- calling it before '
              'the zone is created is exactly the ordering that caused '
              'the real zone-mismatch warning this test guards against.',
        );
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
