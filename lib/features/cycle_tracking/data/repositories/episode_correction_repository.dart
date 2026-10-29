import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/bleeding_episode.dart';
import '../../domain/entities/load_result.dart';
import 'bleeding_episode_repository_impl.dart';
import 'cycle_entries_projection.dart';
import 'cycle_tracking_repository_impl.dart';

/// What happened to an episode-level change (move the start or end, undo
/// an end, remove or restore a period). Every outcome other than [saved]
/// means nothing changed on the server.
enum EpisodeEditStatus {
  /// Saved on the server; the episode now reflects it.
  saved,

  /// The change would take out entries she recorded (bleeding before a
  /// later start, after an earlier end). [EpisodeEditResult.conflictingCount]
  /// says how many; repeat with `retractConflicting: true` once she agreed.
  needsConfirmation,

  /// Another device changed this period after it was loaded here.
  changedElsewhere,

  /// The server refused the change for a reason re-sending cannot fix
  /// (overlap with another period, a future date, ...).
  rejected,

  /// No answer from the server. Nothing is queued: these changes rewrite
  /// a period's shape and are only applied while connected, so she keeps
  /// her selection and can try again.
  offline,
}

class EpisodeEditResult {
  const EpisodeEditResult(
    this.status, {
    this.revisionId,
    this.conflictingCount,
    this.serverMessage,
  });

  final EpisodeEditStatus status;
  final String? revisionId;
  final int? conflictingCount;

  /// The server's own message for [EpisodeEditStatus.rejected]; for
  /// diagnostics and choosing a message, never shown raw to her.
  final String? serverMessage;

  bool get saved => status == EpisodeEditStatus.saved;
}

/// A period she removed, as kept in `bleeding_episodes_archive` so the
/// removal can be undone.
class RemovedEpisode {
  const RemovedEpisode({required this.episode, required this.removedAt});

  final BleedingEpisode episode;
  final DateTime removedAt;
}

/// Client for the episode correction RPCs added by
/// `supabase/migrations/20261029100000_bleeding_episode_corrections.sql`
/// (cases PT-027, PT-051..PT-057, PT-060, PT-148).
///
/// Each call takes a client operation id generated once per user action
/// and reused on retry (the RPC returns the original result for a repeat),
/// and the episode's [BleedingEpisode.revisionToken] so a change made on
/// another device in between is refused instead of overwritten.
///
/// After a saved change the `cycle_entries` mirror on this device is
/// brought in line ([_resyncMirror]); the server already deleted the
/// mirrors of everything it took out.
class EpisodeCorrectionRepository {
  EpisodeCorrectionRepository({
    SupabaseClient? client,
    BleedingEpisodeRepositoryImpl? episodes,
    CycleTrackingRepositoryImpl? cycleLogs,
    CycleEntriesProjection? projection,
  }) : _client = client ?? NiswahSupabase.clientOrNull,
       _episodesOverride = episodes,
       _cycleLogsOverride = cycleLogs,
       _projectionOverride = projection;

  final SupabaseClient? _client;
  final BleedingEpisodeRepositoryImpl? _episodesOverride;
  final CycleTrackingRepositoryImpl? _cycleLogsOverride;
  final CycleEntriesProjection? _projectionOverride;

  BleedingEpisodeRepositoryImpl get _episodes =>
      _episodesOverride ?? BleedingEpisodeRepositoryImpl(client: _client);
  CycleTrackingRepositoryImpl get _cycleLogs =>
      _cycleLogsOverride ?? CycleTrackingRepositoryImpl(client: _client);
  CycleEntriesProjection get _projection =>
      _projectionOverride ?? CycleEntriesProjection(repository: _cycleLogs);

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<EpisodeEditResult> correctStart({
    required String clientOperationId,
    required BleedingEpisode episode,
    required DateTime newStartDate,
    required ObservationFlow flow,
    required String? timezone,
    required int utcOffsetMinutes,
    bool retractConflicting = false,
  }) => _run(
    'correct_episode_start',
    episode: episode,
    params: {
      'p_client_operation_id': clientOperationId,
      'p_episode_id': episode.id,
      'p_new_start_date': _dateOnly(newStartDate),
      'p_flow': flow.value,
      'p_timezone': timezone,
      'p_utc_offset_minutes': utcOffsetMinutes,
      'p_expected_updated_at': episode.revisionToken,
      'p_retract_conflicting': retractConflicting,
    },
  );

