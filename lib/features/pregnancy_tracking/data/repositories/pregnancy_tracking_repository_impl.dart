import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/pregnancy_milestone.dart';
import '../../domain/repositories/pregnancy_tracking_repository.dart';
import '../datasources/local_pregnancy_tracking_data_source.dart';

class PregnancyTrackingRepositoryImpl implements PregnancyTrackingRepository {
  PregnancyTrackingRepositoryImpl({
    LocalPregnancyTrackingDataSource? localDataSource,
    SupabaseClient? supabaseClient,
  }) : _localDataSource = localDataSource ?? LocalPregnancyTrackingDataSource(),
       _supabaseClient = supabaseClient ?? NiswahSupabase.clientOrNull;

  final LocalPregnancyTrackingDataSource _localDataSource;
  final SupabaseClient? _supabaseClient;

  // NOT a simple rename: production has no `pregnancy_milestones` table.
  // The live `pregnancy_records` table exists under a different, incompatible
  // shape — one row per pregnancy (lmp_date, due_date, current_week,
  // birth_date, nifas_id, weekly_notes jsonb) — not one row per dated
  // milestone (week, trimester, label, summary, date) the way this repository
  // needs. Repointing `_tableName` at `pregnancy_records` would still fail
  // (e.g. `.order('date', ...)` below has no matching column there), just
  // with a different, more confusing error, and both paths currently
  // fall back to local-only data identically. A real fix requires a product
  // decision — either add proper milestone columns/table live (a schema
  // migration, gated on Wave 0 approval per W0-002) or redesign this
  // feature to persist milestones inside `pregnancy_records.weekly_notes`.
  // See W0-002 / 00_10_WAVE0_EXECUTION_REPORT.md.
  static const String _tableName = 'pregnancy_milestones';

  @override
  Future<List<PregnancyMilestone>> getMilestonesForUser(String userId) async {
    final localEntries = await _localDataSource.loadMilestones();
    final userEntries = localEntries
        .where((item) => item.userId == userId)
        .toList();

    final client = _supabaseClient;
    if (client == null) {
      return userEntries;
    }

    try {
      final response = await client
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .order('date', ascending: false);

      final remoteEntries = (response as List)
          .map(
            (item) =>
                PregnancyMilestone.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();

      final merged = <String, PregnancyMilestone>{};
      for (final item in [...userEntries, ...remoteEntries]) {
        merged[item.id] = item;
      }

      final sorted = merged.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return sorted;
    } catch (_) {
      return userEntries;
    }
  }

  @override
  Future<void> saveMilestone(PregnancyMilestone milestone) async {
    await _localDataSource.upsert(milestone);

    final client = _supabaseClient;
    if (client == null) {
      return;
    }

    try {
      final payload = milestone.toJson();
      await client.from(_tableName).upsert(payload);
    } catch (_) {
      // Local-first persistence remains authoritative when remote sync is unavailable.
    }
  }

  @override
  Future<void> deleteMilestone(String id) async {
    await _localDataSource.delete(id);

    final client = _supabaseClient;
    if (client == null) {
      return;
    }

    try {
      await client.from(_tableName).delete().eq('id', id);
    } catch (_) {
      // Ignore remote deletion failures to preserve offline resilience.
    }
  }
}
