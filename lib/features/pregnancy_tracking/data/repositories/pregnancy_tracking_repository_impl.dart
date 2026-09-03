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
