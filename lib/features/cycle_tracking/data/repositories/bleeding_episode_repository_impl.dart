import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/errors/network_failure.dart';
import '../../../../core/storage/secure_local_store.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../domain/entities/bleeding_episode.dart';
import '../../domain/entities/load_result.dart';
import '../local/pending_bleeding_operation_store.dart';
import 'cycle_entries_projection.dart';

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

/// Commit D7 — thrown by [BleedingEpisodeRepositoryImpl.correctObservation]
/// specifically when [supersedesId] is no longer the current tip of its
/// revision chain: another correction (a different device, an earlier
/// reconciliation) already superseded it first. This is never a generic
/// failure — it is `correct_observation`'s own `ERRCODE = 'NW409'`,
/// recognized here so the caller can show a real conflict-resolution UI
/// ("Current saved value: X / Your offline change: Y") instead of a
/// scary error or, worse, a silent last-write-wins. [supersedesId] is the
/// target the caller originally tried to correct — resolve "what is the
/// current value now" via [BleedingEpisodeRepositoryImpl.effectiveObservationId]
/// (a fresh call, deliberately not parsed out of the exception message).
class CorrectionConflictException implements Exception {
  const CorrectionConflictException(this.supersedesId);

  final String supersedesId;

  @override
  String toString() => 'CorrectionConflictException($supersedesId)';
}

/// Logging/sync hardening (proposed, 2026-10-18) — the server answered a
/// write with a deterministic rejection: a validation `RAISE EXCEPTION`
/// (SQLSTATE `P0001`), a constraint violation (`23xxx`) or malformed input
/// (`22xxx`). Re-sending the same data can never succeed, so this is never
/// reported to her as "Saved on device — syncing": the write sheets show a
/// real error and drop the queued copy, and
/// [BleedingEpisodeRepositoryImpl.reconcilePendingOperations] files it as
/// [PendingOperationFailureCategory.validation] instead of retrying it as a
/// network gap.
class BleedingWriteRejectedException implements Exception {
  const BleedingWriteRejectedException(this.code, this.message);

  /// The Postgres/PostgREST error code, e.g. `P0001` or `23514`.
  final String code;
  final String message;

  @override
  String toString() => 'BleedingWriteRejectedException($code: $message)';
}

/// Logging/sync hardening (proposed) — `record_onboarding_menstrual_history`
/// returned normally but with `episode_conflict = true`: nothing was saved
/// for the episode part. Thrown only by the background replay, so a
/// conflicting queued onboarding submission stays pending (needs her
/// review) instead of being cleared as if it had saved.
class OnboardingEpisodeConflictException implements Exception {
  const OnboardingEpisodeConflictException();

  @override
  String toString() => 'OnboardingEpisodeConflictException';
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
  /// A deterministic server rejection — see [BleedingWriteRejectedException].
  static bool isPermanentRejectionCode(String? code) {
    if (code == null) return false;
    return code == 'P0001' || code.startsWith('23') || code.startsWith('22');
  }

  /// No response from the server at all (offline, DNS, refused, timeout).
  /// postgrest does not wrap these in a [PostgrestException].
  static bool isTransportFailure(Object error) =>
      error is http.ClientException || isNetworkFailure(error);

  /// Shared failure policy for every write that can be queued on device:
  /// a deterministic rejection is thrown as [BleedingWriteRejectedException];
  /// anything transient (a transport failure or a non-deterministic
  /// PostgREST error) returns normally so the caller reports the queued
  /// "Saved on device — syncing" outcome. Anything else is rethrown.
  static void _classifyWriteFailure(
    Object error,
    StackTrace stack, {
    required String context,
    String? recordId,
  }) {
    if (error is PostgrestException) {
      AppErrorReporter.report(
        error,
        stack,
        context: context,
        feature: 'cycle_tracking',
        recordId: recordId,
      );
      if (isPermanentRejectionCode(error.code)) {
        throw BleedingWriteRejectedException(error.code!, error.message);
      }
      return;
    }
    if (isTransportFailure(error)) {
      AppErrorReporter.report(
        error,
        stack,
        context: context,
        feature: 'cycle_tracking',
        recordId: recordId,
      );
      return;
    }
    Error.throwWithStackTrace(error, stack);
  }

