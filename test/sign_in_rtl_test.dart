import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:niswah/features/onboarding/presentation/screens/onboarding_screen.dart';

/// AUTH-008 (shares its root cause with AUTH-007 — see
/// `onboarding_ui_test.dart`'s AUTH-007 group): the owner reported the
/// Sign In / Sign Up sheet appearing "flipped/mirrored" under Arabic.
/// `SignInScreen` reads `AppLocaleController` directly for its own text
/// (always correct), but when embedded in onboarding it used to inherit
/// ambient `Directionality` from the onboarding shell's stale local
/// `_arabic` field — producing genuinely-Arabic text inside an
/// LTR-mirrored layout. These tests lock in correct RTL/LTR behavior for
/// both the standalone screen and the embedded (onboarding step 3) case,
/// across viewport size, text scale, and semantics.
void main() {
  final signInTab = find.byKey(const Key('mode_tab_sign_in'));
  final signUpTab = find.byKey(const Key('mode_tab_sign_up'));

  // Standalone SignInScreen has no Directionality of its own — in the real
  // app it always renders under main.dart's top-level
  // `MaterialApp(builder: (context, child) => Directionality(textDirection:
  // AppLocaleController.instance.textDirection, child: child))`. A bare
  // `MaterialApp(home: SignInScreen())` in a test has no such ancestor and
  // silently defaults to LTR regardless of the selected locale — this
  // reproduces the real app's wiring so standalone-mode RTL assertions are
  // meaningful.
  Widget standaloneApp(Widget home) => MaterialApp(
    builder: (context, child) => Directionality(
      textDirection: AppLocaleController.instance.textDirection,
      child: child!,
    ),
    home: home,
  );

  Future<void> openAuthSheet(WidgetTester tester, {required String email}) async {
    // The consent InkWell intentionally spans the full row width (a larger
    // tap target than just the visible checkbox glyph + text — reasonable
    // accessibility practice, not a bug). Tapping its geometric center is
    // therefore ambiguous: depending on exact text layout/wrapping, that
    // center point can coincide with the nested "Privacy Policy"/"Terms of
    // Use" TapGestureRecognizer spans instead of toggling consent — this
    // happens to differ between English and Arabic layouts. Tap the small
    // checkbox glyph itself instead, which has an unambiguous, direction-
    // correct render box regardless of the surrounding text's layout.
    final checkboxGlyph = find.descendant(
      of: find.byKey(const Key('consent_checkbox')),
      matching: find.byType(AnimatedContainer),
    );
    await tester.ensureVisible(checkboxGlyph);
    await tester.pumpAndSettle();
    await tester.tap(checkboxGlyph);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(email));
    await tester.pumpAndSettle();
    await tester.tap(find.text(email));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'standalone Sign In sheet renders LTR under English, with correct tab '
    'labels and signup-field toggling',
    (tester) async {
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(standaloneApp(const SignInScreen()));
      await tester.pumpAndSettle();
      await openAuthSheet(tester, email: 'Email');

      expect(find.text('Sign In'), findsWidgets);
      expect(find.text('Sign Up'), findsWidgets);
      expect(find.text('Full name'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Directionality &&
              widget.textDirection == TextDirection.ltr,
        ),
        findsWidgets,
      );

      await tester.tap(signUpTab);
      await tester.pumpAndSettle();
      expect(
        find.text('Full name'),
        findsOneWidget,
        reason: 'tapping the Sign Up tab must actually render signup fields',
      );

      await tester.tap(signInTab);
      await tester.pumpAndSettle();
      expect(
        find.text('Full name'),
        findsNothing,
        reason: 'tapping the Sign In tab must hide the signup-only fields',
      );
    },
  );

  testWidgets(
    'standalone Sign In sheet renders RTL under Arabic, with correct tab '
    'labels and signup-field toggling',
    (tester) async {
      AppLocaleController.instance.setArabic(true);
      await tester.pumpWidget(standaloneApp(const SignInScreen()));
      await tester.pumpAndSettle();
      await openAuthSheet(tester, email: 'البريد الإلكتروني');

      expect(find.text('تسجيل الدخول'), findsWidgets);
      expect(find.text('إنشاء حساب'), findsWidgets);
      expect(find.text('الاسم الكامل'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Directionality &&
              widget.textDirection == TextDirection.rtl,
        ),
        findsWidgets,
        reason: 'the auth sheet must be wrapped in RTL Directionality',
      );
      expect(find.text('Sign In'), findsNothing);
      expect(find.text('Sign Up'), findsNothing);

      await tester.tap(signUpTab);
      await tester.pumpAndSettle();
      expect(
        find.text('الاسم الكامل'),
        findsOneWidget,
        reason: 'tapping the إنشاء حساب tab must render signup fields',
      );

      await tester.tap(signInTab);
      await tester.pumpAndSettle();
      expect(
        find.text('الاسم الكامل'),
        findsNothing,
        reason: 'tapping the تسجيل الدخول tab must hide the signup fields',
      );
    },
  );

  testWidgets(
    'embedded Sign In sheet (onboarding step 3) renders RTL under Arabic '
    'with correct tab labels',
    (tester) async {
      AppLocaleController.instance.setArabic(true);
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onFinished: () {}, initialStep: 3),
        ),
      );
      await tester.pumpAndSettle();
      await openAuthSheet(tester, email: 'البريد الإلكتروني');

      expect(find.text('تسجيل الدخول'), findsWidgets);
      expect(find.text('إنشاء حساب'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Directionality &&
              widget.textDirection == TextDirection.rtl,
        ),
        findsWidgets,
      );

      await tester.tap(signUpTab);
      await tester.pumpAndSettle();
      expect(find.text('الاسم الكامل'), findsOneWidget);
    },
  );

  // The following three cross-cutting checks deliberately stop at the
  // entry step (language toggle + Email/Mobile choice) rather than
  // reaching the credentials tab step — at a genuinely narrow width the
  // consent checkbox's own tap target can overlap the adjoining Privacy
  // Policy link's tap recognizer once the row reflows, which is a
  // pre-existing test-navigation hazard unrelated to RTL correctness
  // (also called out in `sign_in_consent_gating_test.dart`). The entry
  // step already carries the same `_LanguageToggle`/Directionality
  // machinery under test, so it is equally valid RTL coverage without
  // that hazard.
  testWidgets('Arabic entry step renders with no layout exception on a '
      'small viewport', (tester) async {
    AppLocaleController.instance.setArabic(true);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(standaloneApp(const SignInScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Directionality &&
            widget.textDirection == TextDirection.rtl,
      ),
      findsWidgets,
    );
  });

  testWidgets('Arabic entry step renders with no layout exception at 200% '
      'text scale', (tester) async {
    AppLocaleController.instance.setArabic(true);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Directionality(
          textDirection: AppLocaleController.instance.textDirection,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
        ),
        home: const SignInScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
  });

  testWidgets('Arabic entry step exposes a valid semantics tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    AppLocaleController.instance.setArabic(true);
    await tester.pumpWidget(standaloneApp(const SignInScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
    handle.dispose();
  });
}
