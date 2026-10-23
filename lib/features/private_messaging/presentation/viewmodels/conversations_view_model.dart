import 'dart:async';

import '../../domain/repositories/private_messaging_realtime.dart';

import 'package:flutter/foundation.dart';

import '../../domain/entities/private_conversation.dart';
import '../../domain/repositories/private_messaging_repository_base.dart';

/// Loads and holds the list of private conversations for the current user.
class ConversationsViewModel extends ChangeNotifier {
  final PrivateMessagingRepositoryBase _repository;
  final String currentUserId;

  ConversationsViewModel({
    required PrivateMessagingRepositoryBase repository,
    required this.currentUserId,
  }) : _repository = repository {
    if (repository is PrivateMessagingRealtime) {
      _unsubscribe = (repository as PrivateMessagingRealtime).watchChanges(
        () => unawaited(loadConversations()),
      );
    }
  }
  void Function()? _unsubscribe;
  bool _disposed = false;
  int _generation = 0;
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  List<PrivateConversation> conversations = [];
  Map<String, String> displayNames = const {};
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadConversations() async {
    final generation = ++_generation;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final loaded = await _repository.fetchConversations();
      final names = await _repository.fetchDisplayNames({
        for (final c in loaded) c.otherParticipant(currentUserId),
      });
      if (_disposed || generation != _generation) return;
      conversations = loaded;
      displayNames = names;
    } catch (e) {
      if (generation == _generation) errorMessage = e.toString();
    } finally {
      if (generation == _generation) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  /// The published display name of the other participant, if any.
  String? displayNameFor(PrivateConversation conversation) =>
      displayNames[conversation.otherParticipant(currentUserId)];

  /// Opens (or creates) a conversation with [otherUserId] and returns it.
  Future<PrivateConversation?> startConversation(String otherUserId) async {
    try {
      final conversation = await _repository.getOrCreateConversation(
        currentUserId,
        otherUserId,
      );
      if (!conversations.any((c) => c.id == conversation.id)) {
        conversations.insert(0, conversation);
        notifyListeners();
      }
      return conversation;
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }
}
