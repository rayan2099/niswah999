import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final instance = AppThemeController._();
  static const _preferenceKey = 'niswah_theme_mode';

  // Niswah is designed light-first; dark mode is opt-in from Profile, so a
  // phone in system dark mode still opens the app in light mode.
  static const defaultMode = ThemeMode.light;

  /// Off for launch: many screens still hard-code light colors, so dark mode
  /// was hard to read (device run 2026-10-28, A23). While off, the app is
  /// always light and Profile hides the choice; a saved choice is kept, so
  /// turning this back on restores it.
  static const darkModeAvailable = false;

  ThemeMode _themeMode = defaultMode;

  /// The mode the app renders with.
  ThemeMode get themeMode => darkModeAvailable ? _themeMode : ThemeMode.light;

  /// The mode she last picked, even while [darkModeAvailable] is off.
  ThemeMode get savedThemeMode => _themeMode;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_preferenceKey);
    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => defaultMode,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, mode.name);
  }
}
