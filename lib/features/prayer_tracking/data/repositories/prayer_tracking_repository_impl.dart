import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/prayer_entry.dart';
import '../../domain/repositories/prayer_tracking_repository.dart';
import '../datasources/local_prayer_tracking_data_source.dart';

class PrayerTrackingRepositoryImpl implements PrayerTrackingRepository {
  PrayerTrackingRepositoryImpl({
    SupabaseClient? client,
    LocalPrayerTrackingDataSource? localDataSource,
  }) : _client = client ?? NiswahSupabase.clientOrNull,
       _localDataSource = localDataSource ?? LocalPrayerTrackingDataSource();

  final SupabaseClient? _client;
  final LocalPrayerTrackingDataSource _localDataSource;

  @override
  Future<List<PrayerEntry>> getDailyPrayerLog(
    DateTime date, {
    required String userId,
  }) async {
    final localLogs = await _localDataSource.loadLogsForDate(
      date,
      userId: userId,
    );
    final client = _client;
    if (client == null) {
      return localLogs;
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      return localLogs;
    }

    try {
      final response = await client
          .from('prayer_entries')
          .select()
          .eq('user_id', sessionUser.id)
          .eq('date', date.toIso8601String().substring(0, 10));

      final remote = (response as List<dynamic>)
          .map((item) => PrayerEntry.fromJson(item as Map<String, dynamic>))
          .toList();

      final merged = <String, PrayerEntry>{};
      for (final entry in [...localLogs, ...remote]) {
        merged[entry.id] = entry;
      }

      final ordered = merged.values.toList()
        ..sort((a, b) => a.prayerName.index.compareTo(b.prayerName.index));
      return ordered;
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    } catch (_) {
      return localLogs;
    }
  }

  @override
  Future<List<PrayerEntry>> getPrayerHistory({
    required String userId,
    DateTime? from,
    DateTime? to,
  }) async {
    final localLogs = await _localDataSource.loadLogs();
    final filteredLocal = localLogs
        .where((entry) => entry.userId == userId)
        .where((entry) {
          if (from != null && entry.date.isBefore(from)) {
            return false;
          }
          if (to != null && entry.date.isAfter(to)) {
            return false;
          }
          return true;
        })
        .toList();

    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      return filteredLocal;
    }

    try {
      var query = client.from('prayer_entries').select().eq('user_id', userId);
      if (from != null) {
        query = query.gte('date', from.toIso8601String().substring(0, 10));
      }
      if (to != null) {
        query = query.lte('date', to.toIso8601String().substring(0, 10));
      }

      final response = await query.order('date', ascending: false);
      final remote = (response as List<dynamic>)
          .map((item) => PrayerEntry.fromJson(item as Map<String, dynamic>))
          .toList();

      final merged = <String, PrayerEntry>{};
      for (final entry in [...filteredLocal, ...remote]) {
        merged[entry.id] = entry;
      }
      final ordered = merged.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return ordered;
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    } catch (_) {
      return filteredLocal;
    }
  }

  @override
  Future<void> savePrayer(PrayerEntry entry) async {
    await _localDataSource.upsert(entry);
    final client = _client;
    if (client == null) {
      return;
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null || sessionUser.id != entry.userId) {
      return;
    }

    try {
      final payload = {...entry.toJson(), 'user_id': sessionUser.id};

      await client.from('prayer_entries').upsert(payload, onConflict: 'id');
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }

  @override
  Future<void> deletePrayer(String id) async {
    await _localDataSource.delete(id);
    final client = _client;
    if (client == null) {
      return;
    }

    try {
      await client.from('prayer_entries').delete().eq('id', id);
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }
}
