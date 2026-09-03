import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../datasources/local_cycle_tracking_data_source.dart';
import '../../domain/entities/cycle_log.dart';
import '../../domain/repositories/cycle_tracking_repository.dart';

class CycleTrackingRepositoryImpl implements CycleTrackingRepository {
  CycleTrackingRepositoryImpl({
    SupabaseClient? client,
    LocalCycleTrackingDataSource? localDataSource,
  }) : _client = client ?? NiswahSupabase.clientOrNull,
       _localDataSource = localDataSource ?? LocalCycleTrackingDataSource();

  final SupabaseClient? _client;
  final LocalCycleTrackingDataSource _localDataSource;

  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    final localLogs = await _localDataSource.loadLogs();
    final client = _client;
    if (client == null) {
      return localLogs;
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      return localLogs;
    }

    try {
      var query = client
          .from('cycle_entries')
          .select()
          .eq('user_id', sessionUser.id);

      if (from != null) {
        query = query.filter(
          'date',
          'gte',
          from.toIso8601String().substring(0, 10),
        );
      }
      if (to != null) {
        query = query.filter(
          'date',
          'lte',
          to.toIso8601String().substring(0, 10),
        );
      }

      final response = await query.order('date', ascending: false).limit(limit);
      final remote = (response as List<dynamic>)
          .map((item) => CycleLog.fromJson(item as Map<String, dynamic>))
          .toList();

      final merged = <String, CycleLog>{};
      for (final entry in [...localLogs, ...remote]) {
        merged[entry.id] = entry;
      }
      final ordered = merged.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return ordered;
    } on PostgrestException catch (error) {
      // Local save is authoritative for the UI (see saveCycleLog below) —
      // a remote read failure here must never make an already-saved local
      // log disappear from the caller. This used to rethrow as a
      // NetworkFailure instead, which meant CycleTrackingViewModel.loadLogs
      // caught it *before* ever assigning `logs`, silently wiping out
      // whatever had just been saved locally moments earlier.
      debugPrint('[CycleTracking] getCycleLogs remote read failed: ${error.message}');
      return localLogs;
    } catch (_) {
      return localLogs;
    }
  }

  @override
  Future<CycleLog?> getCycleLogById(String id) async {
    final client = _client;
    if (client == null) {
      return _localDataSource.getById(id);
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      final local = await _localDataSource.getById(id);
      return local;
    }

    try {
      final response = await client
          .from('cycle_entries')
          .select()
          .eq('id', id)
          .eq('user_id', sessionUser.id)
          .maybeSingle();

      if (response == null) {
        return await _localDataSource.getById(id);
      }
      return CycleLog.fromJson(response);
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }

  @override
  Future<void> saveCycleLog(CycleLog log) async {
    await _localDataSource.upsert(log);
    try {
      await upsertCycleLog(log);
    } on NetworkFailure catch (error) {
      // Local save is authoritative for the UI; remote sync is eventually-
      // consistent (see SyncStatus.pending / syncPendingLogs()). Swallow
      // here so a transient network/schema issue never hides an already-
      // successful local save from the caller — see getCycleLogs() above,
      // which already degrades the same way on a remote read failure.
      debugPrint('[CycleTracking] saveCycleLog remote sync failed: $error');
    }
  }

  @override
  Future<void> upsertCycleLog(CycleLog log) async {
    final client = _client;
    if (client == null) {
      return;
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      return;
    }

    try {
      final payload = {...log.toJson(), 'user_id': sessionUser.id};

      await client.from('cycle_entries').upsert(payload, onConflict: 'id');
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }

  @override
  Future<void> deleteCycleLog(String id) async {
    await _localDataSource.delete(id);
    final client = _client;
    if (client == null) {
      return;
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      return;
    }

    try {
      await client
          .from('cycle_entries')
          .delete()
          .eq('id', id)
          .eq('user_id', sessionUser.id);
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }

  @override
  Future<List<CycleLog>> syncPendingLogs() async {
    final client = _client;
    if (client == null) {
      return const [];
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      return const [];
    }

    try {
      final pendingLocal = await _localDataSource.loadLogs();
      final remote = await client
          .from('cycle_entries')
          .select()
          .eq('user_id', sessionUser.id)
          .eq('sync_status', 'pending');

      final remoteLogs = (remote as List<dynamic>)
          .map((item) => CycleLog.fromJson(item as Map<String, dynamic>))
          .toList();

      final merged = <String, CycleLog>{};
      for (final item in [...pendingLocal, ...remoteLogs]) {
        merged[item.id] = item;
      }
      return merged.values.toList();
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }
}
