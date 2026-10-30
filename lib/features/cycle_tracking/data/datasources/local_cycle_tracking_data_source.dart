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
  Future<void> _ensureMigrated(String ownerId) =>
      SecureLocalStore.migrateLegacyIfNeeded(
        legacyKey: _legacyCacheKey,
        category: _category,
        isValid: _isValidLogsJson,
        userId: ownerId,
      );

  Future<List<CycleLog>> loadLogs() =>
      _loadLogs(SecureLocalStore.currentUserId());

  Future<List<CycleLog>> _loadLogs(String ownerId) async {
    await _ensureMigrated(ownerId);
    final raw = await SecureLocalStore.read(_category, userId: ownerId);
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
    final ownerId = SecureLocalStore.currentUserId();
    return SecureLocalStore.serialized(_category, () async {
      final existing = await _loadLogs(ownerId);
      final updates = <String, CycleLog>{};
      for (final item in existing) {
        updates[item.id] = item;
      }
      updates[log.id] = log;
      await _writeAll(updates.values, ownerId);
    });
  }

  Future<void> delete(String id) {
    final ownerId = SecureLocalStore.currentUserId();
    return SecureLocalStore.serialized(_category, () async {
      final existing = await _loadLogs(ownerId);
      await _writeAll(existing.where((log) => log.id != id), ownerId);
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
  Future<bool> setSyncStatusIfUnchanged(
    CycleLog uploaded,
    SyncStatus status, {
    String? userId,
  }) {
    // A response belongs to the bucket used before the request, even if
    // another account is active by the time the network completes.
    final ownerId = userId ?? SecureLocalStore.currentUserId();
    return SecureLocalStore.serialized(_category, () async {
      final existing = await _loadLogs(ownerId);
      final index = existing.indexWhere((log) => log.id == uploaded.id);
      if (index < 0) return false;
      final current = existing[index];
      if (_contentKey(current) != _contentKey(uploaded)) return false;
      if (current.syncStatus == status) return true;
      existing[index] = current.copyWith(syncStatus: status);
      await _writeAll(existing, ownerId);
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

  Future<void> _writeAll(Iterable<CycleLog> logs, String ownerId) =>
      SecureLocalStore.write(
        _category,
        jsonEncode(logs.map((item) => item.toJson()).toList()),
        userId: ownerId,
      );

  /// Removes this user's cycle data — used by account-deletion local
  /// cleanup (Phase F). Takes [userId] explicitly rather than relying on
  /// the current session, since cleanup runs after the server-side
  /// deletion has already invalidated it.
  static Future<void> clearForUser(String userId) =>
      SecureLocalStore.clearForUser(_category, userId);
}
