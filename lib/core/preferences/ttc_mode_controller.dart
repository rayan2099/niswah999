import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the "TTC Mode" (وضع التخطيط للحمل) toggle, which reveals the
/// fertile window and pregnancy-chance estimate in the cycle calendar.
class TtcModeController extends ChangeNotifier {
  TtcModeController._();

  static final TtcModeController instance = TtcModeController._();

  static const _storageKey = 'niswah_ttc_mode_enabled';

  bool _enabled = false;

  bool get enabled => _enabled;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(_storageKey) ?? false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_storageKey, value);
  }
}
