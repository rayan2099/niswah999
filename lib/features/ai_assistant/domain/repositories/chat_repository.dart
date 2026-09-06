import '../entities/chat_message.dart';
import '../entities/chat_thread.dart';

abstract class ChatRepository {
  Future<List<ChatThread>> getThreads({required String userId});

  /// [threadId], when supplied, must be a stable id generated once by the
  /// caller — same idempotency reasoning as [sendMessage]'s `messageId`.
  Future<ChatThread> createThread({
    required String userId,
    required ChatThreadType threadType,
    String? title,
    Map<String, dynamic>? metadata,
    String? threadId,
  });

  Future<List<ChatMessage>> getMessages({
    required String threadId,
    required String userId,
  });

  /// [messageId], when supplied, must be a stable id generated once by the
  /// caller — retrying this call with the same [messageId] safely upserts
  /// the same row instead of creating a duplicate message. Falls back to
  /// a fresh id if omitted.
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String userId,
    required ChatRole role,
    required String content,
    Map<String, dynamic>? metadata,
    String? messageId,
  });

  Future<void> deleteThread({required String threadId, required String userId});
}
