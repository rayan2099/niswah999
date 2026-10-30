import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_scoped_preferences.dart';

/// Persists the Gregorian / Hijri choice made in the calendar screen, so
/// other dates that follow the calendar (the Insights mood chart and the
/// mental state report's month names) use the same system (rayan,
/// 2026-10-30).
class CalendarSystemController extends ChangeNotifier {
  CalendarSystemController._();

  static final CalendarSystemController instance = CalendarSystemController._();

  static const _storageKey = 'niswah_calendar_hijri';

  bool _hijri = false;

  bool get hijri => _hijri;

  /// Reads the signed-in user's own choice (never another user's).
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getBool(UserScopedPreferences.key(_storageKey));
    if (stored == null || stored == _hijri) return;
    _hijri = stored;
    notifyListeners();
  }

  /// Forgets the in-memory choice (sign-out) so the next account can never
  /// observe it before its own [load] completes.
  void resetInMemory() {
    _hijri = false;
    notifyListeners();
  }

  Future<void> setHijri(bool value) async {
    if (value != _hijri) {
      _hijri = value;
      notifyListeners();
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(UserScopedPreferences.key(_storageKey), value);
  }
}
