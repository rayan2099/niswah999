import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/pregnancy_milestone.dart';

class LocalPregnancyTrackingDataSource {
  LocalPregnancyTrackingDataSource({this._preferences});

  static const String _cacheKey = 'niswah_pregnancy_tracking_milestones';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> _getPrefs() async {
    return _preferences ?? await SharedPreferences.getInstance();
  }

  Future<List<PregnancyMilestone>> loadMilestones() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) => PregnancyMilestone.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> upsert(PregnancyMilestone milestone) async {
    final prefs = await _getPrefs();
    final existing = await loadMilestones();
    final updates = <String, PregnancyMilestone>{};
    for (final item in existing) {
      updates[item.id] = item;
    }
    updates[milestone.id] = milestone;

    await prefs.setString(
      _cacheKey,
      jsonEncode(updates.values.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> delete(String id) async {
    final prefs = await _getPrefs();
    final existing = await loadMilestones();
    final remaining = existing.where((item) => item.id != id).toList();

    await prefs.setString(
      _cacheKey,
      jsonEncode(remaining.map((item) => item.toJson()).toList()),
    );
  }
}
