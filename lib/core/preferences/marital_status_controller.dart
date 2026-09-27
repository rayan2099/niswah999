import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_scoped_preferences.dart';

class MaritalStatusController extends ChangeNotifier {
  MaritalStatusController._();

  static final MaritalStatusController instance = MaritalStatusController._();
  static const _storageKey = 'niswah_is_married';

  bool _isMarried = false;
  bool get isMarried => _isMarried;

  /// Reads the signed-in user's own answer (never another user's).
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    await UserScopedPreferences.adoptLegacy(preferences, const [_storageKey]);
    _isMarried =
        preferences.getBool(UserScopedPreferences.key(_storageKey)) ?? false;
    notifyListeners();
  }

  /// Forgets the in-memory answer (sign-out) so the next account can never
  /// observe it before its own [load] completes.
  void resetInMemory() {
    _isMarried = false;
    notifyListeners();
  }

  Future<void> setMarried(bool value) async {
    if (_isMarried == value) return;
    _isMarried = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(UserScopedPreferences.key(_storageKey), value);
  }
}
