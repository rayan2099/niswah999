import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/features/private_messaging/data/repositories/private_messaging_repository.dart';
import 'package:niswah/features/private_messaging/domain/entities/private_conversation.dart';
import 'package:niswah/features/private_messaging/domain/entities/private_message.dart';
import 'package:niswah/features/private_messaging/domain/repositories/private_messaging_repository_base.dart';
import 'package:niswah/features/private_messaging/presentation/screens/chat_detail_screen.dart';
import 'package:niswah/features/private_messaging/presentation/screens/conversations_screen.dart';
import 'package:niswah/features/private_messaging/presentation/viewmodels/chat_detail_view_model.dart';
import 'package:niswah/features/private_messaging/presentation/viewmodels/conversations_view_model.dart';
import 'package:niswah/features/private_messaging/private_messaging_locator.dart';

const _me = 'user-me';
const _other = 'user-other';

PrivateConversation _conversation({String id = 'conv-1'}) =>
    PrivateConversation(
      id: id,
      participantOne: _me,
      participantTwo: _other,
      createdAt: DateTime(2026, 8, 22, 9),
      updatedAt: DateTime(2026, 8, 22, 10),
    );

PrivateMessage _message({
  String id = 'msg-1',
  String conversationId = 'conv-1',
  String senderId = _other,
  String content = 'Assalamu alaikum',
  bool isRead = false,
}) => PrivateMessage(
  id: id,
  conversationId: conversationId,
  senderId: senderId,
  content: content,
  isRead: isRead,
  createdAt: DateTime(2026, 8, 22, 9, 30),
);

class FakePrivateMessagingRepository implements PrivateMessagingRepositoryBase {
  FakePrivateMessagingRepository({
    List<PrivateConversation>? conversations,
    Map<String, List<PrivateMessage>>? messages,
    this.failSends = false,
  }) : conversations = conversations ?? [],
       messagesByConversation = messages ?? {};

  List<PrivateConversation> conversations;
  Map<String, List<PrivateMessage>> messagesByConversation;
  bool failSends;

  int fetchConversationsCalls = 0;
  int fetchMessagesCalls = 0;
  int getOrCreateCalls = 0;
  int sendMessageCalls = 0;
  int markReadCalls = 0;
  final List<String> sentContents = [];

  @override
  Future<int> fetchUnreadCount() async {
    var count = 0;
    for (final messages in messagesByConversation.values) {
      for (final message in messages) {
        if (!message.isRead && message.senderId != 'You') {
          count++;
        }
      }
    }
    return count;
  }

  @override
  Future<List<PrivateConversation>> fetchConversations() async {
    fetchConversationsCalls++;
    return List.of(conversations);
  }

  @override
  Future<List<PrivateMessage>> fetchMessages(String conversationId) async {
    fetchMessagesCalls++;
    return List.of(messagesByConversation[conversationId] ?? const []);
  }

  @override
  Future<PrivateConversation> getOrCreateConversation(
    String currentUserId,
    String otherUserId,
  ) async {
    getOrCreateCalls++;
    final existing = conversations.where(
      (c) => c.involves(currentUserId) && c.involves(otherUserId),
    );
    if (existing.isNotEmpty) return existing.first;
    final created = PrivateConversation(
      id: 'conv-${conversations.length + 1}',
      participantOne: currentUserId,
      participantTwo: otherUserId,
      createdAt: DateTime(2026, 8, 22),
      updatedAt: DateTime(2026, 8, 22),
    );
    conversations.add(created);
    return created;
  }

