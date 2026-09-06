import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../doctor_report/domain/entities/report_source_status.dart';
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
    } on PostgrestException catch (error, stack) {
      // Local save is authoritative for the UI (see saveCycleLog below) —
      // a remote read failure here must never make an already-saved local
      // log disappear from the caller. This used to rethrow as a
      // NetworkFailure instead, which meant CycleTrackingViewModel.loadLogs
      // caught it *before* ever assigning `logs`, silently wiping out
      // whatever had just been saved locally moments earlier. Still
      // reported (not silently discarded) so a real outage is observable.
      AppErrorReporter.report(
        error,
        stack,
        context: 'CycleTrackingRepositoryImpl.getCycleLogs',
        feature: 'cycle_tracking',
      );
      return localLogs;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'CycleTrackingRepositoryImpl.getCycleLogs',
        feature: 'cycle_tracking',
      );
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
  Future<SyncStatus> saveCycleLog(CycleLog log) async {
    // Saved locally as `pending` first (formData.toCycleLog defaults to
    // SyncStatus.pending) — if the remote attempt below fails retryably,
    // this pending marker is exactly what makes it eligible for automatic
    // retry via syncPendingLogs(); see main.dart's app-start/app-resume
    // wiring, which is what makes retry actually automatic rather than a
    // dead-code promise.
    await _localDataSource.upsert(log);
    try {
      await upsertCycleLog(log);
      await _localDataSource.upsert(log.copyWith(syncStatus: SyncStatus.synced));
      return SyncStatus.synced;
    } on NetworkFailure catch (error, stack) {
      // Local save is authoritative for the UI; remote sync is eventually-
      // consistent for retryable failures (see syncPendingLogs()). The
      // failure is never allowed to hide an already-successful local save
      // from the caller — see getCycleLogs() above, which degrades the
      // same way on a remote read failure — but it IS now reported (not
      // silently discarded) and surfaced back to the caller via the
      // return value, so the UI can show an accurate, non-blocking
      // indication instead of the failure vanishing with zero trace
      // (DI-002/PJ-002).
      AppErrorReporter.report(
        error,
        stack,
        context: 'CycleTrackingRepositoryImpl.saveCycleLog',
        feature: 'cycle_tracking',
        recordId: log.id,
      );
      // Non-retryable failures (a policy/validation rejection that will
      // fail identically every time) are marked `failed`, not left
      // `pending` — automatic retry must not hammer a request that can
      // never succeed ("do not retry non-retryable errors blindly").
      if (!error.retryable) {
        await _localDataSource.upsert(log.copyWith(syncStatus: SyncStatus.failed));
        return SyncStatus.failed;
      }
      return SyncStatus.pending;
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
      // Reaching this point without throwing IS the definition of "synced"
      // — overridden unconditionally rather than passed through from
      // log.toJson()'s local default (CycleLog() defaults to
      // SyncStatus.pending, which — before this fix — was uploaded
      // verbatim and then never updated, leaving every successfully
      // synced row permanently marked 'pending' in the database).
      final payload = {
        ...log.toJson(),
        'user_id': sessionUser.id,
        'sync_status': 'synced',
      };

      await client.from('cycle_entries').upsert(payload, onConflict: 'id');
    } on PostgrestException catch (error, stack) {
      throw mapRepositoryError(
        error,
        stack,
        context: 'CycleTrackingRepositoryImpl.upsertCycleLog',
        userMessage: 'Could not save your cycle log to your account.',
      ) as NetworkFailure;
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
  Future<CyclePendingSyncResult> syncPendingLogs() async {
    final client = _client;
    if (client == null) {
      return const CyclePendingSyncResult(
        synced: 0,
        stillPending: 0,
        permanentlyFailed: 0,
      );
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      return const CyclePendingSyncResult(
        synced: 0,
        stillPending: 0,
        permanentlyFailed: 0,
      );
    }

    final localLogs = await _localDataSource.loadLogs();
    final toRetry = localLogs
        .where((log) => log.syncStatus == SyncStatus.pending)
        .toList();

    var synced = 0;
    var stillPending = 0;
    var permanentlyFailed = 0;

    // Sequential, not parallel — a burst of simultaneous requests on
    // reconnect is exactly the kind of load a bounded retry should avoid
    // creating (and matches the "no infinite/unbounded loop" requirement
    // in spirit: one bounded pass per trigger, not an unbounded fan-out).
    for (final log in toRetry) {
      try {
        await upsertCycleLog(log);
        await _localDataSource.upsert(log.copyWith(syncStatus: SyncStatus.synced));
        synced++;
      } on NetworkFailure catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'CycleTrackingRepositoryImpl.syncPendingLogs',
          feature: 'cycle_tracking',
          recordId: log.id,
        );
        if (error.retryable) {
          stillPending++; // left as `pending` — eligible for the next trigger
        } else {
          await _localDataSource.upsert(
            log.copyWith(syncStatus: SyncStatus.failed),
          );
          permanentlyFailed++;
        }
      }
    }

    return CyclePendingSyncResult(
      synced: synced,
      stillPending: stillPending,
      permanentlyFailed: permanentlyFailed,
    );
  }

  /// A report-consuming variant of [getCycleLogs] that surfaces whether
  /// the returned logs are the full, merged local+remote picture, or a
  /// local-only fallback because the remote read failed. [getCycleLogs]
  /// itself deliberately swallows a remote failure into a silent
  /// local-only return (correct for the main cycle-tracking UI — a remote
  /// read hiccup must never make an already-saved local entry disappear),
  /// but a downstream report consumer needs to know when that happened
  /// rather than silently presenting a possibly-incomplete history as
  /// definitive (PJ-006 — Doctor's Report Data Completeness +
  /// Truthfulness wave, 2026-09-06). Does not change [getCycleLogs]'s own
  /// behavior or contract at all.
  Future<ReportSourceResult<List<CycleLog>>> getCycleLogsForReport({
    int limit = 1000,
  }) async {
    final localLogs = await _localDataSource.loadLogs();
    final client = _client;
    if (client == null) {
      return ReportSourceResult(
        status: localLogs.isEmpty
            ? ReportSourceStatus.empty
            : ReportSourceStatus.available,
        data: localLogs,
      );
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      return ReportSourceResult(
        status: localLogs.isEmpty
            ? ReportSourceStatus.empty
            : ReportSourceStatus.available,
        data: localLogs,
      );
    }

    try {
      final response = await client
          .from('cycle_entries')
          .select()
          .eq('user_id', sessionUser.id)
          .order('date', ascending: false)
          .limit(limit);
      final remote = (response as List<dynamic>)
          .map((item) => CycleLog.fromJson(item as Map<String, dynamic>))
          .toList();

      final merged = <String, CycleLog>{};
      for (final entry in [...localLogs, ...remote]) {
        merged[entry.id] = entry;
      }
      final ordered = merged.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      return ReportSourceResult(
        status: ordered.isEmpty
            ? ReportSourceStatus.empty
            : ReportSourceStatus.available,
        data: ordered,
      );
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'CycleTrackingRepositoryImpl.getCycleLogsForReport',
        feature: 'doctor_report',
      );
      return ReportSourceResult(
        status: ReportSourceStatus.failed,
        data: localLogs,
      );
    }
  }
}
