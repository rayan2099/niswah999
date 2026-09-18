import 'dart:convert';

import 'package:collection/collection.dart';

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
}

class PendingBleedingOperation {
  const PendingBleedingOperation({
    required this.operationId,
    required this.type,
    required this.params,
    required this.createdAt,
  });

  final String operationId;
  final PendingBleedingOperationType type;
  final Map<String, dynamic> params;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'operation_id': operationId,
    'type': type.name,
    'params': params,
    'created_at': createdAt.toIso8601String(),
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
    return PendingBleedingOperation(
      operationId: operationId,
      type: type,
      params: params,
      createdAt: createdAt,
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

  static Future<List<PendingBleedingOperation>> loadPending() async {
    final raw = await SecureLocalStore.read(_category);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) => PendingBleedingOperation.tryFromJson(
            item as Map<String, dynamic>,
          ),
        )
        .whereType<PendingBleedingOperation>()
        .toList();
  }
}
