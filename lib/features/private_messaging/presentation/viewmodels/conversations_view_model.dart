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
  }) : _repository = repository;

  List<PrivateConversation> conversations = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadConversations() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      conversations = await _repository.fetchConversations();
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

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
