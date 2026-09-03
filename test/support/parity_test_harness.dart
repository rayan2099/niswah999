import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParityTestHarness {
  static bool _fontsLoaded = false;

  static Future<void> pump(
    WidgetTester tester, {
    required bool arabic,
    Size size = const Size(390, 844),
    int initialTabIndex = 0,
    Map<String, Object> extraPrefs = const {},
  }) async {
    AppClock.now = () => DateTime(2026, 8, 18, 12);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    await _loadFonts();
    SharedPreferences.setMockInitialValues({
      'niswah_arabic': arabic,
      ...extraPrefs,
    });
    await AppLocaleController.instance.load();
    await MaritalStatusController.instance.load();
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(NiswahApp(initialTabIndex: initialTabIndex));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  static Future<void> _loadFonts() async {
    if (_fontsLoaded) return;
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
    await (FontLoader(
          'Playfair Display',
        )..addFont(rootBundle.load('assets/fonts/PlayfairDisplay-Regular.ttf')))
        .load();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    _fontsLoaded = true;
  }
}
