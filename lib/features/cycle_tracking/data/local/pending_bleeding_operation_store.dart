import 'dart:convert';

import 'package:collection/collection.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/storage/secure_local_store.dart';

/// Menstrual Data Integrity charter, PR #4 completion wave — Fix D. The
/// Start/End Bleeding sheets keep their `client_operation_id` in widget
/// State, which protects against a repeated tap while the sheet stays
/// alive — but a mobile failure can be worse than that: the request
/// reaches the server and commits, then the app process is killed before
/// the response arrives, and the sheet (with it, the operation id) is
/// gone. Without this store, the next attempt would generate a *new*
/// operation id, indistinguishable from a genuinely new request — for
/// `startEpisode` specifically, that would hit the one-open-episode
/// conflict; for other operations it could otherwise duplicate.
///
/// The fix: persist the operation id and enough of its original
/// parameters to replay it *before* ever sending the RPC. On success,
/// clear it — the server is now the durable record. On app start (or any
/// other convenient trigger), reconcile: replay every still-pending
/// operation through the exact same idempotent RPC it was headed for.
/// Because every RPC this store is used with is itself idempotent (see
/// `start_bleeding_episode`/`end_bleeding_episode`'s own doc comments),
/// replaying a call that already succeeded is always safe — it returns
/// the original result rather than erroring or duplicating.
///
/// Today's operation types (start/end/onboarding history) never persist
/// free-text health content (notes/symptoms) — only the structural fields
/// needed to replay the call. Hardening 4: as Commit D adds operation
/// types whose own replay genuinely cannot be lossless without a field
/// like `notes`/`symptoms` (a correction, say), storing it here — and
/// only here, never in SharedPreferences/debug logs/Sentry/analytics — is
/// acceptable precisely because [SecureLocalStore] is encrypted and
/// already per-user scoped; still minimize what's kept to what a retry
/// genuinely cannot reconstruct otherwise.
enum PendingBleedingOperationType {
  startEpisode,
  endEpisode,
  // PR #4 completion wave, Hardening 1: onboarding's completion is the
  // same class of failure as start/end — its RPC can commit on the
  // server before the app ever sees the response, and unlike start/end
  // (whose operation id is only ever generated once the user is already
  // mid-action on a live screen), a killed process loses onboarding's
  // *entire* widget tree, including the screen that would otherwise
  // generate a fresh (and now duplicate-risking) operation id on retry.
  onboardingHistory,
  // PR #4 final implementation wave, Commit D8/D9: the daily check-in
  // YES answer and a historical backfill are the same underlying RPC
  // (record_bleeding_observation) — one pending-operation type covers
  // both, exactly mirroring how the RPC itself does.
  dailyOrBackfillObservation,
  correction,
  baselineEstimate,
}

/// New critical finding — the three-honest-sync-states closure. Never
/// conflate a transient, still-being-retried failure with one that
/// genuinely needs her own intervention, and never differentiate them
/// on gut feel: this is the durable, structural signal
/// [PendingBleedingOperation.syncState] is computed from.
enum PendingOperationFailureCategory {
  /// No network/backend response at all — the ordinary "she's offline
  /// or the server hiccuped" case. Always safe to keep auto-retrying.
  network,

  /// The server rejected the request specifically because her session
  /// is no longer valid. Auto-retrying with the same stale credentials
  /// will not help — but signing back in and retrying will, so this is
  /// still not a dead end, just one that needs her to reauthenticate
  /// first (handled by this app's existing sign-in flow, not by this
  /// store inventing its own).
  auth,

  /// The server rejected the request's own data (a constraint the
  /// client should have already prevented but didn't) — retrying with
  /// the *same* data will deterministically fail again. Never
  /// auto-retried indefinitely; surfaced for her own review instead.
  validation,

  /// Commit D7's own conflict (`NW409`) — another correction already
  /// superseded this exact target. Never auto-resolved by picking a
  /// winner; the existing correction-conflict UI is the real resolution
  /// path, not blind retrying.
  correctionConflict,

  /// An error this store's own classification does not recognize —
  /// treated as conservatively as [network] (still retried) rather than
  /// guessed into a more specific, possibly wrong, bucket.
  unknown,
}

/// New critical finding — the three honest, user-facing sync states.
/// Never a fourth, silent "failed" state: a locally-preserved
/// observation is never allowed to simply disappear from her view of
/// what's saved.
enum SyncState {
  /// No pending operation exists for this fact at all — the server has
  /// already acknowledged it.
  savedSynced,

