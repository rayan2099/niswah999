import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_scoped_preferences.dart';

/// Persists the "TTC Mode" (وضع التخطيط للحمل) toggle, which reveals the
/// fertile window and pregnancy-chance estimate in the cycle calendar.
class TtcModeController extends ChangeNotifier {
  TtcModeController._();

  static final TtcModeController instance = TtcModeController._();

  static const _storageKey = 'niswah_ttc_mode_enabled';

  bool _enabled = false;

  bool get enabled => _enabled;

  /// Reads the signed-in user's own choice (never another user's).
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    await UserScopedPreferences.adoptLegacy(preferences, const [_storageKey]);
    _enabled =
        preferences.getBool(UserScopedPreferences.key(_storageKey)) ?? false;
    notifyListeners();
  }

  /// Forgets the in-memory choice (sign-out) so the next account can never
  /// observe it before its own [load] completes.
  void resetInMemory() {
    _enabled = false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(UserScopedPreferences.key(_storageKey), value);
  }
}
