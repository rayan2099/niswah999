import '../entities/private_conversation.dart';
import '../entities/private_message.dart';

/// Abstraction over the private messaging data source so view models and
/// widgets can be tested with fakes.
abstract class PrivateMessagingRepositoryBase {
  Future<List<PrivateConversation>> fetchConversations();

  Future<List<PrivateMessage>> fetchMessages(String conversationId);

  Future<PrivateConversation> getOrCreateConversation(
    String currentUserId,
    String otherUserId,
  );

  /// [messageId], when supplied, must be a stable id generated once by the
  /// caller — retrying this call with the same [messageId] safely upserts
  /// the same row instead of creating a duplicate message. Falls back to
  /// a fresh id if omitted.
  Future<PrivateMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    String? messageId,
  });

  Future<void> markMessagesAsRead({
    required String conversationId,
    required String readerId,
  });

  /// Returns the total number of unread messages sent by other users
  /// across all of the current user's conversations.
  Future<int> fetchUnreadCount();
}
