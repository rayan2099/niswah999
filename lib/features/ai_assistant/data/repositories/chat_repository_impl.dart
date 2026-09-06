import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  @override
  Future<List<ChatThread>> getThreads({required String userId}) async {
    final client = _client;
    if (client == null) {
      return const [];
    }

    try {
      final response = await client
          .from('chat_threads')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      final mapped = (response as List<dynamic>)
          .map((item) => ChatThread.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      return mapped;
    } on PostgrestException {
      return const [];
    }
  }

  @override
  Future<ChatThread> createThread({
    required String userId,
    required ChatThreadType threadType,
    String? title,
    Map<String, dynamic>? metadata,
    String? threadId,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not initialized.');
    }

    final createdAt = DateTime.now();
    final payload = {
      'id': threadId ?? const Uuid().v4(),
      'user_id': userId,
      'title': title ?? 'New conversation',
      'thread_type': threadType.name,
      'status': ChatThreadStatus.active.name,
      'metadata': metadata ?? const <String, dynamic>{},
      'created_at': createdAt.toIso8601String(),
      'updated_at': createdAt.toIso8601String(),
    };

    final response = await client
        .from('chat_threads')
        .upsert(payload)
        .select()
        .single();
    return ChatThread.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<List<ChatMessage>> getMessages({
    required String threadId,
    required String userId,
  }) async {
    final client = _client;
    if (client == null) {
      return const [];
    }

    try {
      final response = await client
          .from('chat_messages')
          .select()
          .eq('thread_id', threadId)
          .eq('user_id', userId)
          .order('created_at', ascending: true);

      return (response as List<dynamic>)
          .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on PostgrestException {
      return const [];
    }
  }

  @override
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String userId,
    required ChatRole role,
    required String content,
    Map<String, dynamic>? metadata,
    String? messageId,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not initialized.');
    }

    // A caller-supplied, stable id (see ChatViewModel's
    // `_persistUserMessage`/`_showAssistantReplyAndPersist`) makes this
    // upsert-safe under retry, matching the pattern already used by
    // dream_entries/community_posts — a retry after a client-side timeout
    // no-ops or genuinely creates the row, never duplicates it.
    final payload = {
      'id': messageId ?? const Uuid().v4(),
      'thread_id': threadId,
      'user_id': userId,
      'role': role.name,
      'content': content,
      'metadata': metadata ?? const <String, dynamic>{},
      'created_at': DateTime.now().toIso8601String(),
    };

    final response = await client
        .from('chat_messages')
        .upsert(payload)
        .select()
        .single();
    return ChatMessage.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<void> deleteThread({
    required String threadId,
    required String userId,
  }) async {
    final client = _client;
    if (client == null) {
      return;
    }

    await client
        .from('chat_threads')
        .delete()
        .eq('id', threadId)
        .eq('user_id', userId);
  }
}
