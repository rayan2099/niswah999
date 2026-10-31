import 'dart:async';

import '../../domain/repositories/private_messaging_realtime.dart';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../community/safety/community_write_error.dart';
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
    this.isVisible,
  }) : _repository = repository {
    if (repository is PrivateMessagingRealtime) {
      _unsubscribe = (repository as PrivateMessagingRealtime).watchConversation(
        conversationId,
        onIncomingMessage,
        onResync: () => unawaited(loadMessages()),
      );
    }
  }

  final bool Function()? isVisible;
  void Function()? _unsubscribe;
  bool _disposed = false;
  bool active = true;
  int _loadGeneration = 0;
  final _received = <String, PrivateMessage>{};

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  List<PrivateMessage> messages = [];
  bool isLoading = false;
  bool isSending = false;
  String? errorMessage;

  /// Set when the last send was refused by a community safety rule.
  CommunityWriteError? sendError;

  /// Stable id for the message currently being sent, reused across manual
  /// retries of the same submit so a retry after a timeout upserts the
  /// same row instead of creating a duplicate message — same pattern as
  /// `CommunityFeedViewModel._pendingPostId` (RR-001 idempotency audit).
  String? _pendingMessageId;

  Future<void> loadMessages() async {
    final generation = ++_loadGeneration;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final loaded = await _repository.fetchMessages(conversationId);
      if (_disposed || generation != _loadGeneration) return;
      messages = {
        ..._received,
        for (final message in loaded) message.id: message,
      }.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!active || !(isVisible?.call() ?? true)) return;
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
      if (!_disposed && generation == _loadGeneration) {
        errorMessage = e.toString();
      }
    } finally {
      if (generation == _loadGeneration) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Sends [content] and appends the stored message optimistically.
  Future<bool> sendMessage(String content) async {
    if (content.trim().isEmpty) return false;
    isSending = true;
    errorMessage = null;
    sendError = null;
    notifyListeners();
    final messageId = _pendingMessageId ??= const Uuid().v4();
    try {
      final message = await _repository.sendMessage(
        conversationId: conversationId,
        senderId: currentUserId,
        content: content,
        messageId: messageId,
      );
      if (_disposed) return false;
      _received[message.id] = message;
      messages = {
        for (final m in messages) m.id: m,
        message.id: message,
      }.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _pendingMessageId = null;
      return true;
    } catch (e, stack) {
      errorMessage = e.toString();
      sendError = CommunityWriteError.from(e);
      // A safety refusal (blocked word, block, suspension) is an expected
      // outcome, not a fault worth reporting.
      if (sendError != null) return false;
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
    if (_disposed || message.conversationId != conversationId) return;
    _received[message.id] = message;
    if (messages.any((m) => m.id == message.id)) return;
    messages = [...messages, message];
    notifyListeners();
    if (active &&
        (isVisible?.call() ?? true) &&
        message.senderId != currentUserId) {
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
