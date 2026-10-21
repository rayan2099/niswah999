import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_scoped_preferences.dart';

class MaritalStatusController extends ChangeNotifier {
  MaritalStatusController._();

  static final MaritalStatusController instance = MaritalStatusController._();
  static const _storageKey = 'niswah_is_married';

  // Onboarding/server hardening (proposed, finding #13): null until she
  // actually answers. Previously this defaulted to false, so onboarding
  // pre-selected "No" for a first-time user and `setMarried(false)` was a
  // no-op that never stored her real answer.
  bool? _isMarried;

  /// Whether she said she is married; false when unanswered (spouse-only
  /// tools stay hidden until she says yes).
  bool get isMarried => _isMarried ?? false;

  /// Her saved answer, or null when she has not answered yet.
  bool? get answer => _isMarried;

  /// Reads the signed-in user's own answer (never another user's).
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    await UserScopedPreferences.adoptLegacy(preferences, const [_storageKey]);
    _isMarried = preferences.getBool(UserScopedPreferences.key(_storageKey));
    notifyListeners();
  }

  /// Forgets the in-memory answer (sign-out) so the next account can never
  /// observe it before its own [load] completes.
  void resetInMemory() {
    _isMarried = null;
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
