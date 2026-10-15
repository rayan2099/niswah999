import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_storage_test_support.dart';

class ParityTestHarness {
  static bool _fontsLoaded = false;

  static Future<void> pump(
    WidgetTester tester, {
    required bool arabic,
    Size size = const Size(390, 844),
    int initialTabIndex = 0,
    Map<String, Object> extraPrefs = const {},
    // New critical finding (Fiqh regression fix) — lets a test mount a
    // specific screen directly (e.g. DashboardScreen with canonical-
    // evidence injection points set) instead of the full NiswahApp, while
    // still sharing every other piece of fixed test setup below (the
    // clock, fonts, locale, secure-storage reset) that a real canonical
    // evidence scenario still depends on. Wrapped in a bare MaterialApp,
    // mirroring how every other standalone-screen widget test in this
    // suite already mounts a screen.
    Widget? homeOverride,
  }) async {
    AppClock.now = () => DateTime(2026, 8, 18, 12);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    await _loadFonts();
    SharedPreferences.setMockInitialValues({
      'niswah_arabic': arabic,
      ...extraPrefs,
    });
    // Reset at the same granularity as SharedPreferences above — several
    // parity test files call ParityTestHarness.pump() multiple times per
    // file, seeding different cycle/prayer fixtures each time. Without
    // this, secure storage from an earlier call in the same file persists
    // (flutter_test_config.dart only resets it once per *file*), so a
    // later call's freshly-seeded legacy SharedPreferences data gets
    // silently ignored — migration sees secure storage already populated
    // from the earlier call and short-circuits as "already migrated."
    resetSecureLocalStoreForTest();
    await AppLocaleController.instance.load();
    await MaritalStatusController.instance.load();
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      homeOverride == null
          ? NiswahApp(initialTabIndex: initialTabIndex)
          : MaterialApp(home: homeOverride),
    );
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
