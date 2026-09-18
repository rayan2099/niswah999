import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../domain/entities/bleeding_episode.dart';
import '../local/pending_bleeding_operation_store.dart';

/// Thrown by [BleedingEpisodeRepositoryImpl.startEpisode] specifically
/// when the user already has an open episode — the database's
/// `bleeding_episodes_one_open_per_user` constraint is what actually
/// prevents the duplicate; this exception just gives the caller (the
/// Start Bleeding UI) a typed way to tell "you're already tracking one"
/// apart from a genuine failure, so a double-tap or retry never surfaces
/// as a scary error. Note this is distinct from a *retry of the same*
/// start — see [BleedingEpisodeRepositoryImpl.startEpisode]'s own
/// idempotency handling, which returns the original result instead of
/// throwing at all for that case.
class ActiveEpisodeAlreadyExistsException implements Exception {
  const ActiveEpisodeAlreadyExistsException();

  @override
  String toString() => 'ActiveEpisodeAlreadyExistsException';
}

/// Writes/reads the first-class `bleeding_episodes` / `bleeding_observations`
/// / `cycle_baselines` model (menstrual-data-integrity charter). Deliberately
/// server-only for this initial slice — every caller today (onboarding, the
/// dashboard's Start/End Bleeding actions) is only ever reached
/// already-authenticated, so a real session always exists; a
/// local-first/offline path mirroring [CycleTrackingRepositoryImpl] is
/// follow-up work once a consumer needs to read this data offline.
class BleedingEpisodeRepositoryImpl {
  BleedingEpisodeRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  /// The reporter's own local "today," derived from a UTC offset — never
  /// guessed, never dependent on a named timezone being recognized. Used
  /// to classify provenance (Blocker 4: reporting today is
  /// [ObservationSource.userObserved]; reporting any other date is
  /// [ObservationSource.userReportedHistorical]) consistently with what
  /// the canonical RPC itself uses for future-date rejection.
  static DateTime localToday(int utcOffsetMinutes) {
    final nowUtc = DateTime.now().toUtc();
    final local = nowUtc.add(Duration(minutes: utcOffsetMinutes));
    return DateTime(local.year, local.month, local.day);
  }

  /// Atomically creates an OPEN episode + its first observation via the
  /// `start_bleeding_episode` RPC — never two separate writes that could
  /// partially fail. [clientOperationId] must be generated once by the
  /// caller and reused unchanged on any retry of this exact logical
  /// action (double-tap, a lost response, an app restart before the
  /// result was seen) — the RPC returns the original episode/observation
  /// instead of erroring or duplicating when it recognizes a repeat.
  ///
  /// Throws [ActiveEpisodeAlreadyExistsException] if the user already has
  /// a *different*, genuinely open episode (the DB's one-open-per-user
  /// constraint is the real enforcement; this only classifies that
  /// specific, expected conflict for the caller). Any other failure is
  /// reported and rethrown — unlike onboarding's best-effort writes, a
  /// live "Start bleeding" tap must tell the user honestly if it did not
  /// save (Section 7: no false success).
  Future<({BleedingEpisode episode, BleedingObservation observation})>
  startEpisode({
    required String clientOperationId,
    required DateTime startDate,
    required ObservationPrecision startPrecision,
    DateTime? startTime,
    required ObservationFlow flow,
    DateTime? observedTime,
    required ObservationPrecision observationPrecision,
    String? timezone,
    required int utcOffsetMinutes,
    List<String>? symptoms,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'No Supabase session — cannot start a bleeding episode.',
      );
    }

    final source = ObservationSource.classify(
      reportedDate: startDate,
      localToday: localToday(utcOffsetMinutes),
    );