  static DateTime localToday(int utcOffsetMinutes) {
    // AppClock.now defaults to DateTime.now (identical production
    // behavior); it is the single controllable clock the notification
    // coordinator already derives its own `now` from, so a test that
    // pins it gets one consistent logical "today" on both sides.
    final nowUtc = AppClock.now().toUtc();
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
          'p_flow': flow.value,
          'p_observed_time': observedTime?.toIso8601String(),
          'p_precision': observationPrecision.value,
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
      // A deterministic rejection is thrown as
      // BleedingWriteRejectedException; anything transient is rethrown
      // unchanged (the Start sheet reports it as queued).
      _classifyWriteFailure(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.startEpisode',
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
    DateTime? endTime,
    DateTime? observedTime,
    required ObservationPrecision observationPrecision,
    String? timezone,
    required int utcOffsetMinutes,
  }) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client.rpc(
        'end_bleeding_episode',
        params: {
          'p_client_operation_id': clientOperationId,
          'p_episode_id': episodeId,
          'p_end_date': _dateOnly(endDate),
          'p_end_precision': endPrecision.value,
          'p_end_time': endTime?.toIso8601String(),
          'p_observed_time': observedTime?.toIso8601String(),
          'p_precision': observationPrecision.value,
          'p_timezone': timezone,
          'p_utc_offset_minutes': utcOffsetMinutes,
        },
      );

