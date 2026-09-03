import 'package:equatable/equatable.dart';

/// One day's mood/energy/sleep check-in. Maps 1:1 to the `wellbeing_logs`
/// table (one row per user per day). All three ratings use the same 1-5
/// scale as the dashboard check-in UI (1 = very sad/exhausted/insomnia,
/// 5 = excellent/peak energy/perfect sleep).
class WellbeingLog extends Equatable {
  const WellbeingLog({
    required this.id,
    required this.userId,
    required this.logDate,
    required this.mood,
    required this.energy,
    required this.sleep,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final DateTime logDate;
  final int mood;
  final int energy;
  final int sleep;

  /// Optional free-text note for the day — null/empty when nothing was
  /// written, never a fabricated placeholder.
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static String _dateOnly(DateTime date) =>
      date.toIso8601String().substring(0, 10);

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'log_date': _dateOnly(logDate),
    'mood': mood,
    'energy': energy,
    'sleep': sleep,
    'notes': notes,
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory WellbeingLog.fromJson(Map<String, dynamic> json) {
    return WellbeingLog(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      logDate:
          DateTime.tryParse(json['log_date'] as String? ?? '') ??
          DateTime.now(),
      mood: json['mood'] as int? ?? 3,
      energy: json['energy'] as int? ?? 3,
      sleep: json['sleep'] as int? ?? 3,
      notes: json['notes'] as String?,
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
    logDate,
    mood,
    energy,
    sleep,
    notes,
    createdAt,
    updatedAt,
  ];
}
