import '../../domain/entities/private_conversation.dart';
import '../../domain/entities/private_message.dart';
import '../../domain/repositories/private_messaging_repository_base.dart';

/// In-memory repository with seeded demo data so the private messaging
/// UI can be explored without a Supabase backend or signed-in user.
class MockPrivateMessagingRepository implements PrivateMessagingRepositoryBase {
  MockPrivateMessagingRepository({String currentUserId = 'You'})
    : _currentUserId = currentUserId {
    _seed();
  }

  final String _currentUserId;
  final List<PrivateConversation> _conversations = [];
  final Map<String, List<PrivateMessage>> _messages = {};
  int _idCounter = 0;

  String get currentUserId => _currentUserId;

  void _seed() {
    final now = DateTime.now();

    PrivateConversation conversation(String other, {int hoursAgo = 1}) {
      _idCounter++;
      return PrivateConversation(
        id: 'mock-conv-$_idCounter',
        participantOne: _currentUserId,
        participantTwo: other,
        createdAt: now.subtract(Duration(hours: hoursAgo + 20)),
        updatedAt: now.subtract(Duration(hours: hoursAgo)),
      );
    }

    PrivateMessage message(
      String conversationId,
      String sender,
      String content, {
      required int minutesAgo,
      bool isRead = true,
    }) => PrivateMessage(
      id: 'mock-msg-${_idCounter++}',
      conversationId: conversationId,
      senderId: sender,
      content: content,
      isRead: isRead,
      createdAt: now.subtract(Duration(minutes: minutesAgo)),
    );

    final sara = conversation('Umm Sara', hoursAgo: 1);
    final huda = conversation('Huda', hoursAgo: 5);
    final maryam = conversation('Maryam', hoursAgo: 26);

    _conversations.addAll([sara, huda, maryam]);

    _messages[sara.id] = [
      message(
        sara.id,
        'Umm Sara',
        'Assalamu alaikum! How are you feeling today?',
        minutesAgo: 180,
      ),
      message(
        sara.id,
        _currentUserId,
        'Wa alaikum salam, alhamdulillah. A bit tired but okay.',
        minutesAgo: 170,
      ),
      message(
        sara.id,
        'Umm Sara',
        'Make sure you rest, sister. Warm tea helps me a lot 💛',
        minutesAgo: 160,
      ),
      message(
        sara.id,
        _currentUserId,
        'Jazakillahu khairan, I will inshaAllah.',
        minutesAgo: 90,
      ),
      message(
        sara.id,
        'Umm Sara',
        'Let me know if you need anything at all!',
        minutesAgo: 60,
        isRead: false,
      ),
    ];

    _messages[huda.id] = [
      message(
        huda.id,
        'Huda',
        'Salam! Did you finish reading the fiqh article?',
        minutesAgo: 400,
      ),
      message(
        huda.id,
        _currentUserId,
        'Almost done — the section on istihadah was so clear.',
        minutesAgo: 380,
      ),
      message(
        huda.id,
        'Huda',
        'Right? I loved it. We should discuss it after Asr.',
        minutesAgo: 300,
      ),
    ];

    _messages[maryam.id] = [
      message(
        maryam.id,
        'Maryam',
        'Sister, thank you for your kind words yesterday 🌸',
        minutesAgo: 1600,
      ),
      message(
        maryam.id,
        _currentUserId,
        'Always here for you. May Allah make it easy for you.',
        minutesAgo: 1580,
      ),
    ];
  }

  @override
  Future<List<PrivateConversation>> fetchConversations() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final list = List.of(_conversations)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<List<PrivateMessage>> fetchMessages(String conversationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return List.of(_messages[conversationId] ?? const []);
  }

  @override
  Future<PrivateConversation> getOrCreateConversation(
    String currentUserId,
    String otherUserId,
  ) async {
    final existing = _conversations.where(
      (c) => c.involves(currentUserId) && c.involves(otherUserId),
    );
    if (existing.isNotEmpty) return existing.first;
    _idCounter++;
    final created = PrivateConversation(
      id: 'mock-conv-$_idCounter',
      participantOne: currentUserId,
      participantTwo: otherUserId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _conversations.add(created);
    return created;
  }

  @override
  Future<PrivateMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    String? messageId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final trimmed = content.trim();
    _idCounter++;
    final message = PrivateMessage(
      id: messageId ?? 'mock-msg-$_idCounter',
      conversationId: conversationId,
      senderId: senderId,
      content: trimmed,
      isRead: false,
      createdAt: DateTime.now(),
    );
    _messages.putIfAbsent(conversationId, () => []).add(message);
    _touchConversation(conversationId);
    return message;
  }

  @override
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String readerId,
  }) async {
    final list = _messages[conversationId];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      if (list[i].senderId != readerId && !list[i].isRead) {
        list[i] = list[i].copyWith(isRead: true);
      }
    }
  }

  @override
  Future<int> fetchUnreadCount() async {
    var count = 0;
    for (final messages in _messages.values) {
      for (final message in messages) {
        if (message.senderId != _currentUserId && !message.isRead) {
          count++;
        }
      }
    }
    return count;
  }

  void _touchConversation(String conversationId) {
    for (var i = 0; i < _conversations.length; i++) {
      if (_conversations[i].id == conversationId) {
        _conversations[i] = PrivateConversation(
          id: _conversations[i].id,
          participantOne: _conversations[i].participantOne,
          participantTwo: _conversations[i].participantTwo,
          createdAt: _conversations[i].createdAt,
          updatedAt: DateTime.now(),
        );
      }
    }
  }

  @override
  Future<Map<String, String>> fetchDisplayNames(Set<String> userIds) async =>
      const {};
}
