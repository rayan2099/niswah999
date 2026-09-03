import 'package:equatable/equatable.dart';

enum ChatThreadType { drNiswah, dreamInterpreter, general, fiqhAdvisory }

enum ChatThreadStatus { active, archived, deleted }

class ChatThread extends Equatable {
  const ChatThread({
    required this.id,
    required this.userId,
    required this.title,
    required this.threadType,
    required this.status,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String title;
  final ChatThreadType threadType;
  final ChatThreadStatus status;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'title': title,
    'thread_type': threadType.name,
    'status': status.name,
    'metadata': metadata,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    return ChatThread(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'New conversation',
      threadType: ChatThreadType.values.firstWhere(
        (type) => type.name == (json['thread_type'] as String? ?? 'drNiswah'),
        orElse: () => ChatThreadType.drNiswah,
      ),
      status: ChatThreadStatus.values.firstWhere(
        (status) => status.name == (json['status'] as String? ?? 'active'),
        orElse: () => ChatThreadStatus.active,
      ),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    title,
    threadType,
    status,
    metadata,
    createdAt,
    updatedAt,
  ];
}
