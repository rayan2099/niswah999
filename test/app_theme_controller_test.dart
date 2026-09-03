import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/theme/app_theme_controller.dart';
import 'package:niswah/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('theme preference loads, changes, and persists', () async {
    SharedPreferences.setMockInitialValues({'niswah_theme_mode': 'dark'});
    await AppThemeController.instance.load();
    expect(AppThemeController.instance.themeMode, ThemeMode.dark);

    await AppThemeController.instance.setThemeMode(ThemeMode.light);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('niswah_theme_mode'), 'light');

    await AppThemeController.instance.setThemeMode(ThemeMode.system);
    expect(AppThemeController.instance.themeMode, ThemeMode.system);
  });

  test('light and dark themes are distinct and readable', () {
    final light = AppTheme.lightTheme;
    final dark = AppTheme.darkTheme;

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.scaffoldBackgroundColor, isNot(dark.scaffoldBackgroundColor));
    expect(
      _contrastRatio(dark.colorScheme.onSurface, dark.colorScheme.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(light.colorScheme.onSurface, light.colorScheme.surface),
      greaterThanOrEqualTo(4.5),
    );
  });
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
