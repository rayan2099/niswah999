import 'package:flutter/foundation.dart';

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
    try {
      final message = await _repository.sendMessage(
        conversationId: conversationId,
        senderId: currentUserId,
        content: content,
      );
      messages = [...messages, message];
      return true;
    } catch (e) {
      errorMessage = e.toString();
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
