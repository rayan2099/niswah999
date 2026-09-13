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

        // Madhhab (step 3 — AUTH-008 removed the old embedded login step
        // that used to sit at step 3) rendered directly, not step 1
        // (splash) — confirms the initialStep hint took effect, without
        // ever reaching the dashboard.
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
        expect(find.byType(NiswahHomeShell), findsNothing);
        expect(find.byType(SignInScreen), findsNothing);
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

  // AUTH-008: a fresh app launch/restart re-evaluates the exact same
  // `_buildHome` contract from scratch each time — these tests exercise
  // that directly by pumping a brand-new `NiswahApp()` for each of the
  // charter's four required restart scenarios, confirming none of them
  // ever shows `SignInScreen` for an authenticated user.
  group('AUTH-008 — app restart scenarios', () {
    testWidgets(
      '1. authenticated + onboarding incomplete -> restart -> onboarding',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: false,
        );
        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        expect(find.byType(NiswahHomeShell), findsNothing);
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('YOUR CYCLE. YOUR FAITH. YOUR SPACE.'), findsOneWidget);
      },
    );

    testWidgets(
      '2. authenticated + onboarding complete -> restart -> dashboard',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: true,
        );
        await tester.pumpWidget(const NiswahApp());
        await tester.pumpAndSettle();

        expect(find.byType(NiswahHomeShell), findsOneWidget);
        expect(find.byType(SignInScreen), findsNothing);
      },
    );

    testWidgets('3. unauthenticated -> restart -> auth', (tester) async {
      AuthController.instance.setStateForTest(
        isAuthenticated: false,
        onboardingCompleted: false,
      );
      await tester.pumpWidget(const NiswahApp());
      await tester.pump();

      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets(
      '4. partial onboarding + app killed -> reopen -> onboarding '
      'incomplete, no auth repetition (isNewSignUp lost across restart, '
      'as it always is — this must still never surface SignInScreen)',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: false,
          isNewSignUp: false,
        );
        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        expect(find.byType(SignInScreen), findsNothing);
        expect(find.byType(NiswahHomeShell), findsNothing);
      },
    );
  });

  // AUTH-008: logout/login must never produce login -> onboarding -> login
  // again. Each test drives AuthController through the real event sequence
  // (sign-out fires `isAuthenticated: false`; sign-in re-authenticates)
  // rather than only checking static states in isolation.
  group('AUTH-008 — logout / login', () {
    testWidgets(
      'partial onboarding -> logout -> login -> onboarding (not stuck on '
      'Sign In, not skipped to dashboard)',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: false,
        );
        await tester.pumpWidget(const NiswahApp());
        await tester.pump();
        expect(find.byType(SignInScreen), findsNothing);

        // Logout.
        AuthController.instance.setStateForTest(
          isAuthenticated: false,
          onboardingCompleted: false,
        );
        await tester.pump();
        expect(find.byType(SignInScreen), findsOneWidget);

        // Login again — server state still says incomplete.
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: false,
        );
        await tester.pump();

        expect(find.byType(SignInScreen), findsNothing);
        expect(find.byType(NiswahHomeShell), findsNothing);
        expect(find.text('YOUR CYCLE. YOUR FAITH. YOUR SPACE.'), findsOneWidget);
      },
    );

    testWidgets(
      'completed onboarding -> logout -> login -> dashboard directly '
      '(never re-shown onboarding or a repeated Sign In)',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: true,
        );
        await tester.pumpWidget(const NiswahApp());
        await tester.pumpAndSettle();
        expect(find.byType(NiswahHomeShell), findsOneWidget);

        // Logout.
        AuthController.instance.setStateForTest(
          isAuthenticated: false,
          onboardingCompleted: true,
        );
        await tester.pump();
        expect(find.byType(SignInScreen), findsOneWidget);
        expect(find.byType(NiswahHomeShell), findsNothing);

        // Login again — server state still says complete.
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: true,
        );
        await tester.pumpAndSettle();

        expect(find.byType(NiswahHomeShell), findsOneWidget);
        expect(find.byType(SignInScreen), findsNothing);
      },
    );
  });

  // AUTH-008 — charter items M/N: the two "already confirmed" journeys
  // must never re-show signup/onboarding UI they've already passed.
  group('AUTH-008 — returning-user journeys', () {
    testWidgets(
      'confirmed + onboarding complete -> login -> dashboard directly; '
      'never language, Madhhab, signup, or onboarding of any kind',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: true,
        );
        await tester.pumpWidget(const NiswahApp());
        await tester.pumpAndSettle();

        expect(find.byType(NiswahHomeShell), findsOneWidget);
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Choose your language'), findsNothing);
        expect(find.text('What is your Fiqh Madhhab?'), findsNothing);
      },
    );

    testWidgets(
      'confirmed + onboarding incomplete -> login -> onboarding; never '
      'signup shown again',
      (tester) async {
        AuthController.instance.setStateForTest(
          isAuthenticated: true,
          onboardingCompleted: false,
        );
        await tester.pumpWidget(const NiswahApp());
        await tester.pump();

        expect(find.byType(NiswahHomeShell), findsNothing);
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('YOUR CYCLE. YOUR FAITH. YOUR SPACE.'), findsOneWidget);
      },
    );
  });
}