  @override
  Future<PrivateMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    sendMessageCalls++;
    if (failSends) throw const PrivateMessagingException('send failed');
    // Mirror the real repository, which trims content before persisting.
    final trimmed = content.trim();
    sentContents.add(trimmed);
    final message = PrivateMessage(
      id: 'sent-$sendMessageCalls',
      conversationId: conversationId,
      senderId: senderId,
      content: trimmed,
      isRead: false,
      createdAt: DateTime(2026, 8, 22, 11),
    );
    messagesByConversation.putIfAbsent(conversationId, () => []).add(message);
    return message;
  }

  @override
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String readerId,
  }) async {
    markReadCalls++;
    final list = messagesByConversation[conversationId];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      if (list[i].senderId != readerId && !list[i].isRead) {
        list[i] = PrivateMessage(
          id: list[i].id,
          conversationId: list[i].conversationId,
          senderId: list[i].senderId,
          content: list[i].content,
          isRead: true,
          createdAt: list[i].createdAt,
        );
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUp(() => AppLocaleController.instance.setArabic(false));

  group('Private messaging models', () {
    test('serializes and deserializes a conversation', () {
      final original = _conversation();
      final restored = PrivateConversation.fromJson(original.toJson());
      expect(restored.id, 'conv-1');
      expect(restored.participantOne, _me);
      expect(restored.participantTwo, _other);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('otherParticipant resolves both directions', () {
      final conversation = _conversation();
      expect(conversation.otherParticipant(_me), _other);
      expect(conversation.otherParticipant(_other), _me);
      expect(conversation.involves(_me), isTrue);
      expect(conversation.involves('stranger'), isFalse);
    });

    test('serializes and deserializes a message', () {
      final original = _message(isRead: true);
      final restored = PrivateMessage.fromJson(original.toJson());
      expect(restored.id, 'msg-1');
      expect(restored.conversationId, 'conv-1');
      expect(restored.senderId, _other);
      expect(restored.content, 'Assalamu alaikum');
      expect(restored.isRead, isTrue);
      expect(restored.createdAt, original.createdAt);
    });

    test('message is_read defaults to false when missing', () {
      final json = _message().toJson()..remove('is_read');
      expect(PrivateMessage.fromJson(json).isRead, isFalse);
    });
  });

  group('ConversationsViewModel', () {
    test('loads conversations from repository', () async {
      final repository = FakePrivateMessagingRepository(
        conversations: [_conversation()],
      );
      final viewModel = ConversationsViewModel(
        repository: repository,
        currentUserId: _me,
      );

      await viewModel.loadConversations();

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.errorMessage, isNull);
      expect(viewModel.conversations, hasLength(1));
      expect(viewModel.conversations.first.id, 'conv-1');
      expect(repository.fetchConversationsCalls, 1);
    });

    test('exposes error message when loading fails', () async {
      final viewModel = ConversationsViewModel(
        repository: _FailingRepository(),
        currentUserId: _me,
      );

      await viewModel.loadConversations();

      expect(viewModel.conversations, isEmpty);
      expect(viewModel.errorMessage, isNotNull);
      expect(viewModel.isLoading, isFalse);
    });

    test('startConversation reuses existing conversation', () async {
      final repository = FakePrivateMessagingRepository(
        conversations: [_conversation()],
      );
      final viewModel = ConversationsViewModel(
        repository: repository,
        currentUserId: _me,
      );

      final result = await viewModel.startConversation(_other);

      expect(result?.id, 'conv-1');
      expect(repository.getOrCreateCalls, 1);
      expect(viewModel.conversations, hasLength(1));
    });

    test('startConversation inserts new conversation at top', () async {
      final repository = FakePrivateMessagingRepository();
      final viewModel = ConversationsViewModel(
        repository: repository,
        currentUserId: _me,
      );

      final result = await viewModel.startConversation(_other);

      expect(result, isNotNull);
      expect(viewModel.conversations, hasLength(1));
      expect(viewModel.conversations.first.otherParticipant(_me), _other);
    });
  });

  group('ChatDetailViewModel', () {
    test('loads messages and marks incoming ones as read', () async {
      final repository = FakePrivateMessagingRepository(
        messages: {
          'conv-1': [
            _message(senderId: _other),
            _message(id: 'msg-2', senderId: _me, content: 'Wa alaikum salam'),
          ],
        },
      );
      final viewModel = ChatDetailViewModel(
        repository: repository,
        conversationId: 'conv-1',
        currentUserId: _me,
      );

      await viewModel.loadMessages();

      expect(viewModel.messages, hasLength(2));
      expect(repository.markReadCalls, 1);
      // Only the other user's message should be marked read.
      expect(viewModel.messages.first.isRead, isTrue);
      expect(viewModel.messages.last.isRead, isFalse);
    });

    test('sendMessage appends message and reports success', () async {
      final repository = FakePrivateMessagingRepository();
      final viewModel = ChatDetailViewModel(
        repository: repository,
        conversationId: 'conv-1',
        currentUserId: _me,
      );

      final sent = await viewModel.sendMessage('  Hello there!  ');

      expect(sent, isTrue);
      expect(repository.sentContents, ['Hello there!']);
      expect(viewModel.messages, hasLength(1));
      expect(viewModel.messages.first.content, 'Hello there!');
      expect(viewModel.isMine(viewModel.messages.first), isTrue);
    });

    test('sendMessage rejects blank input', () async {
      final repository = FakePrivateMessagingRepository();
      final viewModel = ChatDetailViewModel(
        repository: repository,
        conversationId: 'conv-1',
        currentUserId: _me,
      );

      expect(await viewModel.sendMessage('   '), isFalse);
      expect(repository.sendMessageCalls, 0);
      expect(viewModel.messages, isEmpty);
    });

    test('sendMessage surfaces failure', () async {
      final repository = FakePrivateMessagingRepository(failSends: true);
      final viewModel = ChatDetailViewModel(
        repository: repository,
        conversationId: 'conv-1',
        currentUserId: _me,
      );

      expect(await viewModel.sendMessage('hi'), isFalse);
      expect(viewModel.errorMessage, isNotNull);
      expect(viewModel.messages, isEmpty);
      expect(viewModel.isSending, isFalse);
    });

    test('onIncomingMessage appends foreign messages only once', () {
      final repository = FakePrivateMessagingRepository();
      final viewModel = ChatDetailViewModel(
        repository: repository,
        conversationId: 'conv-1',
        currentUserId: _me,
      );

      viewModel.onIncomingMessage(_message());
      viewModel.onIncomingMessage(_message()); // duplicate id ignored
      viewModel.onIncomingMessage(
        _message(id: 'msg-x', conversationId: 'conv-2'), // other thread
      );

      expect(viewModel.messages, hasLength(1));
    });
  });

  group('PrivateMessagingException', () {
    test('has readable toString', () {
      expect(
        const PrivateMessagingException('boom').toString(),
        contains('boom'),
      );
    });
  });

  group('ConversationsScreen widget', () {
    testWidgets('renders loaded conversations and opens chat on tap', (
      tester,
    ) async {
      final repository = FakePrivateMessagingRepository(
        conversations: [_conversation()],
        messages: {
          'conv-1': [_message()],
        },
      );
      final viewModel = ConversationsViewModel(
        repository: repository,
        currentUserId: _me,
      );
      // ChatDetailScreen resolves its repository via the global locator.
      privateMessagingRepositoryOverride = repository;

      await tester.pumpWidget(
        MaterialApp(home: ConversationsScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();

      expect(find.text('user-other'), findsOneWidget);

      await tester.tap(find.text('user-other'));
      await tester.pumpAndSettle();

      // Chat detail screen pushed with the message visible.
      expect(find.byType(ChatDetailScreen), findsOneWidget);
      expect(find.text('Assalamu alaikum'), findsOneWidget);
    });

    testWidgets('shows empty state when no conversations exist', (
      tester,
    ) async {
      final viewModel = ConversationsViewModel(
        repository: FakePrivateMessagingRepository(),
        currentUserId: _me,
      );

      await tester.pumpWidget(
        MaterialApp(home: ConversationsScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No conversations yet'), findsOneWidget);
    });

    testWidgets('shows error state when loading fails', (tester) async {
      final viewModel = ConversationsViewModel(
        repository: _FailingRepository(),
        currentUserId: _me,
      );

      await tester.pumpWidget(
        MaterialApp(home: ConversationsScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not load your messages'),
        findsOneWidget,
      );
    });
  });

  group('ChatDetailScreen widget', () {
    late FakePrivateMessagingRepository repository;

    setUp(() {
      repository = FakePrivateMessagingRepository(
        messages: {
          'conv-1': [_message()],
        },
      );
      privateMessagingRepositoryOverride = repository;
    });

    tearDown(() {
      privateMessagingRepositoryOverride = _FailingRepository(); // detach fake
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: _conversation(),
            currentUserId: _me,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('displays existing messages with sender alignment', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Assalamu alaikum'), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsNothing);
    });

    testWidgets('sends a message through the input field', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'Wa alaikum salam');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(repository.sentContents, ['Wa alaikum salam']);
      expect(find.text('Wa alaikum salam'), findsOneWidget);
      // Own sent message shows the single-check (unread) indicator.
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    });

    testWidgets('does not send blank messages', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(repository.sentContents, isEmpty);
    });

    testWidgets('shows failure feedback when sending fails', (tester) async {
      repository.failSends = true;
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Message failed to send'), findsOneWidget);
    });
  });
}

class _FailingRepository implements PrivateMessagingRepositoryBase {
  @override
  Future<List<PrivateConversation>> fetchConversations() async {
    throw const PrivateMessagingException('network down');
  }

  @override
  Future<List<PrivateMessage>> fetchMessages(String conversationId) async {
    throw const PrivateMessagingException('network down');
  }

  @override
  Future<PrivateConversation> getOrCreateConversation(
    String currentUserId,
    String otherUserId,
  ) async {
    throw const PrivateMessagingException('network down');
  }

  @override
  Future<PrivateMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    throw const PrivateMessagingException('network down');
  }

  @override
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String readerId,
  }) async {
    throw const PrivateMessagingException('network down');
  }

  @override
  Future<int> fetchUnreadCount() async {
    throw const PrivateMessagingException('network down');
  }
}
