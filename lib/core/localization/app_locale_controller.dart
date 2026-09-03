import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocaleController extends ChangeNotifier {
  AppLocaleController._();
  static final AppLocaleController instance = AppLocaleController._();

  bool _isArabic = true;
  bool get isArabic => _isArabic;
  Locale get locale => Locale(_isArabic ? 'ar' : 'en');
  TextDirection get textDirection =>
      _isArabic ? TextDirection.rtl : TextDirection.ltr;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _isArabic = preferences.getBool('niswah_arabic') ?? true;
  }

  void setArabic(bool value) {
    if (_isArabic == value) return;
    _isArabic = value;
    notifyListeners();
    SharedPreferences.getInstance().then(
      (preferences) => preferences.setBool('niswah_arabic', value),
    );
  }

  String text(String english, String arabic) => _isArabic ? arabic : english;
}
