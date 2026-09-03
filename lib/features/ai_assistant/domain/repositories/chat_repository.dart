import '../entities/chat_message.dart';
import '../entities/chat_thread.dart';

abstract class ChatRepository {
  Future<List<ChatThread>> getThreads({required String userId});

  Future<ChatThread> createThread({
    required String userId,
    required ChatThreadType threadType,
    String? title,
    Map<String, dynamic>? metadata,
  });

  Future<List<ChatMessage>> getMessages({
    required String threadId,
    required String userId,
  });

  Future<ChatMessage> sendMessage({
    required String threadId,
    required String userId,
    required ChatRole role,
    required String content,
    Map<String, dynamic>? metadata,
  });

  Future<void> deleteThread({required String threadId, required String userId});
}
