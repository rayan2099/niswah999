import 'package:equatable/equatable.dart';

enum PregnancyTrimester { first, second, third }

/// Local-authoritative-with-sync, mirroring CycleLog's SyncStatus (see
/// cycle_log.dart) — same three-state design, named distinctly to avoid a
/// same-name import collision if a future file imports both entities.
/// `pending`: saved locally, not yet confirmed on the server. `synced`:
/// confirmed written to `pregnancy_milestones`. `failed`: a non-retryable
/// remote rejection — will not be retried automatically (see
/// PregnancyTrackingRepositoryImpl.syncPendingMilestones).
enum PregnancySyncStatus { pending, synced, failed }

class PregnancyMilestone extends Equatable {
  const PregnancyMilestone({
    required this.id,
    required this.userId,
    required this.week,
    required this.trimester,
    required this.label,
    required this.summary,
    required this.date,
    this.syncStatus = PregnancySyncStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final int week;
  final PregnancyTrimester trimester;
  final String label;
  final String summary;
  final DateTime date;
  final PregnancySyncStatus syncStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PregnancyMilestone copyWith({
    String? id,
    String? userId,
    int? week,
    PregnancyTrimester? trimester,
    String? label,
    String? summary,
    DateTime? date,
    PregnancySyncStatus? syncStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PregnancyMilestone(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      week: week ?? this.week,
      trimester: trimester ?? this.trimester,
      label: label ?? this.label,
      summary: summary ?? this.summary,
      date: date ?? this.date,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Payload for local storage — includes syncStatus, since the local copy
  /// needs to remember it. Remote writes use [toRemoteJson] instead, which
  /// omits it (the server always reflects "synced" simply by having the
  /// row present — see PregnancyTrackingRepositoryImpl.upsertMilestone).
  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'week': week,
    'trimester': trimester.name,
    'label': label,
    'summary': summary,
    'date': date.toIso8601String(),
    'sync_status': syncStatus.name,
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  /// Payload for the `pregnancy_milestones` table — a DATE column, not a
  /// full timestamp (matches the migration's `date DATE NOT NULL`).
  Map<String, dynamic> toRemoteJson() => {
    'id': id,
    'user_id': userId,
    'week': week,
    'trimester': trimester.name,
    'label': label,
    'summary': summary,
    'date': date.toIso8601String().substring(0, 10),
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory PregnancyMilestone.fromJson(Map<String, dynamic> json) {
    return PregnancyMilestone(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      week: json['week'] as int? ?? 0,
      trimester: PregnancyTrimester.values.firstWhere(
        (value) => value.name == (json['trimester'] as String? ?? 'first'),
        orElse: () => PregnancyTrimester.first,
      ),
      label: json['label'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      syncStatus: PregnancySyncStatus.values.firstWhere(
        (value) => value.name == (json['sync_status'] as String? ?? 'synced'),
        orElse: () => PregnancySyncStatus.synced,
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
    week,
    trimester,
    label,
    summary,
    date,
    syncStatus,
    createdAt,
    updatedAt,
  ];
}
