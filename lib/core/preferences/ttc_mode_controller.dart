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
  bool _isLoaded = false;
  bool _hasExplicitSelection = false;

  /// UI-facing value. The product may render TTC as off by default even
  /// before the user has explicitly chosen; AI context must not confuse that
  /// presentation default with a real user statement.
  bool get enabled => _enabled;

  /// Trust-boundary value: null means no explicit user-scoped TTC preference
  /// has been loaded/saved, so AI context must preserve UNKNOWN rather than
  /// silently turning absence into "not trying to conceive".
  bool? get explicitSelectionOrNull =>
      _isLoaded && _hasExplicitSelection ? _enabled : null;

  /// Reads the signed-in user's own choice (never another user's).
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    await UserScopedPreferences.adoptLegacy(preferences, const [_storageKey]);
    final scopedKey = UserScopedPreferences.key(_storageKey);
    _hasExplicitSelection = preferences.containsKey(scopedKey);
    _enabled = preferences.getBool(scopedKey) ?? false;
    _isLoaded = true;
    notifyListeners();
  }

  /// Forgets the in-memory choice (sign-out) so the next account can never
  /// observe it before its own [load] completes.
  void resetInMemory() {
    _enabled = false;
    _isLoaded = false;
    _hasExplicitSelection = false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    _isLoaded = true;
    _hasExplicitSelection = true;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(UserScopedPreferences.key(_storageKey), value);
  }
}
