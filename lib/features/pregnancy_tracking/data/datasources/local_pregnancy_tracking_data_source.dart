import 'dart:convert';

import '../../../../core/storage/secure_local_store.dart';
import '../../domain/entities/pregnancy_milestone.dart';

class LocalPregnancyTrackingDataSource {
  static const String _category = 'pregnancy_tracking_milestones';
  static const String _legacyCacheKey = 'niswah_pregnancy_tracking_milestones';

  static bool _isValidMilestonesJson(String json) {
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
    isValid: _isValidMilestonesJson,
  );

  Future<List<PregnancyMilestone>> loadMilestones() async {
    await _ensureMigrated();
    final raw = await SecureLocalStore.read(_category);
    return SecureLocalStore.decodeJsonListSafely(
      raw: raw,
      category: _category,
      fromJson: PregnancyMilestone.fromJson,
    );
  }

  Future<void> upsert(PregnancyMilestone milestone) async {
    await _ensureMigrated();
    final existing = await loadMilestones();
    final updates = <String, PregnancyMilestone>{};
    for (final item in existing) {
      updates[item.id] = item;
    }
    updates[milestone.id] = milestone;

    await SecureLocalStore.write(
      _category,
      jsonEncode(updates.values.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> delete(String id) async {
    await _ensureMigrated();
    final existing = await loadMilestones();
    final remaining = existing.where((item) => item.id != id).toList();

    await SecureLocalStore.write(
      _category,
      jsonEncode(remaining.map((item) => item.toJson()).toList()),
    );
  }

  /// Removes this user's pregnancy milestone data — used by account-deletion
  /// local cleanup (Phase F). Takes [userId] explicitly rather than relying
  /// on the current session, since cleanup runs after the server-side
  /// deletion has already invalidated it.
  static Future<void> clearForUser(String userId) =>
      SecureLocalStore.clearForUser(_category, userId);
}
