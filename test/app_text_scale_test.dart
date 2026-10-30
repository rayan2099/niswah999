import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/theme/app_theme.dart';

import 'support/parity_test_harness.dart';

/// Testing feedback 2026-10-30: text across the app should be a little
/// larger. The app applies one factor on top of the phone's own setting.
void main() {
  test('the app factor multiplies the phone setting, never replaces it', () {
    expect(
      const AppTextScaler(TextScaler.noScaling).scale(10),
      closeTo(11, 1e-9),
    );
    expect(
      const AppTextScaler(TextScaler.linear(1.5)).scale(10),
      closeTo(16.5, 1e-9),
      reason: 'someone who already enlarged text keeps it, plus the step',
    );
    expect(
      AppTypography.appTextScale,
      inInclusiveRange(1.05, 1.15),
      reason: '"just a bit": a small step, not a redesign',
    );
  });

  for (final arabic in [true, false]) {
    testWidgets(
      'every screen under NiswahApp sees the enlarged scaler (arabic: $arabic)',
      (tester) async {
        await ParityTestHarness.pump(tester, arabic: arabic);
        final context = tester.element(find.byType(Scaffold).first);
        expect(MediaQuery.textScalerOf(context).scale(10), closeTo(11, 1e-9));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
