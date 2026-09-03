import 'package:equatable/equatable.dart';

enum DreamMood { peaceful, anxious, joyful, mysterious, fearful }

class DreamEntry extends Equatable {
  const DreamEntry({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.mood,
    required this.tags,
    required this.createdAt,
    this.interpretation,
    this.rating,
  });

  final String id;
  final String userId;
  final String title;
  final String description;
  final DreamMood mood;
  final List<String> tags;
  final DateTime createdAt;
  final String? interpretation;
  final int? rating;

  DreamEntry copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    DreamMood? mood,
    List<String>? tags,
    DateTime? createdAt,
    String? interpretation,
    int? rating,
  }) {
    return DreamEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      interpretation: interpretation ?? this.interpretation,
      rating: rating ?? this.rating,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'title': title,
    'description': description,
    'mood': mood.name,
    'tags': tags,
    'created_at': createdAt.toIso8601String(),
    'interpretation': interpretation,
    'rating': rating,
  };

  factory DreamEntry.fromJson(Map<String, dynamic> json) {
    return DreamEntry(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      mood: DreamMood.values.firstWhere(
        (mood) => mood.name == (json['mood'] as String? ?? 'mysterious'),
        orElse: () => DreamMood.mysterious,
      ),
      tags: List<String>.from(json['tags'] as List? ?? const <String>[]),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      interpretation: json['interpretation'] as String?,
      rating: json['rating'] as int?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    title,
    description,
    mood,
    tags,
    createdAt,
    interpretation,
    rating,
  ];
}
