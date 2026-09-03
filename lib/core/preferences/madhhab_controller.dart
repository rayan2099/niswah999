import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

class MadhhabController extends ChangeNotifier {
  MadhhabController._();

  static final MadhhabController instance = MadhhabController._();
  static const _storageKey = 'niswah_selected_madhhab';

  Madhhab _selected = Madhhab.hanbali;
  Madhhab get selected => _selected;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_storageKey);
    _selected = Madhhab.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => Madhhab.hanbali,
    );
  }

  Future<void> select(Madhhab value) async {
    if (_selected == value) return;
    _selected = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, value.name);
  }
}
