import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';

/// App Store guideline 4.8: iOS must not offer Google sign-in without an
/// equivalent privacy-focused option (Sign in with Apple), so iOS shows
/// email and mobile only. Android keeps Google.
void main() {
  Future<void> pumpSignIn(WidgetTester tester) async {
    AppLocaleController.instance.setArabic(false);
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('iOS offers email and mobile sign-in, not Google', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpSignIn(tester);
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Mobile'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android still offers Google sign-in', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpSignIn(tester);
      expect(find.text('Continue with Google'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
