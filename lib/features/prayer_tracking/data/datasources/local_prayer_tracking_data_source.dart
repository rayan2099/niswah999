import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/prayer_entry.dart';

class LocalPrayerTrackingDataSource {
  LocalPrayerTrackingDataSource({this._preferences});

  static const String _cacheKey = 'niswah_prayer_tracking_logs';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> _getPrefs() async {
    return _preferences ?? await SharedPreferences.getInstance();
  }

  Future<List<PrayerEntry>> loadLogs() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => PrayerEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<PrayerEntry>> loadLogsForDate(
    DateTime date, {
    required String userId,
  }) async {
    final logs = await loadLogs();
    final targetDay = DateTime(date.year, date.month, date.day);
    return logs
        .where(
          (entry) =>
              entry.userId == userId &&
              DateTime(
                entry.date.year,
                entry.date.month,
                entry.date.day,
              ).isAtSameMomentAs(targetDay),
        )
        .toList();
  }

  Future<void> upsert(PrayerEntry entry) async {
    final prefs = await _getPrefs();
    final existing = await loadLogs();
    final updates = <String, PrayerEntry>{};
    for (final item in existing) {
      updates[item.id] = item;
    }
    updates[entry.id] = entry;

    await prefs.setString(
      _cacheKey,
      jsonEncode(updates.values.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> delete(String id) async {
    final prefs = await _getPrefs();
    final existing = await loadLogs();
    final remaining = existing.where((entry) => entry.id != id).toList();

    await prefs.setString(
      _cacheKey,
      jsonEncode(remaining.map((item) => item.toJson()).toList()),
    );
  }
}
