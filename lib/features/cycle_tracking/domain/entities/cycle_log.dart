import 'package:equatable/equatable.dart';

enum CyclePhase { menstrual, follicular, ovulation, luteal }

enum FlowLevel { none, spotting, light, medium, heavy }

class CycleLog extends Equatable {
  const CycleLog({
    required this.id,
    required this.userId,
    required this.date,
    required this.flow,
    this.notes,
    this.cycleDay = 1,
    this.symptoms = const <String>[],
    this.syncStatus = SyncStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final DateTime date;
  final FlowLevel flow;
  final String? notes;
  final int cycleDay;
  final List<String> symptoms;
  final SyncStatus syncStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CycleLog copyWith({
    String? id,
    String? userId,
    DateTime? date,
    FlowLevel? flow,
    String? notes,
    int? cycleDay,
    List<String>? symptoms,
    SyncStatus? syncStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CycleLog(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      flow: flow ?? this.flow,
      notes: notes ?? this.notes,
      cycleDay: cycleDay ?? this.cycleDay,
      symptoms: symptoms ?? this.symptoms,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'date': date.toIso8601String(),
      'time_logged': (updatedAt ?? createdAt ?? DateTime.now())
          .toIso8601String(),
      'flow': flow.name,
      'notes': notes,
      'cycle_day': cycleDay,
      'symptoms': symptoms,
      'sync_status': syncStatus.name,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory CycleLog.fromJson(Map<String, dynamic> json) {
    return CycleLog(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      flow: FlowLevel.values.firstWhere(
        (value) => value.name == (json['flow'] as String? ?? 'light'),
        orElse: () => FlowLevel.light,
      ),
      notes: json['notes'] as String?,
      cycleDay: json['cycle_day'] as int? ?? 1,
      symptoms: (json['symptoms'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      syncStatus: SyncStatus.values.firstWhere(
        (value) => value.name == (json['sync_status'] as String? ?? 'pending'),
        orElse: () => SyncStatus.pending,
      ),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    date,
    flow,
    notes,
    cycleDay,
    symptoms,
    syncStatus,
    createdAt,
    updatedAt,
  ];
}

enum SyncStatus { pending, synced, failed }

class CycleTrackingSummary extends Equatable {
  const CycleTrackingSummary({
    required this.averageCycleLength,
    required this.averagePeriodLength,
    required this.lastCycleStart,
    required this.currentPhase,
    required this.fertileWindow,
    this.nextPeriodStart,
    this.hasPlausibleAverage = false,
  });

  final int? averageCycleLength;
  final int? averagePeriodLength;
  final DateTime? lastCycleStart;
  final CyclePhase currentPhase;
  final FertileWindow fertileWindow;

  /// Predicted start of the next period, rolled forward past [DateTime]s
  /// that have already elapsed — never a date in the past relative to the
  /// `now` given to [CycleTrackingController.summarizeHistory].
  final DateTime? nextPeriodStart;

  /// Mirrors [CycleCalculationResult.hasPlausibleAverage] — [averageCycleLength]
  /// is deliberately left ungated above (Haid/Tahara day-tallies and fiqh
  /// classification stay valid even on a degenerate average), but any
  /// *forward projection* built from it (an "Expected Haid" pattern drawn
  /// on a calendar, say) must check this first or a tiny average (e.g. 2
  /// days, from two Haid starts logged close together) repeats every
  /// couple of days instead of producing one real block per cycle.
  final bool hasPlausibleAverage;

  @override
  List<Object?> get props => [
    averageCycleLength,
    averagePeriodLength,
    lastCycleStart,
    currentPhase,
    fertileWindow,
    nextPeriodStart,
    hasPlausibleAverage,
  ];
}

class FertileWindow extends Equatable {
  const FertileWindow({
    required this.start,
    required this.end,
    required this.peakDay,
  });

  final DateTime? start;
  final DateTime? end;
  final DateTime? peakDay;

  @override
  List<Object?> get props => [start, end, peakDay];
}
