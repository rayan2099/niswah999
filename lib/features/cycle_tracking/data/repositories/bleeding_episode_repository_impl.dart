import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/bleeding_episode.dart';

/// Thrown by [BleedingEpisodeRepositoryImpl.startEpisode] specifically
/// when the user already has an active episode — the database's
/// `bleeding_episodes_one_active_per_user` constraint is what actually
/// prevents the duplicate (Commit A); this exception just gives the
/// caller (Commit D's "Start bleeding" UI) a typed way to tell "you're
/// already tracking one" apart from a genuine failure, so a double-tap or
/// retry never surfaces as a scary error.
class ActiveEpisodeAlreadyExistsException implements Exception {
  const ActiveEpisodeAlreadyExistsException();

  @override
  String toString() => 'ActiveEpisodeAlreadyExistsException';
}

/// Writes/reads the first-class `bleeding_episodes` / `bleeding_observations`
/// / `cycle_baselines` model (menstrual-data-integrity charter, Commit A/B
/// schema). Deliberately server-only for this initial slice — every
/// caller today (onboarding, the dashboard's Start/End Bleeding actions)
/// is only ever reached already-authenticated, so a real session always
/// exists; a local-first/offline path mirroring
/// [CycleTrackingRepositoryImpl] is follow-up work once a consumer needs
/// to read this data offline.
class BleedingEpisodeRepositoryImpl {
  BleedingEpisodeRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  /// Atomically creates an ACTIVE episode + its first observation via the
  /// `start_bleeding_episode` RPC (Commit B) — never two separate writes
  /// that could partially fail. Throws
  /// [ActiveEpisodeAlreadyExistsException] if the user already has an
  /// active episode (the DB's own one-active-episode constraint is the
  /// real enforcement; this only classifies that specific, expected
  /// conflict for the caller). Any other failure is reported and
  /// rethrown — unlike onboarding's best-effort writes, a live "Start
  /// bleeding" tap must tell the user honestly if it did not save
  /// (Section 7: no false success).
  Future<({BleedingEpisode episode, BleedingObservation observation})>
  startEpisode({
    required DateTime startDate,
    required ObservationPrecision startPrecision,
    DateTime? startTime,
    required ObservationFlow flow,
    DateTime? observedTime,
    required ObservationPrecision observationPrecision,
    required String timezone,
    List<String>? symptoms,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'No Supabase session — cannot start a bleeding episode.',
      );
    }

