class CycleLog {
  final String id;
  final String userId;
  final DateTime startDate;
  final DateTime? endDate;
  final String? bleedingIntensity;
  final String? notes;
  final DateTime createdAt;

  CycleLog({
    required this.id,
    required this.userId,
    required this.startDate,
    this.endDate,
    this.bleedingIntensity,
    this.notes,
    required this.createdAt,
  });

  factory CycleLog.fromJson(Map<String, dynamic> json) {
    return CycleLog(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      bleedingIntensity: json['bleeding_intensity'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'start_date': startDate
          .toIso8601String()
          .split('T')
          .first, // Only date part
      'end_date': endDate?.toIso8601String().split('T').first, // Only date part
      'bleeding_intensity': bleedingIntensity,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  CycleLog copyWith({
    String? id,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    String? bleedingIntensity,
    String? notes,
    DateTime? createdAt,
  }) {
    return CycleLog(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      bleedingIntensity: bleedingIntensity ?? this.bleedingIntensity,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
