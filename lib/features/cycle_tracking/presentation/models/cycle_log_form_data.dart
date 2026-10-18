import 'dart:math';

import '../../../../core/utils/app_clock.dart';
import '../../domain/entities/cycle_log.dart';

String _generateLogId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

class CycleLogFormData {
  const CycleLogFormData({
    required this.flow,
    required this.cycleDay,
    this.date,
    this.notes,
    this.symptoms = const <String>[],
  });

  final DateTime? date;
  final FlowLevel flow;
  final int cycleDay;
  final String? notes;
  final List<String> symptoms;

  String? validate() {
    if (date == null) {
      return 'Please select a date for this log.';
    }

    if (cycleDay < 1 || cycleDay > 40) {
      return 'Cycle day must be between 1 and 40.';
    }

    if (notes != null && notes!.trim().length > 250) {
      return 'Notes should stay under 250 characters.';
    }

    return null;
  }

  /// [dataProvenance] — Logging/sync hardening (proposed): an edit of an
  /// existing row carries that row's own provenance forward unchanged
  /// (docs/menstrual-data-integrity-contract.md §5: a `legacy_unverified`
  /// row must never be silently re-declared `user_observed`). A brand-new
  /// manual log is classified by its own date per the §1 taxonomy: a day
  /// before [today] is reported after the fact — `user_reported_historical`
  /// — and only a same-day report is `user_observed`.
  CycleLog toCycleLog({
    required String userId,
    String? id,
    CycleEntryProvenance? dataProvenance,
    DateTime? today,
  }) {
    final resolvedDate = date ?? AppClock.now();
    final resolvedId = id ?? _generateLogId();
    final now = today ?? AppClock.now();
    final localToday = DateTime(now.year, now.month, now.day);
    final day = DateTime(
      resolvedDate.year,
      resolvedDate.month,
      resolvedDate.day,
    );
    final provenance =
        dataProvenance ??
        (day.isBefore(localToday)
            ? CycleEntryProvenance.userReportedHistorical
            : CycleEntryProvenance.userObserved);

    return CycleLog(
      id: resolvedId,
      userId: userId,
      date: resolvedDate,
      flow: flow,
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      cycleDay: cycleDay,
      symptoms: symptoms,
      syncStatus: SyncStatus.pending,
      dataProvenance: provenance,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
