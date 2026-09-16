// Startup Auth-Gate Infinite-Spinner Investigation (AUTH-012). The root
// router in main.dart used to show an indefinite loading spinner whenever
// AuthController.onboardingCompleted (the old `bool?` contract) was `null`
// — a value that meant "still checking" AND "checking failed", with no way
// to tell them apart, and a `completed != _onboardingCompleted` guard that
// silently suppressed notifyListeners() whenever a failed check produced
// `null` on top of an already-`null` value. This suite exercises
// AuthController's real generation-guarded, timeout-bounded,
// error-classifying logic directly (via the `refreshOnboardingStatusForTest`
// seam — a real Supabase network round-trip isn't practical to fake at the
// widget-test layer this codebase currently has), plus the router's own
// rendering of the new explicit OnboardingStatus states.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/auth/auth_controller.dart';
import 'package:niswah/core/errors/app_error_reporter.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
  });

  tearDown(() {
    AppErrorReporter.onReport = null;
    AuthController.instance.setStateForTest(
      isAuthenticated: true,
      onboardingCompleted: true,
    );
  });

  group('AuthController.refreshOnboardingStatus — state-model correctness', () {
    testWidgets('A. server returns onboarding=false -> incomplete', (
      tester,
    ) async {
      await AuthController.instance.refreshOnboardingStatusForTest(
        () async => {'onboarding_completed': false},
      );
      expect(
        AuthController.instance.onboardingStatus,
        OnboardingStatus.incomplete,
      );
    });

    testWidgets('B. server returns onboarding=true -> complete', (
      tester,
    ) async {
      await AuthController.instance.refreshOnboardingStatusForTest(
        () async => {'onboarding_completed': true},
      );
      expect(
        AuthController.instance.onboardingStatus,
        OnboardingStatus.complete,
      );
    });

    testWidgets('C. server throws -> explicit error, never left on loading', (
      tester,
    ) async {
      Object? reported;
      AppErrorReporter.onReport =
          (error, stack, {context, feature, retryAttempt, recordId}) {
            reported = error;
          };

      await AuthController.instance.refreshOnboardingStatusForTest(
        () async => throw Exception('simulated query failure'),
      );

      expect(AuthController.instance.onboardingStatus, OnboardingStatus.error);
      expect(
        reported,
        isNotNull,
        reason: 'a thrown query error must be reported, not silently swallowed',
      );
    });

    testWidgets(
      'D. authenticated user has no public.users row -> defined error, never a guessed route',
      (tester) async {
        Object? reported;
        AppErrorReporter.onReport =
            (error, stack, {context, feature, retryAttempt, recordId}) {
              reported = error;
            };

        // maybeSingle() returns null when no row matches — not an
        // exception. This must not be silently treated as "onboarding
        // complete" (skips onboarding for someone who never did it) nor
        // silently repaired.
        await AuthController.instance.refreshOnboardingStatusForTest(
          () async => null,
        );

        expect(
          AuthController.instance.onboardingStatus,
          OnboardingStatus.error,
        );
        expect(
          reported,
          isNotNull,
          reason: 'a missing public.users row must be reported, not silent',
        );
      },
    );

    testWidgets('E. slow response: loading first, then resolves correctly', (
      tester,
    ) async {
      final completer = Completer<Map<String, dynamic>?>();
      final future = AuthController.instance.refreshOnboardingStatusForTest(
        () => completer.future,
      );
      await tester.pump();
      expect(
        AuthController.instance.onboardingStatus,
        OnboardingStatus.loading,
      );

      completer.complete({'onboarding_completed': true});
      await future;

      expect(
        AuthController.instance.onboardingStatus,
        OnboardingStatus.complete,
      );
    });

    testWidgets('F. timeout -> explicit error, not an indefinite spinner', (
      tester,
    ) async {
      final future = AuthController.instance.refreshOnboardingStatusForTest(
        () => Future.delayed(
          const Duration(seconds: 30),
          () => {'onboarding_completed': true},
        ),
      );
      await tester.pump();
      expect(
        AuthController.instance.onboardingStatus,
        OnboardingStatus.loading,
      );

      // Past the internal 15s bound but before the underlying (never
      // truly arriving in a real timeout scenario) response.
      await tester.pump(const Duration(seconds: 16));
      expect(AuthController.instance.onboardingStatus, OnboardingStatus.error);

      // Let the still-pending underlying delayed Future also elapse so no
      // Timer is left dangling at teardown.
      await tester.pump(const Duration(seconds: 20));
      await future;
    });

    testWidgets('G. retry after a failure can succeed', (tester) async {
      await AuthController.instance.refreshOnboardingStatusForTest(
        () async => throw Exception('first attempt fails'),
      );
      expect(AuthController.instance.onboardingStatus, OnboardingStatus.error);

      await AuthController.instance.refreshOnboardingStatusForTest(
        () async => {'onboarding_completed': true},
      );
      expect(
        AuthController.instance.onboardingStatus,
        OnboardingStatus.complete,
        reason: 'a retry must be able to leave the error state behind',
      );
    });

    testWidgets(
      'H. logout while a fetch is in flight discards its stale result',
      (tester) async {
        final completer = Completer<Map<String, dynamic>?>();
        final inFlight = AuthController.instance.refreshOnboardingStatusForTest(
          () => completer.future,
        );
        await tester.pump();
        expect(
          AuthController.instance.onboardingStatus,
          OnboardingStatus.loading,
        );

        // Simulates the real onAuthStateChange sign-out path, which bumps
        // the request generation precisely so this can never apply late.
        AuthController.instance.setStateForTest(
          isAuthenticated: false,
          onboardingCompleted: null,
        );
        expect(
          AuthController.instance.onboardingStatus,
          OnboardingStatus.loading,
        );

        completer.complete({'onboarding_completed': true}); // now stale
        await inFlight;
        await tester.pump();

        expect(
          AuthController.instance.onboardingStatus,
          OnboardingStatus.loading,
          reason:
              'a result from before logout must never overwrite the '
              'post-logout state',
        );
      },
    );

    testWidgets(
      "I. account switch mid-flight: user A's stale result cannot affect user B",
      (tester) async {
        final completerA = Completer<Map<String, dynamic>?>();
        final futureA = AuthController.instance.refreshOnboardingStatusForTest(
          () => completerA.future,
        );
        await tester.pump();

        // User B's own real fetch starts before A's resolves — a new
        // request generation, exactly as a real account switch would
        // produce via onAuthStateChange's sign-in transition.
        await AuthController.instance.refreshOnboardingStatusForTest(
          () async => {'onboarding_completed': false},
        );
        expect(
          AuthController.instance.onboardingStatus,
          OnboardingStatus.incomplete,
          reason: "user B's own real result",
        );

        completerA.complete({'onboarding_completed': true}); // stale
        await futureA;
        await tester.pump();

        expect(
          AuthController.instance.onboardingStatus,
          OnboardingStatus.incomplete,
          reason:
              "user A's stale result must never override user B's real "
              'state',
        );
      },
    );
  });

  group(
    'Root router — OnboardingStatus.error renders a real, recoverable screen',
    () {
      testWidgets('shows the error screen, not an indefinite spinner', (
        tester,
      ) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingStatus: OnboardingStatus.error,
        );
        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        expect(find.text("We couldn't load your account."), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Sign out'), findsOneWidget);
      });

      testWidgets('Arabic: shows the Arabic error copy', (tester) async {
        AppLocaleController.instance.setArabic(true);
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingStatus: OnboardingStatus.error,
        );
        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        expect(find.text('تعذر تحميل حسابك'), findsOneWidget);
        expect(find.text('إعادة المحاولة'), findsOneWidget);
        expect(find.text('تسجيل الخروج'), findsOneWidget);
        AppLocaleController.instance.setArabic(false);
      });

      testWidgets(
        'shows the loading indicator, not the error screen, while loading',
        (tester) async {
          AuthController.instance.setStateForTest(
            isAuthenticated: true,
            onboardingCompleted: null,
          );
          await tester.pumpWidget(const NiswahApp());
          await tester.pump();

          expect(find.text("We couldn't load your account."), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        },
      );
    },
  );
}
