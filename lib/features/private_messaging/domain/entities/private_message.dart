/// A single message inside a private conversation.
class PrivateMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final bool isRead;
  final DateTime createdAt;

  const PrivateMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.isRead,
    required this.createdAt,
  });

  factory PrivateMessage.fromJson(Map<String, dynamic> json) {
    return PrivateMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      isRead: (json['is_read'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  PrivateMessage copyWith({bool? isRead}) => PrivateMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    content: content,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'content': content,
    'is_read': isRead,
    'created_at': createdAt.toIso8601String(),
  };
}
