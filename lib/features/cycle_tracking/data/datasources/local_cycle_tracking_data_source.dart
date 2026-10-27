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
  Future<void> _ensureMigrated(String owner) => SecureLocalStore.migrateLegacyIfNeeded(
    legacyKey: _legacyCacheKey,
    category: _category,
    isValid: _isValidLogsJson,
    userId: owner,
  );

  Future<List<CycleLog>> loadLogs({String? userId}) async {
    final owner = userId ?? SecureLocalStore.currentUserId();
    await _ensureMigrated(owner);
    final raw = await SecureLocalStore.read(_category, userId: owner);
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

  // Every mutation below is a read-modify-write of one stored list, so
  // each runs under SecureLocalStore.serialized: two overlapping writers
  // (a save during a background sync, say) otherwise both read the old
  // list and the second write drops the first one's change.
  Future<void> upsert(CycleLog log) {
    final owner = SecureLocalStore.currentUserId();
    return SecureLocalStore.serialized(_category, () async {
        final existing = await loadLogs(userId: owner);
        final updates = <String, CycleLog>{};
        for (final item in existing) {
          updates[item.id] = item;
        }
        updates[log.id] = log;
        await _writeAll(updates.values, owner);
      });
  }

  Future<void> delete(String id) {
    final owner = SecureLocalStore.currentUserId();
    return SecureLocalStore.serialized(_category, () async {
        final existing = await loadLogs(userId: owner);
        await _writeAll(existing.where((log) => log.id != id), owner);
      });
  }

  /// Sets the stored copy of [uploaded] to [status] only if that copy
  /// still holds what was uploaded (same day, flow, notes, symptoms, cycle
  /// day, owner and provenance). A sync pass works from a snapshot and
  /// awaits the network per row; an edit she saved meanwhile is newer than
  /// what was uploaded and must stay `pending` (and keep its content)
  /// instead of being overwritten by the stale snapshot marked `synced`.
  /// A row deleted meanwhile is not brought back. Returns whether the
  /// status was written.
  Future<bool> setSyncStatusIfUnchanged(CycleLog uploaded, SyncStatus status) {
    final owner = SecureLocalStore.currentUserId();
    return SecureLocalStore.serialized(_category, () async {
        final existing = await loadLogs(userId: owner);
        final index = existing.indexWhere((log) => log.id == uploaded.id);
        if (index < 0) return false;
        final current = existing[index];
        if (_contentKey(current) != _contentKey(uploaded)) return false;
        if (current.syncStatus == status) return true;
        existing[index] = current.copyWith(syncStatus: status);
        await _writeAll(existing, owner);
        return true;
      });
  }

  static String _contentKey(CycleLog log) => jsonEncode(
    log.toJson()
      ..remove('sync_status')
      ..remove('time_logged')
      ..remove('created_at')
      ..remove('updated_at'),
  );

  Future<void> _writeAll(Iterable<CycleLog> logs, String owner) => SecureLocalStore.write(
    _category,
    jsonEncode(logs.map((item) => item.toJson()).toList()),
    userId: owner,
  );

  /// Removes this user's cycle data — used by account-deletion local
  /// cleanup (Phase F). Takes [userId] explicitly rather than relying on
  /// the current session, since cleanup runs after the server-side
  /// deletion has already invalidated it.
  static Future<void> clearForUser(String userId) =>
      SecureLocalStore.serialized(_category, () =>
          SecureLocalStore.clearForUser(_category, userId));
}