    try {
      final response = await client.rpc(
        'start_bleeding_episode',
        params: {
          'p_start_date': _dateOnly(startDate),
          'p_start_precision': startPrecision.value,
          'p_start_time': startTime?.toIso8601String(),
          'p_flow': flow.value,
          'p_observed_time': observedTime?.toIso8601String(),
          'p_precision': observationPrecision.value,
          'p_timezone': timezone,
          'p_symptoms': symptoms,
          'p_notes': notes,
        },
      );

      final row = (response as List).single as Map<String, dynamic>;
      final episodeId = row['episode_id'] as String;
      final observationId = row['observation_id'] as String;

      return (
        episode: BleedingEpisode(
          id: episodeId,
          userId: client.auth.currentUser!.id,
          status: EpisodeStatus.active,
          startDate: startDate,
          startPrecision: startPrecision,
          startSource: ObservationSource.userObserved,
        ),
        observation: BleedingObservation(
          id: observationId,
          userId: client.auth.currentUser!.id,
          episodeId: episodeId,
          observedDate: startDate,
          observedTime: observedTime,
          precision: observationPrecision,
          flow: flow,
          source: ObservationSource.userObserved,
          timezone: timezone,
          symptoms: symptoms,
          notes: notes,
        ),
      );
    } on PostgrestException catch (error, stack) {
      if (error.code == '23505') {
        throw const ActiveEpisodeAlreadyExistsException();
      }
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.startEpisode',
        feature: 'cycle_tracking',
      );
      rethrow;
    }
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Ends an active episode with a real, user-reported end date — never
  /// inferred from elapsed time (Section 3 of the episode-lifecycle
  /// contract). A plain single-table UPDATE is already atomic; no RPC is
  /// needed the way starting an episode needed one.
  Future<BleedingEpisode?> endEpisode({
    required String episodeId,
    required DateTime endDate,
    required ObservationPrecision endPrecision,
    required ObservationSource endSource,
  }) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('bleeding_episodes')
          .update({
            'status': 'ended',
            'end_date': _dateOnly(endDate),
            'end_precision': endPrecision.value,
            'end_source': endSource.value,
          })
          .eq('id', episodeId)
          .select()
          .single();
      return BleedingEpisode.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.endEpisode',
        feature: 'cycle_tracking',
        recordId: episodeId,
      );
      return null;
    }
  }

  /// Marks an active episode's continuation as uncertain — Section 15's
  /// "I'm not sure" daily check-in answer. Never closes the episode and
  /// never fabricates a positive bleeding observation.
  Future<BleedingEpisode?> markEpisodeUncertain(String episodeId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('bleeding_episodes')
          .update({'status': 'uncertain'})
          .eq('id', episodeId)
          .select()
          .single();
      return BleedingEpisode.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.markEpisodeUncertain',
        feature: 'cycle_tracking',
        recordId: episodeId,
      );
      return null;
    }
  }

  /// Adds one immutable observation to an existing episode — a daily
  /// check-in response, or a correction when [BleedingObservation.supersedesId]
  /// is set. Never an in-place update: the database itself refuses
  /// UPDATE/DELETE on this table for the owning user (Commit A's RLS
  /// fix), so a correction MUST come through here as a new row.
  Future<BleedingObservation?> addObservation(
    BleedingObservation observation,
  ) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('bleeding_observations')
          .insert(observation.toInsertJson())
          .select()
          .single();
      return BleedingObservation.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.addObservation',
        feature: 'cycle_tracking',
        recordId: observation.episodeId,
      );
      return null;
    } on BleedingEpisodeParseException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.addObservation',
        feature: 'cycle_tracking',
        recordId: observation.episodeId,
      );
      return null;
    }
  }

  /// Every observation for an episode, oldest first — the raw evidence
  /// behind a day's summary (Section 39: same-day multiple observations
  /// must all remain visible, never collapsed into one fabricated value).
  Future<List<BleedingObservation>> getObservationsForEpisode(
    String episodeId,
  ) async {
    final client = _client;
    if (client == null) return const [];

    try {
      final response = await client
          .from('bleeding_observations')
          .select()
          .eq('episode_id', episodeId)
          .order('observed_date')
          .order('reported_at');
      final rows = response as List<dynamic>;
      final observations = <BleedingObservation>[];
      for (final row in rows) {
        try {
          observations.add(
            BleedingObservation.fromJson(row as Map<String, dynamic>),
          );
        } on BleedingEpisodeParseException catch (error, stack) {
          AppErrorReporter.report(
            error,
            stack,
            context: 'BleedingEpisodeRepositoryImpl.getObservationsForEpisode',
            feature: 'cycle_tracking',
            recordId: (row as Map<String, dynamic>)['id'] as String?,
          );
        }
      }
      return observations;
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getObservationsForEpisode',
        feature: 'cycle_tracking',
        recordId: episodeId,
      );
      return const [];
    }
  }

  /// Best-effort: returns null (reported, not thrown) on any failure so a
  /// caller like onboarding completion is never blocked by a network
  /// hiccup — matching the existing best-effort pattern already used for
  /// `AuthRepositoryImpl.markOnboardingCompleted`.
  Future<BleedingEpisode?> createEpisode(BleedingEpisode episode) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('bleeding_episodes')
          .insert(episode.toInsertJson())
          .select()
          .single();
      return BleedingEpisode.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.createEpisode',
        feature: 'cycle_tracking',
        recordId: episode.userId,
      );
      return null;
    } on BleedingEpisodeParseException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.createEpisode',
        feature: 'cycle_tracking',
        recordId: episode.userId,
      );
      return null;
    }
  }

  Future<BleedingEpisode?> getActiveEpisode(String userId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('bleeding_episodes')
          .select()
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      if (response == null) return null;
      return BleedingEpisode.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getActiveEpisode',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return null;
    } on BleedingEpisodeParseException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getActiveEpisode',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return null;
    }
  }
}

/// Writes/reads a user's `cycle_baselines` row (their stated usual
/// duration/cycle length — always USER_REPORTED_ESTIMATE, never observed
/// history). See [BleedingEpisodeRepositoryImpl]'s doc comment for why
/// this is server-only in this initial slice.
class CycleBaselineRepositoryImpl {
  CycleBaselineRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  Future<CycleBaseline?> saveBaseline(CycleBaseline baseline) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('cycle_baselines')
          .upsert(baseline.toUpsertJson(), onConflict: 'user_id')
          .select()
          .single();
      return CycleBaseline.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'CycleBaselineRepositoryImpl.saveBaseline',
        feature: 'cycle_tracking',
        recordId: baseline.userId,
      );
      return null;
    }
  }

  Future<CycleBaseline?> getBaseline(String userId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('cycle_baselines')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (response == null) return null;
      return CycleBaseline.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'CycleBaselineRepositoryImpl.getBaseline',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return null;
    }
  }
}
