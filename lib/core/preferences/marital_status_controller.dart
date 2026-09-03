import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MaritalStatusController extends ChangeNotifier {
  MaritalStatusController._();

  static final MaritalStatusController instance = MaritalStatusController._();
  static const _storageKey = 'niswah_is_married';

  bool _isMarried = false;
  bool get isMarried => _isMarried;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _isMarried = preferences.getBool(_storageKey) ?? false;
  }

  Future<void> setMarried(bool value) async {
    if (_isMarried == value) return;
    _isMarried = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_storageKey, value);
  }
}
