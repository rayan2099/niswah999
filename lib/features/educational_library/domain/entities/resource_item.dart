import 'package:equatable/equatable.dart';

enum ResourceCategory { health, fiqh, family, wellness, spouse }

class ResourceItem extends Equatable {
  const ResourceItem({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.content,
    required this.author,
    required this.readMinutes,
    required this.tags,
    required this.isSpouseGuide,
    required this.createdAt,
  });

  final String id;
  final ResourceCategory category;
  final String title;
  final String summary;
  final String content;
  final String author;
  final int readMinutes;
  final List<String> tags;
  final bool isSpouseGuide;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.name,
    'title': title,
    'summary': summary,
    'content': content,
    'author': author,
    'read_minutes': readMinutes,
    'tags': tags,
    'is_spouse_guide': isSpouseGuide,
    'created_at': createdAt.toIso8601String(),
  };

  factory ResourceItem.fromJson(Map<String, dynamic> json) {
    return ResourceItem(
      id: json['id'] as String? ?? '',
      category: ResourceCategory.values.firstWhere(
        (category) =>
            category.name == (json['category'] as String? ?? 'health'),
        orElse: () => ResourceCategory.health,
      ),
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      content: json['content'] as String? ?? '',
      author: json['author'] as String? ?? 'Niswah Team',
      readMinutes: json['read_minutes'] as int? ?? 4,
      tags: List<String>.from(json['tags'] as List? ?? const <String>[]),
      isSpouseGuide: json['is_spouse_guide'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    category,
    title,
    summary,
    content,
    author,
    readMinutes,
    tags,
    isSpouseGuide,
    createdAt,
  ];
}
