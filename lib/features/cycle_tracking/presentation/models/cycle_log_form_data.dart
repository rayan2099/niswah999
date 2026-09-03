import 'dart:math';

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

  CycleLog toCycleLog({required String userId, String? id}) {
    final resolvedDate = date ?? DateTime.now();
    final resolvedId = id ?? _generateLogId();

    return CycleLog(
      id: resolvedId,
      userId: userId,
      date: resolvedDate,
      flow: flow,
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      cycleDay: cycleDay,
      symptoms: symptoms,
      syncStatus: SyncStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
