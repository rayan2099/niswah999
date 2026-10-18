import 'dart:convert';

import 'package:collection/collection.dart';

import '../../../../core/storage/secure_local_store.dart';
import '../../../../core/storage/scoped_mutation_queue.dart';
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
  Future<void> _ensureMigrated(String owner) =>
      SecureLocalStore.migrateLegacyIfNeeded(
        legacyKey: _legacyCacheKey,
        category: _category,
        isValid: _isValidLogsJson,
        userId: owner,
      );

  Future<List<CycleLog>> loadLogs({String? userId}) {
    final owner = userId ?? SecureLocalStore.currentUserId();
    return ScopedMutationQueue.run(
      category: _category,
      owner: owner,
      action: () => _loadForOwner(owner),
    );
  }

  Future<List<CycleLog>> _loadForOwner(String owner) async {
    await _ensureMigrated(owner);
    final raw = await SecureLocalStore.read(_category, userId: owner);
    return SecureLocalStore.decodeJsonListSafely(
      raw: raw,
      category: _category,
      fromJson: CycleLog.fromJson,
    );
  }

  Future<CycleLog?> getById(String id, {String? userId}) async {
    final logs = await loadLogs(userId: userId);
    return logs.where((log) => log.id == id).firstOrNull;
  }

  Future<void> upsert(CycleLog log, {String? userId}) {
    final owner = userId ?? SecureLocalStore.currentUserId();
    return ScopedMutationQueue.run(
      category: _category,
      owner: owner,
      action: () async {
        final existing = await _loadForOwner(owner);
        final updates = {for (final item in existing) item.id: item};
        updates[log.id] = log;
        await _writeForOwner(owner, updates.values);
      },
    );
  }

  /// A response only acknowledges the exact snapshot sent to the server.
  /// A newer edit or a deletion must survive an older request completing.
  Future<void> acknowledge(
    CycleLog expected,
    SyncStatus status, {
    required String userId,
  }) => ScopedMutationQueue.run(
    category: _category,
    owner: userId,
    action: () async {
      final existing = await _loadForOwner(userId);
      final current = existing
          .where((log) => log.id == expected.id)
          .firstOrNull;
      if (current == null ||
          !const DeepCollectionEquality().equals(
            current.toJson(),
            expected.toJson(),
          )) {
        return;
      }
      await _writeForOwner(
        userId,
        existing.map(
          (log) =>
              log.id == expected.id ? log.copyWith(syncStatus: status) : log,
        ),
      );
    },
  );

  Future<void> delete(String id, {String? userId}) {
    final owner = userId ?? SecureLocalStore.currentUserId();
    return ScopedMutationQueue.run(
      category: _category,
      owner: owner,
      action: () async {
        final existing = await _loadForOwner(owner);
        await _writeForOwner(owner, existing.where((log) => log.id != id));
      },
    );
  }

  Future<void> _writeForOwner(String owner, Iterable<CycleLog> logs) =>
      SecureLocalStore.write(
        _category,
        jsonEncode(logs.map((item) => item.toJson()).toList()),
        userId: owner,
      );

  /// Removes this user's cycle data — used by account-deletion local
  /// cleanup (Phase F). Takes [userId] explicitly rather than relying on
  /// the current session, since cleanup runs after the server-side
  /// deletion has already invalidated it.
  static Future<void> clearForUser(String userId) => ScopedMutationQueue.run(
    category: _category,
    owner: userId,
    action: () => SecureLocalStore.clearForUser(_category, userId),
  );
}
