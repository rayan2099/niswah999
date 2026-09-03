import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/cycle_log.dart';

class LocalCycleTrackingDataSource {
  static const _cacheKey = 'niswah_cycle_tracking_logs';

  Future<List<CycleLog>> loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => CycleLog.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CycleLog?> getById(String id) async {
    final logs = await loadLogs();
    return logs.where((log) => log.id == id).firstOrNull;
  }

  Future<void> upsert(CycleLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadLogs();
    final updates = <String, CycleLog>{};
    for (final item in existing) {
      updates[item.id] = item;
    }
    updates[log.id] = log;

    final encoded = jsonEncode(
      updates.values.map((item) => item.toJson()).toList(),
    );
    await prefs.setString(_cacheKey, encoded);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadLogs();
    final remaining = existing.where((log) => log.id != id).toList();

    await prefs.setString(
      _cacheKey,
      jsonEncode(remaining.map((item) => item.toJson()).toList()),
    );
  }
}
