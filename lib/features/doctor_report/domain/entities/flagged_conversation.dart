import 'package:equatable/equatable.dart';

/// A red-flag chat message the dr-niswah-chat edge function already
/// detected and logged to `flagged_conversations` — surfaced here
/// read-only so the Doctor's Report can list recent urgent concerns.
class FlaggedConversation extends Equatable {
  const FlaggedConversation({
    required this.id,
    required this.threadId,
    required this.messageExcerpt,
    required this.matchedCategories,
    required this.createdAt,
  });

  final String id;
  final String? threadId;
  final String messageExcerpt;
  final List<String> matchedCategories;
  final DateTime createdAt;

  factory FlaggedConversation.fromJson(Map<String, dynamic> json) {
    return FlaggedConversation(
      id: json['id'] as String? ?? '',
      threadId: json['thread_id'] as String?,
      messageExcerpt: json['message_excerpt'] as String? ?? '',
      matchedCategories:
          (json['matched_categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    threadId,
    messageExcerpt,
    matchedCategories,
    createdAt,
  ];
}