      final row = (response as List).single as Map<String, dynamic>;
      return (
        episodeId: row['episode_id'] as String,
        closingObservationId: row['closing_observation_id'] as String,
      );
    } catch (error, stack) {
      // Logging/sync hardening: null only for a transient failure (the
      // operation stays queued); a deterministic rejection throws
      // BleedingWriteRejectedException.
      _classifyWriteFailure(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.endEpisode',
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
  ///
  /// Hardening 5: calls the `set_continuation_uncertain` RPC — a direct
  /// client UPDATE on `bleeding_episodes` is no longer possible at all
  /// (every client-facing grant on that table was revoked).
  Future<BleedingEpisode?> markEpisodeUncertain(String episodeId) async {
    final client = _client;
    if (client == null) return null;

    try {
      await client.rpc(
        'set_continuation_uncertain',
        params: {'p_episode_id': episodeId},
      );
      final response = await client
          .from('bleeding_episodes')
          .select()
          .eq('id', episodeId)
          .single();
      return BleedingEpisode.fromJson(response);
    } catch (error, stack) {
      if (error is! PostgrestException && !isTransportFailure(error)) {
        rethrow;
      }
      // Not queued on device (no pending operation backs it), so every
      // failure — transient or not — is an honest "could not save".
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

  /// Records one immutable NEW fact against an OPEN episode — Commit D1's
  /// daily check-in YES answer (today's date) or Commit D4's backfill
  /// (a past date; `source` is `userReportedHistorical`, classified by
  /// the same [ObservationSource.classify] every other write path uses).
  /// Never a correction — [supersedesId] is deliberately not a parameter
  /// here at all; a correction to an *existing* fact must go through
  /// [correctObservation] instead, which is a structurally different
  /// operation (Hardening 2's own stated principle: adding a new event
  /// and correcting a prior one are kept as two distinct operations, not
  /// one INSERT path branching on whether a field is set).
  ///
  /// Hardening 5: calls the `record_bleeding_observation` RPC — a direct
  /// client INSERT into `bleeding_observations` is no longer possible at
  /// all (every client-facing grant on that table was revoked).
  /// [clientOperationId] must be generated once and reused unchanged on
  /// every retry of this exact logical action (see
  /// [PendingBleedingOperationStore] for surviving a process death
  /// between the server committing and the response arriving).
  Future<String?> recordObservation({
    required String clientOperationId,
    required String episodeId,
    required DateTime observedDate,
    required ObservationPrecision precision,
    required ObservationFlow flow,
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
        'record_bleeding_observation',
        params: {
          'p_client_operation_id': clientOperationId,
          'p_episode_id': episodeId,
          'p_observed_date': _dateOnly(observedDate),
          'p_precision': precision.value,
          'p_flow': flow.value,
          'p_utc_offset_minutes': utcOffsetMinutes,
          'p_observed_time': observedTime?.toIso8601String(),
          'p_timezone': timezone,
          'p_symptoms': symptoms,
          'p_notes': notes,
        },
      );
      final row = (response as List).single as Map<String, dynamic>;
      return row['observation_id'] as String?;
    } catch (error, stack) {
      _classifyWriteFailure(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.recordObservation',
        recordId: episodeId,
      );
      return null;
    }
  }

  /// Hardening 2's explicit controlled correction path — never a direct
  /// INSERT with `supersedesId` set (Hardening 5 revoked that grant
  /// entirely; only this SECURITY DEFINER RPC can write a correction now).
  /// Idempotent (`clientOperationId` retried returns the original
  /// correction's id, never a duplicate), and — critically —
  /// episode-state-agnostic: a correction targeting an observation that
  /// belongs to an *already-ended* episode is exactly the case
  /// `bleeding_observations_validate_insert` would otherwise reject as "a
  /// new fact on an ended episode."
  ///
  /// [supersedesId] is the observation being corrected — the RPC resolves
  /// which episode this belongs to *from that row*, so a caller can never
  /// misdirect a correction at the wrong episode.
  ///
  /// Commit D7: throws [CorrectionConflictException] — never a generic
  /// [PostgrestException] — when [supersedesId] is no longer the current
  /// tip of its revision chain (a concurrent correction from another
  /// device already superseded it first). The caller must not treat this
  /// as an ordinary failure: resolve the real current value via
  /// [effectiveObservationId] and let the user choose to keep the saved
  /// value or retry rebased onto it (never a silent last-write-win, never
  /// a silent fork).
  ///
  /// Closure Blocker 4: takes no `source` parameter — the RPC always
  /// stores `user_reported_historical` for a correction, since amending a
  /// prior fact is never honestly "live observed" even when filed the
  /// same day as the original.
  Future<String?> correctObservation({
    required String clientOperationId,
    required String supersedesId,
    required DateTime observedDate,
    required ObservationPrecision precision,
    required ObservationFlow flow,
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
          'p_utc_offset_minutes': utcOffsetMinutes,
          'p_observed_time': observedTime?.toIso8601String(),
          'p_timezone': timezone,
          'p_symptoms': symptoms,
          'p_notes': notes,
        },
      );
      final row = (response as List).single as Map<String, dynamic>;
      return row['observation_id'] as String?;
    } catch (error, stack) {
      if (error is PostgrestException && error.code == 'NW409') {
        throw CorrectionConflictException(supersedesId);
      }
      _classifyWriteFailure(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.correctObservation',
        recordId: supersedesId,
      );
      return null;
    }
  }

  /// Commit D5 — the effective-observation resolver: given ANY id in a
  /// revision chain (the original root or a later correction), returns
  /// the id of the chain's current tip (the row nothing else supersedes)
  /// — the value that is actually true right now. Calls the
  /// `effective_observation_id` SQL function rather than re-implementing
  /// the recursive walk client-side, so there is exactly one tested
  /// definition of "current tip" the correction UI, the conflict-
  /// resolution UI (D7), and any future reader all share.
  Future<String?> effectiveObservationId(String observationId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client.rpc(
        'effective_observation_id',
        params: {'p_observation_id': observationId},
      );
      return response as String?;
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.effectiveObservationId',
        feature: 'cycle_tracking',
        recordId: observationId,
      );
      return null;
    }
  }

  /// Commit D5/D6 — the full revision history for one logical fact,
  /// oldest (the original report) first: walks forward from [rootObservationId]
  /// following each row's own `supersedes_id` back-reference until no
  /// further correction is found. A correction-of-correction (D6: v1 ->
  /// v2 -> v3) returns all three, in order — nothing is ever discarded
  /// merely because a later correction superseded it. [rootObservationId]
  /// must be the *original* (never-superseded) observation; passing a
  /// later revision returns only the remainder of the chain from that
  /// point forward, which is why the UI should always resolve to the
  /// true root before calling this (every observation this app creates
  /// through [recordObservation] is itself always a root, since it never
  /// accepts a `supersedesId`).
  Future<LoadResult<List<BleedingObservation>>> getRevisionHistory(
    String rootObservationId,
  ) async {
    final episodeId = await _episodeIdFor(rootObservationId);
    if (episodeId == null) {
      return const LoadUnavailable(
        LoadErrorCategory.unknown,
        'Could not resolve the episode for this observation',
      );
    }
    final result = await getObservationsForEpisode(episodeId);
    return switch (result) {
      LoadUnavailable<List<BleedingObservation>>() => LoadUnavailable(
        result.category,
        result.message,
      ),
      LoadSuccess<List<BleedingObservation>>(:final data) => LoadSuccess(
        _walkChain(data, rootObservationId),
      ),
      LoadDegraded<List<BleedingObservation>>(
        :final data,
        :final quarantinedCount,
      ) =>
        LoadDegraded(_walkChain(data, rootObservationId), quarantinedCount),
    };
  }

  List<BleedingObservation> _walkChain(
    List<BleedingObservation> all,
    String rootObservationId,
  ) {
    final chain = <BleedingObservation>[];
    String? currentId = rootObservationId;
    while (currentId != null) {
      final match = all.where((o) => o.id == currentId).firstOrNull;
      if (match == null) break;
      chain.add(match);
      currentId = all.where((o) => o.supersedesId == currentId).firstOrNull?.id;
    }
    return chain;
  }

  /// Logging/sync hardening (proposed) — whether [id] is a canonical
  /// `bleeding_observations` row, i.e. whether a `cycle_entries` row with
  /// the same id is [CycleEntriesProjection]'s mirror of it. The legacy log
  /// sheet must not overwrite such a mirror (the canonical observation is
  /// the fact; corrections go through `correct_observation`). Null when it
  /// cannot be determined (no session, offline, malformed id).
  Future<bool?> isCanonicalObservationId(String id) async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client
          .from('bleeding_observations')
          .select('id')
          .eq('id', id)
          .maybeSingle();
      return response != null;
    } catch (_) {
      return null;
    }
  }

  /// One of [userId]'s observations by id, or null when it cannot be read
  /// (no session, not found, a read failure or an unparseable row — each
  /// reported). The owner filter is explicit: RLS also admits admin reads,
  /// so an id alone could return another user's row.
  Future<BleedingObservation?> getObservationById(
    String observationId, {
    required String userId,
  }) async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client
          .from('bleeding_observations')
          .select()
          .eq('id', observationId)
          .eq('user_id', userId)
          .maybeSingle();
      return response == null ? null : BleedingObservation.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getObservationById',
        feature: 'cycle_tracking',
        recordId: observationId,
      );
      return null;
    } on BleedingEpisodeParseException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getObservationById',
        feature: 'cycle_tracking',
        recordId: observationId,
      );
      return null;
    }
  }

  Future<String?> _episodeIdFor(String observationId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client
          .from('bleeding_observations')
          .select('episode_id')
          .eq('id', observationId)
          .maybeSingle();
      return response?['episode_id'] as String?;
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl._episodeIdFor',
        feature: 'cycle_tracking',
        recordId: observationId,
      );
      return null;
    }
  }

  /// Every observation for an episode, oldest first — the raw evidence
  /// behind a day's summary (Section 39: same-day multiple observations
  /// must all remain visible, never collapsed into one fabricated value).
  Future<LoadResult<List<BleedingObservation>>> getObservationsForEpisode(
    String episodeId,
  ) async {
    final client = _client;
    if (client == null) {
      return const LoadUnavailable(LoadErrorCategory.unknown, 'No session');
    }

    try {
      final response = await client
          .from('bleeding_observations')
          .select()
          .eq('episode_id', episodeId)
          .order('observed_date')
          .order('reported_at');
      final rows = response as List<dynamic>;
      final observations = <BleedingObservation>[];
      var quarantined = 0;
      for (final row in rows) {
        try {
          observations.add(
            BleedingObservation.fromJson(row as Map<String, dynamic>),
          );
        } on BleedingEpisodeParseException catch (error, stack) {
          quarantined++;
          AppErrorReporter.report(
            error,
            stack,
            context: 'BleedingEpisodeRepositoryImpl.getObservationsForEpisode',
            feature: 'cycle_tracking',
            recordId: (row as Map<String, dynamic>)['id'] as String?,
          );
        }
      }
      return quarantined > 0
          ? LoadDegraded(observations, quarantined)
          : LoadSuccess(observations);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getObservationsForEpisode',
        feature: 'cycle_tracking',
        recordId: episodeId,
      );
      return LoadUnavailable(_categorizeError(error), error.message);
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
  ///
  /// Manual QA wave (2026-10-12): [episodeId] can now come back non-null
  /// alongside [episodeConflict] being false in two different honest
  /// ways — a freshly-inserted episode, or an *existing* open episode
  /// the RPC recognized as the same one she just described (same start
  /// date) and reused rather than rejecting with a uniqueness violation.
  /// Callers that only care "did my episode answer get recorded" don't
  /// need to distinguish the two. [episodeConflict] is true only when
  /// the user already has a *different* open episode (a different start
  /// date) — in that case [episodeId] is null (nothing was recorded for
  /// the episode part; the baseline may still have saved) and
  /// [conflictingEpisodeStartDate] names the existing episode's own
  /// date, for a real resolution UI rather than a generic failure.
  Future<
    ({
      String? episodeId,
      String? baselineId,
      bool episodeConflict,
      DateTime? conflictingEpisodeStartDate,
    })
  >
  recordOnboardingHistory({
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
          'p_lifecycle_status': episode.lifecycleStatus.value,
          if (episode.continuationCertainty != null)
            'p_continuation_certainty': episode.continuationCertainty!.value,
          if (episode.endDate != null)
            'p_end_date': _dateOnly(episode.endDate!),
          if (episode.endPrecision != null)
            'p_end_precision': episode.endPrecision!.value,
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
    final conflictingDateRaw = row['conflicting_start_date'] as String?;
    return (
      episodeId: row['episode_id'] as String?,
      baselineId: row['baseline_id'] as String?,
      episodeConflict: row['episode_conflict'] as bool? ?? false,
      conflictingEpisodeStartDate: conflictingDateRaw == null
          ? null
          : DateTime.parse(conflictingDateRaw),
    );
  }

  /// The user's currently open episode (bleeding may be ongoing, or its
  /// continuation may be uncertain — either way, the one-open-per-user
  /// slot is occupied), if any.
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String userId) async {
    final client = _client;
    if (client == null) {
      return const LoadUnavailable(LoadErrorCategory.unknown, 'No session');
    }

    try {
      final response = await client
          .from('bleeding_episodes')
          .select()
          .eq('user_id', userId)
          .eq('lifecycle_status', 'open')
          .maybeSingle();
      if (response == null) return const LoadSuccess(null);
      return LoadSuccess(BleedingEpisode.fromJson(response));
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getOpenEpisode',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return LoadUnavailable(_categorizeError(error), error.message);
    } on BleedingEpisodeParseException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getOpenEpisode',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      // A single-row read's own row failing to parse has nothing left to
      // degrade gracefully into — the whole read is unavailable, not
      // "verified: no open episode."
      return LoadUnavailable(LoadErrorCategory.parseFailure, error.toString());
    }
  }

  /// Commit F — every canonical episode for a user, most recent first.
  /// Used by [CanonicalBleedingStatusResolver] to count real completed
  /// episodes directly (Section F5/F6: one completed episode is not
  /// enough for a cycle-to-cycle prediction) without depending on the
  /// legacy `cycle_entries` projection at all.
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async {
    final client = _client;
    if (client == null) {
      return const LoadUnavailable(LoadErrorCategory.unknown, 'No session');
    }

    try {
      final response = await client
          .from('bleeding_episodes')
          .select()
          .eq('user_id', userId)
          .order('start_date', ascending: false);
      final rows = response as List<dynamic>;
      final episodes = <BleedingEpisode>[];
      var quarantined = 0;
      for (final row in rows) {
        try {
          episodes.add(BleedingEpisode.fromJson(row as Map<String, dynamic>));
        } on BleedingEpisodeParseException catch (error, stack) {
          quarantined++;
          AppErrorReporter.report(
            error,
            stack,
            context: 'BleedingEpisodeRepositoryImpl.getEpisodesForUser',
            feature: 'cycle_tracking',
            recordId: (row as Map<String, dynamic>)['id'] as String?,
          );
        }
      }
      return quarantined > 0
          ? LoadDegraded(episodes, quarantined)
          : LoadSuccess(episodes);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getEpisodesForUser',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return LoadUnavailable(_categorizeError(error), error.message);
    }
  }

  /// Closure Blocker 3 — every canonical observation across every one of
  /// a user's episodes, in one query, for
  /// [CanonicalFiqhEvidenceAdapter]'s own use (it needs the full
  /// timeline to build effective, day-level evidence, not just one
  /// episode's own observations).
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String userId,
  ) async {
    final client = _client;
    if (client == null) {
      return const LoadUnavailable(LoadErrorCategory.unknown, 'No session');
    }

    try {
      final response = await client
          .from('bleeding_observations')
          .select()
          .eq('user_id', userId)
          .order('observed_date')
          .order('reported_at');
      final rows = response as List<dynamic>;
      final observations = <BleedingObservation>[];
      var quarantined = 0;
      for (final row in rows) {
        try {
          observations.add(
            BleedingObservation.fromJson(row as Map<String, dynamic>),
          );
        } on BleedingEpisodeParseException catch (error, stack) {
          quarantined++;
          AppErrorReporter.report(
            error,
            stack,
            context: 'BleedingEpisodeRepositoryImpl.getAllObservationsForUser',
            feature: 'cycle_tracking',
            recordId: (row as Map<String, dynamic>)['id'] as String?,
          );
        }
      }
      return quarantined > 0
          ? LoadDegraded(observations, quarantined)
          : LoadSuccess(observations);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getAllObservationsForUser',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return LoadUnavailable(_categorizeError(error), error.message);
    }
  }

  /// Closure Blocker 1/17 — a best-effort, conservative mapping from a
  /// Postgrest failure to a [LoadErrorCategory]; used only to inform an
  /// honest retry message, never to decide whether the data is "really"
  /// absent.
  static LoadErrorCategory _categorizeError(PostgrestException error) {
    final code = error.code;
    if (code == '42501' || code == 'PGRST301' || code == '401') {
      return LoadErrorCategory.unauthorized;
    }
    if (code == null) return LoadErrorCategory.network;
    return LoadErrorCategory.backend;
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
  ///
  /// New critical finding — three honest sync states: [forceAll] (a
  /// deliberate, informed manual "Retry now" action, never the automatic
  /// app-start/resume trigger) is the only way an operation whose last
  /// failure was categorized [PendingOperationFailureCategory.validation]
  /// or [PendingOperationFailureCategory.correctionConflict] is attempted
  /// again — automatic reconciliation always skips them
  /// ([PendingBleedingOperation.eligibleForAutomaticRetry]), since
  /// retrying either with unchanged data cannot succeed and would only
  /// ever waste a retry slot silently forever ("do not retry invalid
  /// operations indefinitely").
  static Future<void>? _reconcileInFlight;
  static String? _reconcileInFlightOwner;

  /// App start, app resume and the needs-attention banner can each start a
  /// replay; before this guard two overlapping passes both replayed every
  /// queued operation (a second RPC per operation, a second projection
  /// write) and raced each other's queue updates. A call made while a pass
  /// for the same signed-in user is running waits for it and, unless it is
  /// a [forceAll] request (which also retries operations the automatic
  /// pass skips), does not start another.
  Future<void> reconcilePendingOperations({bool forceAll = false}) async {
    while (_reconcileInFlight != null) {
      final running = _reconcileInFlight!;
      final sameOwner =
          _reconcileInFlightOwner == SecureLocalStore.currentUserId();
      await running;
      if (sameOwner && !forceAll) return;
    }
    final pass = _reconcilePass(forceAll: forceAll);
    _reconcileInFlight = pass;
    _reconcileInFlightOwner = SecureLocalStore.currentUserId();
    try {
      await pass;
    } finally {
      if (identical(_reconcileInFlight, pass)) {
        _reconcileInFlight = null;
        _reconcileInFlightOwner = null;
      }
    }
  }

  Future<void> _reconcilePass({required bool forceAll}) async {
    // Logging/sync hardening (proposed): the queue's owner is captured
    // ONCE. Every load/save/clear below targets that owner's bucket, and
    // the pass stops as soon as the signed-in user changes — so an account
    // switch mid-sync can neither move this user's queued health data into
    // another account's queue nor replay it under another session.
    final ownerId = SecureLocalStore.currentUserId();
    bool ownerChanged() => SecureLocalStore.currentUserId() != ownerId;
    final pending = await PendingBleedingOperationStore.loadPending(
      userId: ownerId,
    );
    var clearedAny = false;
    for (final operation in pending) {
      if (ownerChanged()) break;
      if (!forceAll && !operation.eligibleForAutomaticRetry) continue;
      // Set by the cases below when the replay produced an observation
      // the interactive path would have mirrored into the legacy read
      // model; see [_projectReplayedObservation].
      String? replayedObservationId;
      String? supersededObservationId;
      try {
        switch (operation.type) {
          case PendingBleedingOperationType.startEpisode:
            final params = operation.params;
            final started = await startEpisode(
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
            replayedObservationId = started.observation.id;
          case PendingBleedingOperationType.endEpisode:
            final params = operation.params;
            final endResult = await endEpisode(
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
            // A genuine finding: endEpisode returns null (rather than
            // throwing) on both "no session" and an ordinary RPC
            // failure it already caught and reported internally — this
            // switch must not silently treat that as success and clear
            // the pending operation regardless. Throwing here is what
            // routes both cases into the shared "leave pending" path
            // below, exactly like every other case in this switch.
            if (endResult == null) {
              throw StateError(
                'endEpisode reconciliation did not complete — leaving pending.',
              );
            }
            replayedObservationId = endResult.closingObservationId;
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
            final onboardingResult = await recordOnboardingHistory(
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
            // Logging/sync hardening: a conflict saved NOTHING for the
            // episode part — never cleared, never "onboarding complete".
            if (onboardingResult.episodeConflict) {
              throw const OnboardingEpisodeConflictException();
            }
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
          case PendingBleedingOperationType.dailyOrBackfillObservation:
            final params = operation.params;
            final observationResult = await recordObservation(
              clientOperationId: operation.operationId,
              episodeId: params['episodeId'] as String,
              observedDate: DateTime.parse(params['observedDate'] as String),
              precision: ObservationPrecision.parse(
                params['precision'] as String?,
              ),
              flow: ObservationFlow.parse(params['flow'] as String?),
              utcOffsetMinutes: params['utcOffsetMinutes'] as int,
              timezone: params['timezone'] as String?,
              symptoms: (params['symptoms'] as List<dynamic>?)?.cast<String>(),
              notes: params['notes'] as String?,
            );
            if (observationResult == null) {
              throw StateError(
                'recordObservation reconciliation did not complete — '
                'leaving pending.',
              );
            }
            replayedObservationId = observationResult;
          case PendingBleedingOperationType.correction:
            // D7: a conflict here means someone/something else already
            // superseded this exact target since it was queued — this is
            // NOT a transient failure to silently retry forever. Left
            // pending deliberately (falls through to the outer catch
            // below) so her offline-intended change is never lost; the
            // correction UI is responsible for noticing a still-pending
            // correction and offering real conflict resolution the next
            // time she opens it, rather than this reconciler silently
            // picking a winner.
            final params = operation.params;
            // A CorrectionConflictException (D7) propagates straight out
            // of this call to the outer catch below — never caught here
            // — which is exactly the desired behavior: a genuine
            // conflict must leave the operation pending for a human to
            // resolve, not be silently retried or dropped.
            final correctionResult = await correctObservation(
              clientOperationId: operation.operationId,
              supersedesId: params['supersedesId'] as String,
              observedDate: DateTime.parse(params['observedDate'] as String),
              precision: ObservationPrecision.parse(
                params['precision'] as String?,
              ),
              flow: ObservationFlow.parse(params['flow'] as String?),
              utcOffsetMinutes: params['utcOffsetMinutes'] as int,
              timezone: params['timezone'] as String?,
              symptoms: (params['symptoms'] as List<dynamic>?)?.cast<String>(),
              notes: params['notes'] as String?,
            );
            if (correctionResult == null) {
              throw StateError(
                'correctObservation reconciliation did not complete — '
                'leaving pending.',
              );
            }
            replayedObservationId = correctionResult;
            supersededObservationId = params['supersedesId'] as String?;
          case PendingBleedingOperationType.baselineEstimate:
            final params = operation.params;
            final baselineResult =
                await CycleBaselineRepositoryImpl(client: _client).saveBaseline(
                  clientOperationId: operation.operationId,
                  usualBleedingDurationDays:
                      params['usualBleedingDurationDays'] as int?,
                  usualCycleLengthDays: params['usualCycleLengthDays'] as int?,
                );
            if (baselineResult == null) {
              throw StateError(
                'saveBaseline reconciliation did not complete — leaving '
                'pending.',
              );
            }
        }
        await PendingBleedingOperationStore.clearPending(
          operation.operationId,
          userId: ownerId,
        );
        clearedAny = true;
        if (replayedObservationId != null) {
          await _projectReplayedObservation(
            replayedObservationId,
            ownerId: ownerId,
            ownerChanged: ownerChanged,
            supersededObservationId: supersededObservationId,
          );
        }
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
        // New critical finding — durable retry/category tracking is what
        // SyncState is computed from; without persisting this, "saved on
        // device, syncing" could never honestly become "needs attention"
        // no matter how many times the same operation kept failing.
        // Only if still queued: a completed-and-cleared operation (the
        // sheet's own retry finished first) must not come back.
        await PendingBleedingOperationStore.updatePendingIfQueued(
          operation.withFailure(
            _categorizeReconciliationError(error),
            attemptedAt: DateTime.now(),
          ),
          userId: ownerId,
        );
      }
      if (ownerChanged()) break;
    }
    // Only after every projection above has run, so a listener that
    // refreshes reads the fully-reconciled state.
    if (clearedAny) reconcileCompletions.value++;
  }

  /// Bumped once each time a reconcile pass durably persisted (and
  /// cleared) at least one queued operation. The reconcile runs in the
  /// background (app start/resume), completely outside any screen — the
  /// dashboard and any still-open "Saved on device — syncing" sheet listen
  /// to this so they reflect the now-synced state instead of staying
  /// stale until some unrelated action happens to refresh them.
  static final ValueNotifier<int> reconcileCompletions = ValueNotifier<int>(0);

  /// The interactive save paths mirror a new observation into the legacy
  /// `cycle_entries` read model (best effort, [CycleEntriesProjection]);
  /// a replay after an outage must do the same or the legacy consumers
  /// (Calendar, Insights, AI context) never learn the episode exists.
  /// Never authoritative and never fatal: a failure here does not undo the
  /// canonical save, exactly like the interactive path.
  ///
  /// Skipped once the signed-in user is no longer [ownerId]: the projection
  /// writes under the current session, so it must never carry the queue
  /// owner's observation into another account's history.
  Future<void> _projectReplayedObservation(
    String observationId, {
    required String ownerId,
    required bool Function() ownerChanged,
    String? supersededObservationId,
  }) async {
    if (ownerChanged()) return;
    try {
      // One row by primary key — this used to read every observation she
      // ever recorded, once per replayed operation, to pick out this one.
      final replayed = await getObservationById(observationId, userId: ownerId);
      if (replayed == null || replayed.userId != ownerId) return;
      if (ownerChanged()) return;
      final projection = CycleEntriesProjection();
      if (supersededObservationId == null) {
        await projection.project(replayed);
      } else {
        await projection.projectCorrection(
          replayed,
          supersededObservationId: supersededObservationId,
        );
      }
    } catch (_) {
      // Reported internally by the projection's own repository calls.
    }
  }

  /// New critical finding — a best-effort, conservative mapping from a
  /// reconciliation failure to a [PendingOperationFailureCategory].
  /// Deliberately separate from [_categorizeError] (that one classifies a
  /// *read* failure into [LoadErrorCategory] for an honest retry message;
  /// this one classifies a *write* failure to decide whether automatic
  /// retry is even appropriate at all).
  static PendingOperationFailureCategory _categorizeReconciliationError(
    Object error,
  ) {
    if (error is CorrectionConflictException) {
      return PendingOperationFailureCategory.correctionConflict;
    }
    // Logging/sync hardening: deterministic outcomes that re-sending the
    // same data cannot change — never auto-retried, surfaced for review.
    if (error is BleedingWriteRejectedException ||
        error is ActiveEpisodeAlreadyExistsException ||
        error is OnboardingEpisodeConflictException) {
      return PendingOperationFailureCategory.validation;
    }
    if (isTransportFailure(error)) {
      return PendingOperationFailureCategory.network;
    }
    if (error is PostgrestException) {
      final code = error.code;
      if (code == '42501' || code == 'PGRST301' || code == '401') {
        return PendingOperationFailureCategory.auth;
      }
      if (code == null) return PendingOperationFailureCategory.network;
      // Postgres constraint violations (23xxx: check/unique/foreign-key/
      // not-null) and this app's own RPC-level `RAISE EXCEPTION`
      // validations (P0001, the default SQLSTATE for a plain RAISE with
      // no explicit USING ERRCODE) are deterministic, data-shaped
      // rejections — retrying with the exact same data cannot fix them.
      if (code.startsWith('23') || code == 'P0001') {
        return PendingOperationFailureCategory.validation;
      }
      return PendingOperationFailureCategory.network;
    }
    if (error is StateError) {
      // This same method's own "no session"/"reconciliation did not
      // complete" sentinels are StateErrors — a missing session is
      // specifically an auth condition (signing back in resolves it,
      // unlike a genuine network gap).
      if (error.message.toLowerCase().contains('session')) {
        return PendingOperationFailureCategory.auth;
      }
      return PendingOperationFailureCategory.network;
    }
    return PendingOperationFailureCategory.unknown;
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
  ///
  /// Hardening 5: calls the `save_baseline_estimate` RPC — a direct
  /// client INSERT into `cycle_baselines` is no longer possible at all
  /// (every client-facing grant on that table was revoked). Idempotent:
  /// [clientOperationId] retried returns the original row's id rather
  /// than creating a second version.
  Future<String?> saveBaseline({
    required String clientOperationId,
    int? usualBleedingDurationDays,
    int? usualCycleLengthDays,
  }) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client.rpc(
        'save_baseline_estimate',
        params: {
          'p_client_operation_id': clientOperationId,
          'p_usual_bleeding_duration_days': usualBleedingDurationDays,
          'p_usual_cycle_length_days': usualCycleLengthDays,
        },
      );
      final row = (response as List).single as Map<String, dynamic>;
      return row['baseline_id'] as String?;
    } catch (error, stack) {
      BleedingEpisodeRepositoryImpl._classifyWriteFailure(
        error,
        stack,
        context: 'CycleBaselineRepositoryImpl.saveBaseline',
        recordId: clientOperationId,
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
