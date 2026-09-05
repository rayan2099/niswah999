import 'dart:convert';

import '../../../../core/storage/secure_local_store.dart';
import '../../domain/entities/prayer_entry.dart';

class LocalPrayerTrackingDataSource {
  static const String _category = 'prayer_tracking_logs';
  static const String _legacyCacheKey = 'niswah_prayer_tracking_logs';

  static bool _isValidLogsJson(String json) {
    try {
      return jsonDecode(json) is List;
    } catch (_) {
      return false;
    }
  }

  // Not cached across calls — see LocalCycleTrackingDataSource for why.
  Future<void> _ensureMigrated() => SecureLocalStore.migrateLegacyIfNeeded(
    legacyKey: _legacyCacheKey,
    category: _category,
    isValid: _isValidLogsJson,
  );

  Future<List<PrayerEntry>> loadLogs() async {
    await _ensureMigrated();
    final raw = await SecureLocalStore.read(_category);
    return SecureLocalStore.decodeJsonListSafely(
      raw: raw,
      category: _category,
      fromJson: PrayerEntry.fromJson,
    );
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
    await _ensureMigrated();
    final existing = await loadLogs();
    final updates = <String, PrayerEntry>{};
    for (final item in existing) {
      updates[item.id] = item;
    }
    updates[entry.id] = entry;

    await SecureLocalStore.write(
      _category,
      jsonEncode(updates.values.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> delete(String id) async {
    await _ensureMigrated();
    final existing = await loadLogs();
    final remaining = existing.where((entry) => entry.id != id).toList();

    await SecureLocalStore.write(
      _category,
      jsonEncode(remaining.map((item) => item.toJson()).toList()),
    );
  }

  /// Removes this user's prayer data — used by account-deletion local
  /// cleanup (Phase F). Takes [userId] explicitly rather than relying on
  /// the current session, since cleanup runs after the server-side
  /// deletion has already invalidated it.
  static Future<void> clearForUser(String userId) =>
      SecureLocalStore.clearForUser(_category, userId);
}
