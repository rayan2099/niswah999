import 'package:equatable/equatable.dart';

enum PregnancyTrimester { first, second, third }

class PregnancyMilestone extends Equatable {
  const PregnancyMilestone({
    required this.id,
    required this.userId,
    required this.week,
    required this.trimester,
    required this.label,
    required this.summary,
    required this.date,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'week': week,
    'trimester': trimester.name,
    'label': label,
    'summary': summary,
    'date': date.toIso8601String(),
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
    createdAt,
    updatedAt,
  ];
}