  /// Still queued, but every attempt so far is the ordinary, expected
  /// kind of transient gap (offline, a hiccup) — no reason yet to worry
  /// her with anything beyond "still syncing."
  savedSyncing,

  /// Queued, and either it has failed enough consecutive transient
  /// attempts to stop being "still syncing" as a comforting default, or
  /// the failure itself is structurally never going to resolve by
  /// simply trying again (a validation rejection or a correction
  /// conflict). The data is still safely on the device either way —
  /// this state is about visibility and an actionable next step, never
  /// about data loss.
  needsAttention,
}

class PendingBleedingOperation {
  const PendingBleedingOperation({
    required this.operationId,
    required this.type,
    required this.params,
    required this.createdAt,
    this.retryCount = 0,
    this.lastFailureCategory,
    this.lastAttemptAt,
  });

  final String operationId;
  final PendingBleedingOperationType type;
  final Map<String, dynamic> params;
  final DateTime createdAt;

  /// New critical finding — how many consecutive reconciliation
  /// attempts have failed for this exact operation id. Never resets
  /// except by a fresh, successful attempt (which clears the pending
  /// operation entirely — there is nothing left to carry a count on).
  final int retryCount;

  /// The most recent failure's category, or null if this has never
  /// failed yet (still on its very first attempt) or the last attempt
  /// actually succeeded (in which case it would already be cleared, not
  /// sitting here at all).
  final PendingOperationFailureCategory? lastFailureCategory;

  /// When the most recent (successful-or-not) reconciliation attempt
  /// was made — structural metadata only, shown to her as "still trying"
  /// vs. "needs attention," never as health content.
  final DateTime? lastAttemptAt;

  /// New critical finding — retryCount ≥ this many consecutive failures
  /// of an otherwise-recoverable category (network/auth/unknown) is
  /// itself enough to stop calling it "still syncing" and surface it —
  /// still safely queued, still being retried, but no longer a
  /// comforting assumption that it'll resolve any moment now.
  static const _attentionRetryThreshold = 3;

  SyncState get syncState {
    final category = lastFailureCategory;
    if (category == null) return SyncState.savedSyncing;
    if (category == PendingOperationFailureCategory.validation ||
        category == PendingOperationFailureCategory.correctionConflict) {
      // New critical finding — never labeled "still syncing": trying
      // again with unchanged data cannot fix either of these; she needs
      // to know now, not after a threshold of silently-repeated retries.
      return SyncState.needsAttention;
    }
    return retryCount >= _attentionRetryThreshold
        ? SyncState.needsAttention
        : SyncState.savedSyncing;
  }

  /// New critical finding — "do not retry invalid operations
  /// indefinitely": a [PendingOperationFailureCategory.validation]
  /// failure will deterministically repeat with unchanged data, so
  /// automatic (unattended) reconciliation must not keep attempting it
  /// forever — only an explicit, informed manual retry should. A
  /// [PendingOperationFailureCategory.correctionConflict] is likewise
  /// never auto-resolved by blind retrying (that would just conflict
  /// again) — the existing correction-conflict UI is its real
  /// resolution path.
  bool get eligibleForAutomaticRetry {
    final category = lastFailureCategory;
    return category != PendingOperationFailureCategory.validation &&
        category != PendingOperationFailureCategory.correctionConflict;
  }

  PendingBleedingOperation withFailure(
    PendingOperationFailureCategory category, {
    required DateTime attemptedAt,
  }) => PendingBleedingOperation(
    operationId: operationId,
    type: type,
    params: params,
    createdAt: createdAt,
    retryCount: retryCount + 1,
    lastFailureCategory: category,
    lastAttemptAt: attemptedAt,
  );

  Map<String, dynamic> toJson() => {
    'operation_id': operationId,
    'type': type.name,
    'params': params,
    'created_at': createdAt.toIso8601String(),
    'retry_count': retryCount,
    if (lastFailureCategory != null)
      'last_failure_category': lastFailureCategory!.name,
    if (lastAttemptAt != null)
      'last_attempt_at': lastAttemptAt!.toIso8601String(),
  };

