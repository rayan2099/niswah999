import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../domain/entities/private_message.dart';
import '../../domain/repositories/private_messaging_repository_base.dart';

/// Loads, sends and reactively updates messages for one conversation.
class ChatDetailViewModel extends ChangeNotifier {
  final PrivateMessagingRepositoryBase _repository;
  final String conversationId;
  final String currentUserId;

  ChatDetailViewModel({
    required PrivateMessagingRepositoryBase repository,
    required this.conversationId,
    required this.currentUserId,
  }) : _repository = repository;

  List<PrivateMessage> messages = [];
  bool isLoading = false;
  bool isSending = false;
  String? errorMessage;

  /// Stable id for the message currently being sent, reused across manual
  /// retries of the same submit so a retry after a timeout upserts the
  /// same row instead of creating a duplicate message — same pattern as
  /// `CommunityFeedViewModel._pendingPostId` (RR-001 idempotency audit).
  String? _pendingMessageId;

  Future<void> loadMessages() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      messages = await _repository.fetchMessages(conversationId);
      await _repository.markMessagesAsRead(
        conversationId: conversationId,
        readerId: currentUserId,
      );
      // Reflect the read state locally (RLS only lets the recipient update).
      messages = [
        for (final message in messages)
          if (!message.isRead && message.senderId != currentUserId)
            message.copyWith(isRead: true)
          else
            message,
      ];
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Sends [content] and appends the stored message optimistically.
  Future<bool> sendMessage(String content) async {
    if (content.trim().isEmpty) return false;
    isSending = true;
    errorMessage = null;
    notifyListeners();
    final messageId = _pendingMessageId ??= const Uuid().v4();
    try {
      final message = await _repository.sendMessage(
        conversationId: conversationId,
        senderId: currentUserId,
        content: content,
        messageId: messageId,
      );
      messages = [...messages, message];
      _pendingMessageId = null;
      return true;
    } catch (e, stack) {
      errorMessage = e.toString();
      AppErrorReporter.report(
        e,
        stack,
        context: 'ChatDetailViewModel.sendMessage',
        feature: 'private_messaging',
        recordId: messageId,
      );
      return false;
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  /// Called by realtime subscription when a new message arrives.
  void onIncomingMessage(PrivateMessage message) {
    if (message.conversationId != conversationId) return;
    if (messages.any((m) => m.id == message.id)) return;
    messages = [...messages, message];
    notifyListeners();
    if (message.senderId != currentUserId) {
      _repository
          .markMessagesAsRead(
            conversationId: conversationId,
            readerId: currentUserId,
          )
          .catchError((_) {});
    }
  }

  bool isMine(PrivateMessage message) => message.senderId == currentUserId;
}