  Future<EpisodeEditResult> correctEnd({
    required String clientOperationId,
    required BleedingEpisode episode,
    required DateTime newEndDate,
    required String? timezone,
    required int utcOffsetMinutes,
    bool retractConflicting = false,
  }) => _run(
    'correct_episode_end',
    episode: episode,
    params: {
      'p_client_operation_id': clientOperationId,
      'p_episode_id': episode.id,
      'p_new_end_date': _dateOnly(newEndDate),
      'p_timezone': timezone,
      'p_utc_offset_minutes': utcOffsetMinutes,
      'p_expected_updated_at': episode.revisionToken,
      'p_retract_conflicting': retractConflicting,
    },
  );

  /// Undo an end. [revisionToken] null skips the other-device check — used
  /// only by the immediate "Undo" right after she ended it on this device.
  Future<EpisodeEditResult> reopen({
    required String clientOperationId,
    required String episodeId,
    required String? revisionToken,
  }) => _run(
    'reopen_episode',
    episodeId: episodeId,
    params: {
      'p_client_operation_id': clientOperationId,
      'p_episode_id': episodeId,
      'p_expected_updated_at': revisionToken,
    },
  );

  Future<EpisodeEditResult> remove({
    required String clientOperationId,
    required BleedingEpisode episode,
  }) => _run(
    'remove_episode',
    episode: episode,
    params: {
      'p_client_operation_id': clientOperationId,
      'p_episode_id': episode.id,
      'p_expected_updated_at': episode.revisionToken,
    },
  );

  Future<EpisodeEditResult> restore({
    required String clientOperationId,
    required String episodeId,
  }) => _run(
    'restore_episode',
    episodeId: episodeId,
    params: {
      'p_client_operation_id': clientOperationId,
      'p_episode_id': episodeId,
    },
  );

  /// Periods she removed, most recent first, for "Undo".
  Future<LoadResult<List<RemovedEpisode>>> getRemovedEpisodes(
    String userId,
  ) async {
    final client = _client;
    if (client == null) {
      return const LoadUnavailable(LoadErrorCategory.unknown, 'No session');
    }
    try {
      final rows = await client
          .from('bleeding_episodes_archive')
          .select()
          .eq('user_id', userId)
          .order('archived_at', ascending: false);
      final removed = <RemovedEpisode>[];
      var quarantined = 0;
      for (final raw in rows as List<dynamic>) {
        final row = raw as Map<String, dynamic>;
        final removedAt = DateTime.tryParse(
          row['archived_at'] as String? ?? '',
        );
        try {
          if (removedAt == null) {
            throw BleedingEpisodeParseException(
              'archived_at',
              row['archived_at'],
            );
          }
          removed.add(
            RemovedEpisode(
              episode: BleedingEpisode.fromJson(row),
              removedAt: removedAt,
            ),
          );
        } on BleedingEpisodeParseException catch (error, stack) {
          quarantined++;
          AppErrorReporter.report(
            error,
            stack,
            context: 'EpisodeCorrectionRepository.getRemovedEpisodes',
            feature: 'cycle_tracking',
            recordId: row['id'] as String?,
          );
        }
      }
      return quarantined > 0
          ? LoadDegraded(removed, quarantined)
          : LoadSuccess(removed);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'EpisodeCorrectionRepository.getRemovedEpisodes',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return LoadUnavailable(LoadErrorCategory.backend, error.message);
    } catch (error) {
      if (!BleedingEpisodeRepositoryImpl.isTransportFailure(error)) rethrow;
      return const LoadUnavailable(LoadErrorCategory.network, 'Offline');
    }
  }