  static PendingBleedingOperation? tryFromJson(Map<String, dynamic> json) {
    final operationId = json['operation_id'] as String?;
    final rawType = json['type'] as String?;
    final type = PendingBleedingOperationType.values.firstWhereOrNull(
      (value) => value.name == rawType,
    );
    final params = json['params'] as Map<String, dynamic>?;
    final createdAt = json['created_at'] == null
        ? null
        : DateTime.tryParse(json['created_at'] as String);
    if (operationId == null ||
        type == null ||
        params == null ||
        createdAt == null) {
      // Quarantine, not crash — a malformed local record here must never
      // block every other pending operation from reconciling.
      return null;
    }
    // New critical finding — retry-tracking fields are additive and
    // never required: a record persisted before this finding's own
    // change (or one otherwise missing them) is still perfectly valid,
    // defaulting honestly to "never failed yet" rather than being
    // quarantined over a genuinely optional field.
    final retryCount = json['retry_count'] as int? ?? 0;
    final lastFailureCategory = PendingOperationFailureCategory.values
        .firstWhereOrNull(
          (value) => value.name == json['last_failure_category'] as String?,
        );
    final lastAttemptAt = json['last_attempt_at'] == null
        ? null
        : DateTime.tryParse(json['last_attempt_at'] as String);
    return PendingBleedingOperation(
      operationId: operationId,
      type: type,
      params: params,
      createdAt: createdAt,
      retryCount: retryCount,
      lastFailureCategory: lastFailureCategory,
      lastAttemptAt: lastAttemptAt,
    );
  }
}

class PendingBleedingOperationStore {
  PendingBleedingOperationStore._();

  static const _category = 'cycle_tracking_pending_bleeding_operations';

  /// Must be called, and awaited, *before* the RPC it describes is ever
  /// sent — the whole point is to survive a process death between "the
  /// server received this" and "the app saw the response."
  static Future<void> savePending(PendingBleedingOperation operation) async {
    final existing = await loadPending();
    final updated = <String, PendingBleedingOperation>{
      for (final op in existing) op.operationId: op,
    };
    updated[operation.operationId] = operation;
    await SecureLocalStore.write(
      _category,
      jsonEncode(updated.values.map((op) => op.toJson()).toList()),
    );
  }

  /// The one pending operation of [type], if any — onboarding's
  /// completion is a single logical action per account, so "is there
  /// already a pending one to resume" is a more natural question than
  /// working with the full list (Hardening 1).
  static Future<PendingBleedingOperation?> getPendingByType(
    PendingBleedingOperationType type,
  ) async {
    final existing = await loadPending();
    for (final op in existing) {
      if (op.type == type) return op;
    }
    return null;
  }

  static Future<void> clearPending(String operationId) async {
    final existing = await loadPending();
    final remaining = existing
        .where((op) => op.operationId != operationId)
        .toList();
    await SecureLocalStore.write(
      _category,
      jsonEncode(remaining.map((op) => op.toJson()).toList()),
    );
  }

  /// Closure Blocker 11 — every failure mode below is quarantined, never
  /// thrown: a `jsonDecode` failure (malformed outer JSON), a top-level
  /// value that isn't a list at all (wrong shape — e.g. a stray JSON
  /// object), and any individual list element that isn't a JSON object
  /// (or fails [PendingBleedingOperation.tryFromJson]'s own field-level
  /// validation) must never abort every *other*, genuinely valid pending
  /// operation's ability to reconcile. The old cast inside
  /// `decoded.map((item) => ...(item as Map&lt;String, dynamic&gt;)...)`
  /// threw as soon as the lazy map hit one non-Map element — losing every
  /// operation after it
  /// (and, once materialized via `.toList()`, discarding the ones before
  /// it too, since the whole expression never produced a result). Never
  /// fabricates a replacement for a quarantined item — it is simply
  /// dropped, reported for visibility, and the remaining valid operations
  /// still reconcile normally.
  static Future<List<PendingBleedingOperation>> loadPending() async {
    final raw = await SecureLocalStore.read(_category);
    if (raw == null || raw.isEmpty) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'PendingBleedingOperationStore.loadPending — malformed outer JSON, quarantined',
      );
      return const [];
    }

    if (decoded is! List) {
      AppErrorReporter.report(
        StateError(
          'pending operations store held a non-list top-level value '
          '(${decoded.runtimeType}) — quarantined',
        ),
        StackTrace.current,
        context: 'PendingBleedingOperationStore.loadPending',
      );
      return const [];
    }

    final operations = <PendingBleedingOperation>[];
    var quarantinedCount = 0;
    for (final item in decoded) {
      final parsed = item is Map<String, dynamic>
          ? PendingBleedingOperation.tryFromJson(item)
          : null;
      if (parsed == null) {
        quarantinedCount++;
        continue;
      }
      operations.add(parsed);
    }

    if (quarantinedCount > 0) {
      AppErrorReporter.report(
        StateError(
          '$quarantinedCount malformed pending operation(s) quarantined '
          'out of ${decoded.length} total',
        ),
        StackTrace.current,
        context: 'PendingBleedingOperationStore.loadPending',
      );
    }

    return operations;
  }
}
