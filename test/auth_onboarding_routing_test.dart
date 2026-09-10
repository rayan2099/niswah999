// AUTH-001/AUTH-002 routing-contract coverage (Critical Authentication /
// Signup Lifecycle wave, 2026-09-10). Exercises `main.dart`'s `_buildHome`
// routing decision directly via `AuthController.instance.setStateForTest`
// (a real Supabase network round-trip isn't practical to fake at the
// widget-test layer this codebase currently has) — see
// production-readiness-results/master/00_04_MASTER_FINDING_REGISTER.md's
// AUTH-002 row for the full root-cause evidence this test matrix guards
// against: `onboarding_completed` must be the sole gate, never the
// transient, process-local `isNewSignUp` flag.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/auth/auth_controller.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:niswah/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // AppLocaleController defaults to Arabic — force English so text
    // assertions below are deterministic regardless of that default.
    AppLocaleController.instance.setArabic(false);
  });

  tearDown(() {
    // Never leak routing state between tests — every test starts from a
    // clean, explicit state, never whatever the previous test left behind.
    AuthController.instance.setStateForTest(
      isAuthenticated: true,
      onboardingCompleted: true,
    );
  });

  group('STATE 1 — unauthenticated', () {
    testWidgets('routes to SignInScreen regardless of onboarding state', (
      tester,
    ) async {
      AuthController.instance.setStateForTest(
        isAuthenticated: false,
        onboardingCompleted: false,
      );

      await tester.pumpWidget(const NiswahApp());
      await tester.pump();

      expect(find.byType(SignInScreen), findsOneWidget);
    });
  });

  group('STATE "checking" — authenticated, onboarding status not yet known', () {
    testWidgets(
      'shows a loading indicator, never guesses dashboard or onboarding',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: null,
        );

        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(SignInScreen), findsNothing);
      },
    );
  });

  group('STATE 3/5 — authenticated, onboarding incomplete', () {
    testWidgets(
      'a confirmed new user (isNewSignUp=false, e.g. confirmed from a cold '
      'start) sees onboarding starting at step 1, not the dashboard '
      '(AUTH-002 — this is exactly the case that used to be silently '
      'skipped)',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: false,
          isNewSignUp: false,
        );

        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        // Step 1's distinctive splash tagline — its presence (and the
        // dashboard's absence) is what actually matters here.
        expect(
          find.text('YOUR CYCLE. YOUR FAITH. YOUR SPACE.'),
          findsOneWidget,
        );
        expect(find.byType(NiswahHomeShell), findsNothing);
      },
    );

    testWidgets(
      'a user who just signed up in this same process (isNewSignUp=true) '
      'still sees onboarding when server state says incomplete — the hint '
      'only changes the starting step, never whether onboarding shows',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: false,
          isNewSignUp: true,
        );

        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        // Step 4 (Madhhab) rendered directly, not step 1 (splash) —
        // confirms the initialStep hint took effect, without ever
        // reaching the dashboard.
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
        expect(find.byType(NiswahHomeShell), findsNothing);
      },
    );
  });

  group('STATE 4 — authenticated, onboarding complete', () {
    testWidgets('routes straight to the dashboard shell', (tester) async {
      AuthController.instance.setStateForTest(
        isAuthenticated: true,
        onboardingCompleted: true,
      );

      await tester.pumpWidget(const NiswahApp());
      await tester.pumpAndSettle();

      expect(find.byType(NiswahHomeShell), findsOneWidget);
    });
  });

  group('Regression: the old isNewSignUp-only heuristic cannot resurface', () {
    testWidgets(
      'isNewSignUp=false alone must never be read as "onboarding complete" '
      '— only onboardingCompleted decides that',
      (tester) async {
        // This is the exact production defect (AUTH-002): a confirmed new
        // user reaches this state (authenticated, isNewSignUp false
        // because markSignedUp() is never called on the email-confirmation
        // path, onboarding genuinely incomplete). The old code read
        // isNewSignUp as the gate and would send her straight to
        // NiswahHomeShell here. The fix must not.
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: false,
          isNewSignUp: false,
        );

        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        expect(find.byType(NiswahHomeShell), findsNothing);
      },
    );

    testWidgets(
      'isNewSignUp=true alone must never be read as "onboarding incomplete" '
      'once the server says otherwise (a returning user signing in again '
      'must never be re-forced through onboarding by a stray flag)',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: true,
          isNewSignUp: true,
        );

        await tester.pumpWidget(const NiswahApp());
        await tester.pumpAndSettle();

        expect(find.byType(NiswahHomeShell), findsOneWidget);
      },
    );
  });

  group('Completion persists the durable flag, not just local navigation', () {
    testWidgets(
      'OnboardingScreen.onFinished sets onboardingCompleted locally so a '
      'rebuild immediately reflects it, without needing a fresh app launch',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: false,
        );

        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        // Simulate what OnboardingScreen's onFinished callback does on
        // real completion (the network write itself is covered by
        // AuthRepositoryImpl's own contract, not re-tested here).
        AuthController.instance.setOnboardingCompletedLocally(true);
        await tester.pumpAndSettle();

        expect(find.byType(NiswahHomeShell), findsOneWidget);
      },
    );
  });
}
