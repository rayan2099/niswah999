import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/storage/secure_local_store.dart';
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
    final client = _client;
    final session = client?.auth.currentSession;
    final owner = session?.user.id;
    void requireOriginalSession() {
      if (client != null && client.auth.currentSession?.user.id != owner) {
        throw StateError('Account changed during cycle history read.');
      }
    }

    final localLogs = await _localDataSource.loadLogs();
    requireOriginalSession();
    if (client == null || session == null) {
      return localLogs;
    }

    try {
      var query = client
          .from('cycle_entries')
          .select()
          .eq('user_id', session.user.id);

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

      final response = await query
          .order('date', ascending: false)
          .limit(limit)
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      requireOriginalSession();
      final remote = _parseCycleEntries(response as List<dynamic>);

      final merged = _mergeLocalAndRemote(localLogs, remote);
      final ordered = merged.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return ordered;
    } on PostgrestException catch (error, stack) {
      requireOriginalSession();
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
      requireOriginalSession();
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
      try {
        return CycleLog.fromJson(response);
      } on CycleLogParseException catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'CycleTrackingRepositoryImpl.getCycleLogById',
          feature: 'cycle_tracking',
          recordId: id,
        );
        return await _localDataSource.getById(id);
      }
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }

  /// Logging/sync hardening (proposed): a remote row replaces its local
  /// copy only when that local copy is already synced. A local edit that is
  /// still `pending` (or `failed`) is newer than anything the server holds
  /// for that id — it is what she last entered — so it keeps precedence
  /// until it actually syncs.
  static Map<String, CycleLog> _mergeLocalAndRemote(
    List<CycleLog> localLogs,
    List<CycleLog> remote,
  ) {
    final merged = <String, CycleLog>{
      for (final entry in localLogs) entry.id: entry,
    };
    for (final entry in remote) {
      final local = merged[entry.id];
      if (local != null && local.syncStatus != SyncStatus.synced) continue;
      merged[entry.id] = entry;
    }
    return merged;
  }

  /// Parses remote `cycle_entries` rows one at a time so a single record
  /// with unparseable required health data (`date`/`flow`) is quarantined
  /// — reported and skipped — rather than discarding every other, valid
  /// row in the same response (see [CycleLogParseException]).
  List<CycleLog> _parseCycleEntries(List<dynamic> rows) {
    final parsed = <CycleLog>[];
    for (final row in rows) {
      try {
        parsed.add(CycleLog.fromJson(row as Map<String, dynamic>));
      } on CycleLogParseException catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'CycleTrackingRepositoryImpl._parseCycleEntries',
          feature: 'cycle_tracking',
          recordId: (row as Map<String, dynamic>)['id'] as String?,
        );
      }
    }
    return parsed;
  }

  @override
  Future<SyncStatus> saveCycleLog(CycleLog log) async {
    // Reject a stale form/async callback before it enters another account's
    // local cache. The remote guard below runs only after the local save.
    final localOwner = SecureLocalStore.currentUserId();
    final sessionOwner = _client?.auth.currentSession?.user.id;
    if ((SecureLocalStore.hasSession && log.userId != localOwner) ||
        (sessionOwner != null && log.userId != sessionOwner)) {
      throw const NetworkFailure(
        'Sign in to the original account before saving this record.',
      );
    }
    // Saved locally as `pending` first (formData.toCycleLog defaults to
    // SyncStatus.pending) — if the remote attempt below fails retryably,
    // this pending marker is exactly what makes it eligible for automatic
    // retry via syncPendingLogs(); see main.dart's app-start/app-resume
    // wiring, which is what makes retry actually automatic rather than a
    // dead-code promise.
    await _localDataSource.upsert(log);
    try {
      await upsertCycleLog(log);
      // Not a blind upsert of `log`: a newer save of the same row that
      // finished first must not be overwritten by this older one.
      await _localDataSource.setSyncStatusIfUnchanged(
        log,
        SyncStatus.synced,
        userId: localOwner,
      );
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
        await _localDataSource.setSyncStatusIfUnchanged(
          log,
          SyncStatus.failed,
          userId: localOwner,
        );
        return SyncStatus.failed;
      }
      return SyncStatus.pending;
    }
  }

  @override
  Future<void> upsertCycleLog(CycleLog log) async {
    final client = _client;
    if (client == null) {
      throw const NetworkFailure('Account sync is unavailable.');
    }

    // Capture both identity and token together before constructing the
    // request. Never relabel another account's record on an account switch.
    final session = client.auth.currentSession;
    if (session == null || session.user.id != log.userId) {
      throw const NetworkFailure(
        'Sign in to the original account to sync this record.',
      );
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
        'user_id': log.userId,
        'sync_status': 'synced',
      };

      await client
          .from('cycle_entries')
          .upsert(payload, onConflict: 'id')
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
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

  Future<CyclePendingSyncResult>? _syncInFlight;

  /// App start and app resume both trigger this (often back to back on a
  /// cold start), and every pass re-uploads every pending row. A call made
  /// while a pass is still running joins that pass instead of uploading the
  /// same rows a second time.
  @override
  Future<CyclePendingSyncResult> syncPendingLogs() {
    final running = _syncInFlight;
    if (running != null) return running;
    final pass = _syncPendingLogsPass();
    _syncInFlight = pass;
    pass.whenComplete(() {
      if (identical(_syncInFlight, pass)) _syncInFlight = null;
    }).ignore();
    return pass;
  }

  Future<CyclePendingSyncResult> _syncPendingLogsPass() async {
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

    final syncOwner = SecureLocalStore.currentUserId();
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
        // `log` is this pass's snapshot: an edit she saved while the
        // upload was in flight stays pending (it is newer than what the
        // server now holds) instead of being replaced by the snapshot.
        await _localDataSource.setSyncStatusIfUnchanged(
          log,
          SyncStatus.synced,
          userId: syncOwner,
        );
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
          await _localDataSource.setSyncStatusIfUnchanged(
            log,
            SyncStatus.failed,
            userId: syncOwner,
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
    final client = _client;
    final session = client?.auth.currentSession;
    final localOwner = SecureLocalStore.currentUserId();
    bool current() =>
        SecureLocalStore.currentUserId() == localOwner &&
        client?.auth.currentSession?.user.id == session?.user.id;
    const rejected = ReportSourceResult<List<CycleLog>>(
      status: ReportSourceStatus.failed,
      data: [],
    );

    final localLogs = await _localDataSource.loadLogs();
    if (!current()) return rejected;
    if (client == null) {
      return ReportSourceResult(
        status: localLogs.isEmpty
            ? ReportSourceStatus.empty
            : ReportSourceStatus.available,
        data: localLogs,
      );
    }

    if (session == null) {
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
          .eq('user_id', session.user.id)
          .order('date', ascending: false)
          .limit(limit)
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (!current()) return rejected;
      final remote = _parseCycleEntries(response as List<dynamic>);

      final merged = _mergeLocalAndRemote(localLogs, remote);
      final ordered = merged.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      return ReportSourceResult(
        status: ordered.isEmpty
            ? ReportSourceStatus.empty
            : ReportSourceStatus.available,
        data: ordered,
      );
    } catch (error, stack) {
      // A stale account's cache is not a safe fallback for the next account.
      if (!current()) return rejected;
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