    try {
      final response = await client.rpc(
        'start_bleeding_episode',
        params: {
          'p_client_operation_id': clientOperationId,
          'p_start_date': _dateOnly(startDate),
          'p_start_precision': startPrecision.value,
          'p_start_time': startTime?.toIso8601String(),
          'p_start_source': source.value,
          'p_flow': flow.value,
          'p_observed_time': observedTime?.toIso8601String(),
          'p_precision': observationPrecision.value,
          'p_source': source.value,
          'p_timezone': timezone,
          'p_utc_offset_minutes': utcOffsetMinutes,
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
          lifecycleStatus: LifecycleStatus.open,
          continuationCertainty: ContinuationCertainty.confirmed,
          startDate: startDate,
          startPrecision: startPrecision,
          startSource: source,
          clientOperationId: clientOperationId,
        ),
        observation: BleedingObservation(
          id: observationId,
          userId: client.auth.currentUser!.id,
          episodeId: episodeId,
          observedDate: startDate,
          observedTime: observedTime,
          precision: observationPrecision,
          flow: flow,
          source: source,
          timezone: timezone,
          utcOffsetMinutes: utcOffsetMinutes,
          symptoms: symptoms,
          notes: notes,
          clientOperationId: clientOperationId,
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

  /// Atomically ends an open episode AND records its closing (`flow:
  /// none`) observation via the `end_bleeding_episode` RPC — a real,
  /// user-reported end date, never inferred from elapsed time. The
  /// original two-step (UPDATE the episode, then separately INSERT a
  /// closing observation) could leave an episode marked ended with no
  /// factual record of its own closure if the second step failed; this
  /// RPC makes both happen in one transaction, the same way starting an
  /// episode already did. [clientOperationId] gives this its own
  /// idempotency, independent of the start operation's key — a retried
  /// "end" call returns the original closing observation rather than
  /// erroring or double-closing.
  Future<({String episodeId, String closingObservationId})?> endEpisode({
    required String clientOperationId,
    required String episodeId,
    required DateTime endDate,
    required ObservationPrecision endPrecision,
    DateTime? observedTime,
    required ObservationPrecision observationPrecision,
    String? timezone,
    required int utcOffsetMinutes,
  }) async {
    final client = _client;
    if (client == null) return null;

    final source = ObservationSource.classify(
      reportedDate: endDate,
      localToday: localToday(utcOffsetMinutes),
    );

    try {
      final response = await client.rpc(
        'end_bleeding_episode',
        params: {
          'p_client_operation_id': clientOperationId,
          'p_episode_id': episodeId,
          'p_end_date': _dateOnly(endDate),
          'p_end_precision': endPrecision.value,
          'p_end_source': source.value,
          'p_observed_time': observedTime?.toIso8601String(),
          'p_precision': observationPrecision.value,
          'p_source': source.value,
          'p_timezone': timezone,
          'p_utc_offset_minutes': utcOffsetMinutes,
        },
      );

      final row = (response as List).single as Map<String, dynamic>;
      return (
        episodeId: row['episode_id'] as String,
        closingObservationId: row['closing_observation_id'] as String,
      );
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

  /// Marks an OPEN episode's continuation as uncertain — Section 15's
  /// "I'm not sure" daily check-in answer. Never closes the episode
  /// (`lifecycle_status` stays `open`, so the one-open-per-user slot
  /// stays occupied — a second, genuinely concurrent episode still
  /// cannot start) and never fabricates a positive bleeding observation.
  Future<BleedingEpisode?> markEpisodeUncertain(String episodeId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('bleeding_episodes')
          .update({'continuation_certainty': 'uncertain'})
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
  /// UPDATE/DELETE on this table for the owning user, so a correction
  /// MUST come through here as a new row.
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

  /// Hardening 2's explicit controlled correction path — never
  /// `addObservation` with `supersedesId` set. Unlike a plain INSERT, this
  /// calls the dedicated `correct_observation` RPC: idempotent
  /// (`clientOperationId` retried returns the original correction's id,
  /// never a duplicate), and — critically — episode-state-agnostic. A
  /// correction targeting an observation that belongs to an *already-
  /// ended* episode is exactly the case `bleeding_observations_validate_insert`
  /// would otherwise reject as "a new fact on an ended episode"; this RPC
  /// is the one exception the trigger actually recognizes, and it is
  /// deliberately not `SECURITY DEFINER` so RLS and the trigger both still
  /// apply as independent layers on top of it.
  ///
  /// [supersedesId] is the observation being corrected — the RPC resolves
  /// which episode this belongs to *from that row*, so a caller can never
  /// misdirect a correction at the wrong episode.
  Future<String?> correctObservation({
    required String clientOperationId,
    required String supersedesId,
    required DateTime observedDate,
    required ObservationPrecision precision,
    required ObservationFlow flow,
    required ObservationSource source,
    required int utcOffsetMinutes,
    DateTime? observedTime,
    String? timezone,
    List<String>? symptoms,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client.rpc(
        'correct_observation',
        params: {
          'p_client_operation_id': clientOperationId,
          'p_supersedes_id': supersedesId,
          'p_observed_date': _dateOnly(observedDate),
          'p_precision': precision.value,
          'p_flow': flow.value,
          'p_source': source.value,
          'p_utc_offset_minutes': utcOffsetMinutes,
          'p_observed_time': observedTime?.toIso8601String(),
          'p_timezone': timezone,
          'p_symptoms': symptoms,
          'p_notes': notes,
        },
      );
      final row = (response as List).single as Map<String, dynamic>;
      return row['observation_id'] as String?;
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.correctObservation',
        feature: 'cycle_tracking',
        recordId: supersedesId,
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

  /// PR #4 completion wave, Fix A: onboarding's one canonical persistence
  /// operation — replaces two separate calls (createEpisode, then
  /// saveBaseline) whose partial-failure window (episode succeeds,
  /// baseline fails, she taps Retry) could duplicate an ended historical
  /// episode, conflict against an already-open one, or show a false
  /// "failed" state for data that had actually already saved. One RPC,
  /// one transaction: either everything submitted is saved, or nothing
  /// is — no partial state is ever observable. [clientOperationId] must
  /// be generated once by the caller and reused unchanged on every retry
  /// of this exact logical action; the RPC recognizes a repeat and
  /// returns the original result instead of erroring or duplicating.
  ///
  /// [episode] and [baseline] are each independently optional — pass
  /// null for whichever she didn't answer ("I'm not sure"). Returns the
  /// ids of whatever was actually recorded (matching, on a retry, exactly
  /// what was recorded the first time). Throws on a genuine failure —
  /// unlike the old best-effort createEpisode/saveBaseline, onboarding
  /// completion must know honestly whether this succeeded (Blocker 3).
  Future<({String? episodeId, String? baselineId})> recordOnboardingHistory({
    required String clientOperationId,
    required int utcOffsetMinutes,
    BleedingEpisode? episode,
    CycleBaseline? baseline,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'No Supabase session — cannot record onboarding history.',
      );
    }

    final response = await client.rpc(
      'record_onboarding_menstrual_history',
      params: {
        'p_client_operation_id': clientOperationId,
        'p_utc_offset_minutes': utcOffsetMinutes,
        if (episode != null) ...{
          'p_start_date': _dateOnly(episode.startDate),
          'p_start_precision': episode.startPrecision.value,
          'p_start_source': episode.startSource.value,
          'p_lifecycle_status': episode.lifecycleStatus.value,
          if (episode.continuationCertainty != null)
            'p_continuation_certainty': episode.continuationCertainty!.value,
          if (episode.endDate != null)
            'p_end_date': _dateOnly(episode.endDate!),
          if (episode.endPrecision != null)
            'p_end_precision': episode.endPrecision!.value,
          if (episode.endSource != null)
            'p_end_source': episode.endSource!.value,
        },
        if (baseline != null) ...{
          if (baseline.usualBleedingDurationDays != null)
            'p_usual_bleeding_duration_days':
                baseline.usualBleedingDurationDays,
          if (baseline.usualCycleLengthDays != null)
            'p_usual_cycle_length_days': baseline.usualCycleLengthDays,
        },
      },
    );

    final row = (response as List).single as Map<String, dynamic>;
    return (
      episodeId: row['episode_id'] as String?,
      baselineId: row['baseline_id'] as String?,
    );
  }

  /// The user's currently open episode (bleeding may be ongoing, or its
  /// continuation may be uncertain — either way, the one-open-per-user
  /// slot is occupied), if any.
  Future<BleedingEpisode?> getOpenEpisode(String userId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('bleeding_episodes')
          .select()
          .eq('user_id', userId)
          .eq('lifecycle_status', 'open')
          .maybeSingle();
      if (response == null) return null;
      return BleedingEpisode.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getOpenEpisode',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return null;
    } on BleedingEpisodeParseException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getOpenEpisode',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return null;
    }
  }

  /// PR #4 completion wave, Fix D: replays every still-[PendingBleedingOperationStore]
  /// operation through the exact same idempotent RPC it was originally
  /// headed for — safe because both `start_bleeding_episode` and
  /// `end_bleeding_episode` are themselves idempotent (see their own doc
  /// comments): replaying a call that already reached the server and
  /// committed returns the original result rather than erroring or
  /// duplicating; replaying one that never reached the server completes
  /// it for the first time. Intended to run at app start (a killed
  /// process is the exact failure mode this exists for), but safe to call
  /// at any point — a call with nothing pending is a no-op.
  ///
  /// Deliberately does not attempt the `cycle_entries` projection here —
  /// that mirror is best-effort/non-authoritative by design (see the
  /// contract doc's Blocker 12 note); a canonical write recovered by this
  /// method is still fully durable without it, and the next real app-open
  /// through the dashboard already re-derives from canonical data going
  /// forward once Commit F lands.
  Future<void> reconcilePendingOperations() async {
    final pending = await PendingBleedingOperationStore.loadPending();
    for (final operation in pending) {
      try {
        switch (operation.type) {
          case PendingBleedingOperationType.startEpisode:
            final params = operation.params;
            await startEpisode(
              clientOperationId: operation.operationId,
              startDate: DateTime.parse(params['startDate'] as String),
              startPrecision: ObservationPrecision.parse(
                params['startPrecision'] as String?,
              ),
              flow: ObservationFlow.parse(params['flow'] as String?),
              observationPrecision: ObservationPrecision.parse(
                params['observationPrecision'] as String?,
              ),
              timezone: params['timezone'] as String?,
              utcOffsetMinutes: params['utcOffsetMinutes'] as int,
            );
          case PendingBleedingOperationType.endEpisode:
            final params = operation.params;
            await endEpisode(
              clientOperationId: operation.operationId,
              episodeId: params['episodeId'] as String,
              endDate: DateTime.parse(params['endDate'] as String),
              endPrecision: ObservationPrecision.parse(
                params['endPrecision'] as String?,
              ),
              observationPrecision: ObservationPrecision.parse(
                params['observationPrecision'] as String?,
              ),
              timezone: params['timezone'] as String?,
              utcOffsetMinutes: params['utcOffsetMinutes'] as int,
            );
          case PendingBleedingOperationType.onboardingHistory:
            // Hardening 1: the onboarding screen persisted this *before*
            // ever calling record_onboarding_menstrual_history — reaching
            // here means either the request never left the device, or it
            // reached the server but the response never made it back
            // (process death is exactly the failure this store exists
            // for). Either way, replaying with the same operationId is
            // safe: the RPC's own idempotency check returns the original
            // episode_id/baseline_id on a genuine retry instead of
            // duplicating anything.
            final userId = _client?.auth.currentUser?.id;
            if (userId == null) {
              throw StateError(
                'No Supabase session — cannot reconcile onboarding history yet.',
              );
            }
            final params = operation.params;
            final episodeJson = params['episode'] as Map<String, dynamic>?;
            final baselineJson = params['baseline'] as Map<String, dynamic>?;
            await recordOnboardingHistory(
              clientOperationId: operation.operationId,
              utcOffsetMinutes: params['utcOffsetMinutes'] as int,
              episode: episodeJson == null
                  ? null
                  : BleedingEpisode(
                      userId: userId,
                      lifecycleStatus: LifecycleStatus.parse(
                        episodeJson['lifecycleStatus'] as String?,
                      ),
                      continuationCertainty:
                          episodeJson['continuationCertainty'] == null
                          ? null
                          : ContinuationCertainty.parse(
                              episodeJson['continuationCertainty'] as String?,
                            ),
                      startDate: DateTime.parse(
                        episodeJson['startDate'] as String,
                      ),
                      startPrecision: ObservationPrecision.parse(
                        episodeJson['startPrecision'] as String?,
                      ),
                      startSource: ObservationSource.parse(
                        episodeJson['startSource'] as String?,
                      ),
                      endDate: episodeJson['endDate'] == null
                          ? null
                          : DateTime.parse(episodeJson['endDate'] as String),
                      endPrecision: episodeJson['endPrecision'] == null
                          ? null
                          : ObservationPrecision.parse(
                              episodeJson['endPrecision'] as String?,
                            ),
                      endSource: episodeJson['endSource'] == null
                          ? null
                          : ObservationSource.parse(
                              episodeJson['endSource'] as String?,
                            ),
                    ),
              baseline: baselineJson == null
                  ? null
                  : CycleBaseline(
                      userId: userId,
                      usualBleedingDurationDays:
                          baselineJson['usualBleedingDurationDays'] as int?,
                      usualCycleLengthDays:
                          baselineJson['usualCycleLengthDays'] as int?,
                    ),
            );
            // The historical data is now durably saved server-side — she
            // must never be routed back through onboarding to re-answer
            // (and risk a second, semantically-duplicate submission)
            // merely because this reconciliation ran after the process
            // died before her own _finishOnboarding ever completed.
            // Best-effort, matching _finishOnboarding's own established
            // tradeoff: a failure here just means she may see onboarding
            // once more, not that anything was lost or duplicated.
            try {
              await AuthRepositoryImpl().markOnboardingCompleted();
            } catch (_) {
              // Swallowed deliberately — see comment above.
            }
        }
        await PendingBleedingOperationStore.clearPending(operation.operationId);
      } catch (error, stack) {
        // Left pending — the next reconciliation attempt (next app start)
        // will retry it. Reported so a persistently-failing reconcile is
        // observable rather than silently retried forever.
        AppErrorReporter.report(
          error,
          stack,
          context: 'BleedingEpisodeRepositoryImpl.reconcilePendingOperations',
          feature: 'cycle_tracking',
          recordId: operation.operationId,
        );
      }
    }
  }
}

/// Writes/reads a user's `cycle_baselines` history (their stated usual
/// duration/cycle length over time — always USER_REPORTED_ESTIMATE, never
/// observed history). See [BleedingEpisodeRepositoryImpl]'s doc comment
/// for why this is server-only in this initial slice.
class CycleBaselineRepositoryImpl {
  CycleBaselineRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  /// Always a new row — a changed estimate never overwrites the old one
  /// (Blocker 9: reproducibility requires the old value to remain
  /// recoverable for anything that may have used it).
  Future<CycleBaseline?> saveBaseline(CycleBaseline baseline) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('cycle_baselines')
          .insert(baseline.toInsertJson())
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

  /// The current baseline — the most recently reported one, since none of
  /// them are ever overwritten in place.
  Future<CycleBaseline?> getBaseline(String userId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('cycle_baselines')
          .select()
          .eq('user_id', userId)
          .order('reported_at', ascending: false)
          .limit(1)
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
