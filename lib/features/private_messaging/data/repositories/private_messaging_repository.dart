import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/private_messaging_repository_base.dart';
import '../../domain/entities/private_conversation.dart';
import '../../domain/entities/private_message.dart';

/// Repository for private 1:1 direct messaging backed by Supabase.
///
/// RLS on `private_conversations` / `private_messages` guarantees users can
/// only read and write rows where they are active participants.
class PrivateMessagingRepository implements PrivateMessagingRepositoryBase {
  final SupabaseClient _client;

  PrivateMessagingRepository(this._client);

  String get _currentUserId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Private messaging requires an authenticated user.');
    }
    return user.id;
  }

  /// Fetches all conversations the current user participates in,
  /// most recently updated first.
  @override
  Future<List<PrivateConversation>> fetchConversations() async {
    try {
      final uid = _currentUserId;
      final response = await _client
          .from('private_conversations')
          .select()
          .or('participant_one.eq.$uid,participant_two.eq.$uid')
          .order('updated_at', ascending: false);
      return (response as List)
          .map((json) => PrivateConversation.fromJson(json))
          .toList();
    } on PostgrestException catch (e) {
      throw PrivateMessagingException(
        'Failed to load conversations: ${e.message}',
      );
    }
  }

  /// Fetches messages for a conversation, oldest first.
  @override
  Future<List<PrivateMessage>> fetchMessages(String conversationId) async {
    try {
      final response = await _client
          .from('private_messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);
      return (response as List)
          .map((json) => PrivateMessage.fromJson(json))
          .toList();
    } on PostgrestException catch (e) {
      throw PrivateMessagingException('Failed to load messages: ${e.message}');
    }
  }

  /// Finds an existing conversation between [currentUserId] and
  /// [otherUserId], or creates one if none exists.
  @override
  Future<PrivateConversation> getOrCreateConversation(
    String currentUserId,
    String otherUserId,
  ) async {
    if (currentUserId == otherUserId) {
      throw ArgumentError('Cannot start a conversation with yourself.');
    }
    try {
      final existing = await _client
          .from('private_conversations')
          .select()
          .or(
            'and(participant_one.eq.$currentUserId,participant_two.eq.$otherUserId),'
            'and(participant_one.eq.$otherUserId,participant_two.eq.$currentUserId)',
          )
          .maybeSingle();
      if (existing != null) {
        return PrivateConversation.fromJson(existing);
      }
      final inserted = await _client
          .from('private_conversations')
          .insert({
            'participant_one': currentUserId,
            'participant_two': otherUserId,
          })
          .select()
          .single();
      return PrivateConversation.fromJson(inserted);
    } on PostgrestException catch (e) {
      throw PrivateMessagingException(
        'Failed to open conversation: ${e.message}',
      );
    }
  }

  /// Sends a message in a conversation. Returns the stored message.
  @override
  Future<PrivateMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Message content cannot be empty.');
    }
    try {
      final response = await _client
          .from('private_messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': senderId,
            'content': trimmed,
          })
          .select()
          .single();
      return PrivateMessage.fromJson(response);
    } on PostgrestException catch (e) {
      throw PrivateMessagingException('Failed to send message: ${e.message}');
    }
  }

  /// Marks all unread messages sent by the other participant as read.
  @override
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String readerId,
  }) async {
    try {
      await _client
          .from('private_messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .eq('is_read', false)
          .neq('sender_id', readerId);
    } on PostgrestException catch (e) {
      throw PrivateMessagingException(
        'Failed to mark messages read: ${e.message}',
      );
    }
  }

  /// Counts unread messages sent by other users across all of the
  /// current user's conversations.
  @override
  Future<int> fetchUnreadCount() async {
    try {
      final uid = _currentUserId;
      final response = await _client
          .from('private_messages')
          .select('id')
          .eq('is_read', false)
          .neq('sender_id', uid);
      return (response as List).length;
    } on PostgrestException catch (e) {
      throw PrivateMessagingException(
        'Failed to count unread messages: ${e.message}',
      );
    }
  }

  /// Subscribes to new messages for a conversation via Supabase Realtime.
  /// Returns a function that cancels the subscription.
  void Function() subscribeToMessages(
    String conversationId,
    void Function(PrivateMessage message) onNewMessage,
  ) {
    final channel = _client
        .channel('private-messages-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'private_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) {
              onNewMessage(PrivateMessage.fromJson(record));
            }
          },
        )
        .subscribe();
    return () async => _client.removeChannel(channel);
  }
}

class PrivateMessagingException implements Exception {
  final String message;
  const PrivateMessagingException(this.message);

  @override
  String toString() => 'PrivateMessagingException: $message';
}