  Future<EpisodeEditResult> _run(
    String rpc, {
    BleedingEpisode? episode,
    String? episodeId,
    required Map<String, dynamic> params,
  }) async {
    final client = _client;
    final id = episode?.id ?? episodeId;
    if (client == null || id == null) {
      return const EpisodeEditResult(EpisodeEditStatus.offline);
    }

    // What this device mirrors for the episode before the change, so the
    // mirror can be brought in line afterwards.
    final Set<String> beforeIds;
    try {
      final before = await _episodes.getObservationsForEpisode(id);
      beforeIds = _effectiveIds(
        before.dataOrNull ?? const <BleedingObservation>[],
      );
    } catch (error) {
      if (!BleedingEpisodeRepositoryImpl.isTransportFailure(error)) rethrow;
      return const EpisodeEditResult(EpisodeEditStatus.offline);
    }

    final String revisionId;
    try {
      final response = await client.rpc(rpc, params: params);
      final row = (response as List).single as Map<String, dynamic>;
      revisionId = row['revision_id'] as String;
    } on PostgrestException catch (error, stack) {
      return _classify(error, stack, rpc, id);
    } catch (error, stack) {
      if (!BleedingEpisodeRepositoryImpl.isTransportFailure(error)) rethrow;
      AppErrorReporter.report(
        error,
        stack,
        context: 'EpisodeCorrectionRepository.$rpc',
        feature: 'cycle_tracking',
        recordId: id,
      );
      return const EpisodeEditResult(EpisodeEditStatus.offline);
    }

    try {
      await _resyncMirror(id, beforeIds);
    } catch (error, stack) {
      // The server change is saved; a stale local mirror is corrected by
      // the next full read. Never report the save itself as failed.
      AppErrorReporter.report(
        error,
        stack,
        context: 'EpisodeCorrectionRepository._resyncMirror',
        feature: 'cycle_tracking',
        recordId: id,
      );
    }
    return EpisodeEditResult(EpisodeEditStatus.saved, revisionId: revisionId);
  }

  EpisodeEditResult _classify(
    PostgrestException error,
    StackTrace stack,
    String rpc,
    String episodeId,
  ) {
    AppErrorReporter.report(
      error,
      stack,
      context: 'EpisodeCorrectionRepository.$rpc',
      feature: 'cycle_tracking',
      recordId: episodeId,
    );
    switch (error.code) {
      case 'NW422':
        return EpisodeEditResult(
          EpisodeEditStatus.needsConfirmation,
          conflictingCount:
              _leadingCount(error.details) ?? _leadingCount(error.message),
        );
      case 'NW409':
        return const EpisodeEditResult(EpisodeEditStatus.changedElsewhere);
    }
    if (BleedingEpisodeRepositoryImpl.isPermanentRejectionCode(error.code) ||
        error.code == 'NW410') {
      return EpisodeEditResult(
        EpisodeEditStatus.rejected,
        serverMessage: error.message,
      );
    }
    return const EpisodeEditResult(EpisodeEditStatus.offline);
  }

  static int? _leadingCount(Object? text) {
    final match = RegExp(r'^\s*(\d+)').firstMatch('${text ?? ''}');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Ids of the observations no correction supersedes.
  static Set<String> _effectiveIds(List<BleedingObservation> observations) {
    final supersededIds = {
      for (final o in observations)
        if (o.supersedesId != null) o.supersedesId!,
    };
    return {
      for (final o in observations)
        if (o.id != null && !supersededIds.contains(o.id)) o.id!,
    };
  }

  /// Deletes this device's mirror of every observation the change took
  /// out or superseded, and mirrors every current observation that is new.
  Future<void> _resyncMirror(String episodeId, Set<String> beforeIds) async {
    final after = await _episodes.getObservationsForEpisode(episodeId);
    final observations = after.dataOrNull;
    if (observations == null) return;
    final effectiveIds = _effectiveIds(observations);
    final effective = [
      for (final o in observations)
        if (effectiveIds.contains(o.id)) o,
    ];

    for (final id in beforeIds.difference(effectiveIds)) {
      await _cycleLogs.deleteCycleLog(id);
    }
    for (final observation in effective) {
      if (!beforeIds.contains(observation.id)) {
        await _projection.project(observation);
      }
    }
  }
}
