import 'package:equatable/equatable.dart';

enum ChatRole { user, assistant, system }

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.userId,
    required this.role,
    required this.content,
    required this.metadata,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final String userId;
  final ChatRole role;
  final String content;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'thread_id': threadId,
    'user_id': userId,
    'role': role.name,
    'content': content,
    'metadata': metadata,
    'created_at': createdAt.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      threadId: json['thread_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      role: ChatRole.values.firstWhere(
        (role) => role.name == (json['role'] as String? ?? 'user'),
        orElse: () => ChatRole.user,
      ),
      content: json['content'] as String? ?? '',
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    threadId,
    userId,
    role,
    content,
    metadata,
    createdAt,
  ];
}
