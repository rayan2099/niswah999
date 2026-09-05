import 'dart:convert';

import 'package:collection/collection.dart';

import '../../../../core/storage/secure_local_store.dart';
import '../../domain/entities/cycle_log.dart';

class LocalCycleTrackingDataSource {
  static const _category = 'cycle_tracking_logs';
  static const _legacyCacheKey = 'niswah_cycle_tracking_logs';

  static bool _isValidLogsJson(String json) {
    try {
      return jsonDecode(json) is List;
    } catch (_) {
      return false;
    }
  }

  // Not cached across calls: SecureLocalStore.migrateLegacyIfNeeded is
  // itself idempotent (it checks for an existing migrated value first), so
  // caching here would only save one secure-storage read per call — not
  // worth the statefulness (it would also make the migration silently
  // un-retryable within a running app session if an earlier attempt failed
  // transiently).
  Future<void> _ensureMigrated() => SecureLocalStore.migrateLegacyIfNeeded(
    legacyKey: _legacyCacheKey,
    category: _category,
    isValid: _isValidLogsJson,
  );

  Future<List<CycleLog>> loadLogs() async {
    await _ensureMigrated();
    final raw = await SecureLocalStore.read(_category);
    return SecureLocalStore.decodeJsonListSafely(
      raw: raw,
      category: _category,
      fromJson: CycleLog.fromJson,
    );
  }

  Future<CycleLog?> getById(String id) async {
    final logs = await loadLogs();
    return logs.where((log) => log.id == id).firstOrNull;
  }

  Future<void> upsert(CycleLog log) async {
    await _ensureMigrated();
    final existing = await loadLogs();
    final updates = <String, CycleLog>{};
    for (final item in existing) {
      updates[item.id] = item;
    }
    updates[log.id] = log;

    final encoded = jsonEncode(
      updates.values.map((item) => item.toJson()).toList(),
    );
    await SecureLocalStore.write(_category, encoded);
  }

  Future<void> delete(String id) async {
    await _ensureMigrated();
    final existing = await loadLogs();
    final remaining = existing.where((log) => log.id != id).toList();

    await SecureLocalStore.write(
      _category,
      jsonEncode(remaining.map((item) => item.toJson()).toList()),
    );
  }

  /// Removes this user's cycle data — used by account-deletion local
  /// cleanup (Phase F). Takes [userId] explicitly rather than relying on
  /// the current session, since cleanup runs after the server-side
  /// deletion has already invalidated it.
  static Future<void> clearForUser(String userId) =>
      SecureLocalStore.clearForUser(_category, userId);
}
