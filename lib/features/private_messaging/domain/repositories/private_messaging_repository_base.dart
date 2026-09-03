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

  Future<PrivateMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
  });

  Future<void> markMessagesAsRead({
    required String conversationId,
    required String readerId,
  });

  /// Returns the total number of unread messages sent by other users
  /// across all of the current user's conversations.
  Future<int> fetchUnreadCount();
}
