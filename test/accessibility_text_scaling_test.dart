import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

/// AU-006 / Phase D: the dashboard's cycle ring and phase-timeline nodes
/// render inside fixed-pixel-diameter containers. This wave wrapped their
/// value/unit/headline text in `FittedBox(fit: BoxFit.scaleDown)` so large
/// OS text-scale settings shrink the text to fit rather than clipping
/// against the circle. These tests render the real dashboard at large
/// scale factors and fail on any layout overflow exception — a stronger
/// check than reading the code, though still not a substitute for a real
/// device's actual Dynamic Type / font-scale setting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDashboardAtScale(
    WidgetTester tester,
    double scale, {
    bool arabic = false,
  }) async {
    AppLocaleController.instance.setArabic(arabic);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const DashboardScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final scale in [1.0, 1.5, 2.0, 3.0]) {
    testWidgets(
      'dashboard renders with no layout overflow at ${scale}x text scale '
      '(English)',
      (tester) async {
        await pumpDashboardAtScale(tester, scale);
        expect(
          tester.takeException(),
          isNull,
          reason:
              'a RenderFlex overflow or other layout exception was thrown '
              'at ${scale}x text scale',
        );
      },
    );

    testWidgets(
      'dashboard renders with no layout overflow at ${scale}x text scale '
      '(Arabic/RTL)',
      (tester) async {
        await pumpDashboardAtScale(tester, scale, arabic: true);
        expect(
          tester.takeException(),
          isNull,
          reason:
              'a RenderFlex overflow or other layout exception was thrown '
              'at ${scale}x text scale in Arabic',
        );
      },
    );
  }
}
