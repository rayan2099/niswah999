import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/pregnancy_milestone.dart';
import '../../domain/repositories/pregnancy_tracking_repository.dart';
import '../datasources/local_pregnancy_tracking_data_source.dart';

/// W0-002: previously queried a table (`pregnancy_milestones`) that did not
/// exist live at all. Now backed by the real `pregnancy_milestones` table
/// (supabase/migrations/20260907090000_pregnancy_milestones.sql) — a
/// direct per-user child table, matching `CycleTrackingRepositoryImpl`'s
/// established local-authoritative-with-sync pattern (this is a personal,
/// journal-style entry, not a high-stakes record like `pregnancy_profile`,
/// so the same offline-friendly, eventually-consistent design applies).
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
    } on PostgrestException catch (error, stack) {
      // Local save is authoritative for the UI — a remote read failure
      // must never make an already-saved local entry disappear (same
      // reasoning as CycleTrackingRepositoryImpl.getCycleLogs).
      AppErrorReporter.report(
        error,
        stack,
        context: 'PregnancyTrackingRepositoryImpl.getMilestonesForUser',
        feature: 'pregnancy_tracking',
      );
      return userEntries;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'PregnancyTrackingRepositoryImpl.getMilestonesForUser',
        feature: 'pregnancy_tracking',
      );
      return userEntries;
    }
  }

  @override
  Future<PregnancySyncStatus> saveMilestone(PregnancyMilestone milestone) async {
    // Saved locally as `pending` first — exactly like CycleLog, this is
    // what makes it eligible for a later retry via syncPendingMilestones()
    // if the remote attempt below fails retryably.
    await _localDataSource.upsert(milestone);
    try {
      await _upsertRemote(milestone);
      await _localDataSource.upsert(
        milestone.copyWith(syncStatus: PregnancySyncStatus.synced),
      );
      return PregnancySyncStatus.synced;
    } on NetworkFailure catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'PregnancyTrackingRepositoryImpl.saveMilestone',
        feature: 'pregnancy_tracking',
        recordId: milestone.id,
      );
      if (!error.retryable) {
        await _localDataSource.upsert(
          milestone.copyWith(syncStatus: PregnancySyncStatus.failed),
        );
        return PregnancySyncStatus.failed;
      }
      return PregnancySyncStatus.pending;
    }
  }

  Future<void> _upsertRemote(PregnancyMilestone milestone) async {
    final client = _supabaseClient;
    if (client == null) return;

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) return;

    try {
      final payload = {
        ...milestone.toRemoteJson(),
        'user_id': sessionUser.id,
        'sync_status': 'synced',
      };
      await client.from(_tableName).upsert(payload, onConflict: 'id');
    } on PostgrestException catch (error, stack) {
      throw mapRepositoryError(
            error,
            stack,
            context: 'PregnancyTrackingRepositoryImpl._upsertRemote',
            userMessage: 'Could not save your pregnancy update to your account.',
          )
          as NetworkFailure;
    }
  }

  @override
  Future<void> deleteMilestone(String id) async {
    await _localDataSource.delete(id);

    final client = _supabaseClient;
    if (client == null) return;

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) return;

    try {
      await client
          .from(_tableName)
          .delete()
          .eq('id', id)
          .eq('user_id', sessionUser.id);
    } on PostgrestException catch (error, stack) {
      // Deletion is best-effort against the remote (matches
      // CycleTrackingRepositoryImpl.deleteCycleLog's contract) — the local
      // deletion above already happened and is what the UI reflects.
      AppErrorReporter.report(
        error,
        stack,
        context: 'PregnancyTrackingRepositoryImpl.deleteMilestone',
        feature: 'pregnancy_tracking',
        recordId: id,
      );
    }
  }

  @override
  Future<PregnancyMilestonePendingSyncResult> syncPendingMilestones() async {
    final client = _supabaseClient;
    final sessionUser = client?.auth.currentUser;
    if (client == null || sessionUser == null) {
      return const PregnancyMilestonePendingSyncResult(
        synced: 0,
        stillPending: 0,
        permanentlyFailed: 0,
      );
    }

    final localEntries = await _localDataSource.loadMilestones();
    final toRetry = localEntries
        .where((item) => item.syncStatus == PregnancySyncStatus.pending)
        .toList();

    var synced = 0;
    var stillPending = 0;
    var permanentlyFailed = 0;

    // Sequential, not parallel — same bounded-retry reasoning as
    // CycleTrackingRepositoryImpl.syncPendingLogs.
    for (final milestone in toRetry) {
      try {
        await _upsertRemote(milestone);
        await _localDataSource.upsert(
          milestone.copyWith(syncStatus: PregnancySyncStatus.synced),
        );
        synced++;
      } on NetworkFailure catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'PregnancyTrackingRepositoryImpl.syncPendingMilestones',
          feature: 'pregnancy_tracking',
          recordId: milestone.id,
        );
        if (error.retryable) {
          stillPending++;
        } else {
          await _localDataSource.upsert(
            milestone.copyWith(syncStatus: PregnancySyncStatus.failed),
          );
          permanentlyFailed++;
        }
      }
    }

    return PregnancyMilestonePendingSyncResult(
      synced: synced,
      stillPending: stillPending,
      permanentlyFailed: permanentlyFailed,
    );
  }
}
