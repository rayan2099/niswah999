import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_message.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_thread.dart';
import 'package:niswah/features/ai_assistant/domain/repositories/chat_repository.dart';
import 'package:niswah/features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart';
import 'package:niswah/features/ai_assistant/presentation/viewmodels/chat_view_model.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

/// TestFlight Feedback 2 navigation regressions: the fiqh shortcut opened
/// the general Niswah AI; a chat could be opened on another assistant's
/// thread; a suggestion could point back to the chat it came from.
class _Repo implements ChatRepository {
  _Repo([this.threads = const []]);
  final List<ChatThread> threads;
  final loadedThreadIds = <String>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<ChatThread>> getThreads({required String userId}) async =>
      threads;

  @override
  Future<List<ChatMessage>> getMessages({
    required String threadId,
    required String userId,
  }) async {
    loadedThreadIds.add(threadId);
    return const [];
  }
}

ChatThread _thread(String id, ChatThreadType type) => ChatThread(
  id: id,
  userId: 'u',
  title: id,
  threadType: type,
  status: ChatThreadStatus.active,
  metadata: const {},
  createdAt: DateTime(2026, 10, 31),
  updatedAt: DateTime(2026, 10, 31),
);

ChatMessage _m(
  String id,
  ChatRole role,
  String content, [
  Map<String, dynamic> metadata = const {},
]) => ChatMessage(
  id: id,
  threadId: 't',
  userId: 'u',
  role: role,
  content: content,
  metadata: metadata,
  createdAt: DateTime(2026, 10, 31),
);

Future<void> _pumpChat(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(true);
  });

  testWidgets('dashboard: "اسألي أي سؤال فقهي" opens the Fiqh advisor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final shortcut = find.byKey(const Key('dashboard-fiqh-shortcut'));
    expect(shortcut, findsOneWidget);
    expect(find.text('اسألي أي سؤال فقهي...'), findsOneWidget);
    await tester.ensureVisible(shortcut);
    await tester.tap(shortcut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final chat = tester.widget<DrNiswahChatScreen>(
      find.byType(DrNiswahChatScreen),
    );
    expect(chat.mode, NiswahAssistantMode.fiqhAdvisory);
    expect(chatThreadTypeFor(chat.mode), ChatThreadType.fiqhAdvisory);
    expect(find.text('المستشارة الفقهية'), findsWidgets);
    expect(find.text('نسوة AI'), findsNothing);
  });

  testWidgets('a thread of another assistant is never resumed in this chat', (
    tester,
  ) async {
    final repo = _Repo([
      _thread('general-thread', ChatThreadType.general),
      _thread('fiqh-thread', ChatThreadType.fiqhAdvisory),
    ]);
    await _pumpChat(
      tester,
      DrNiswahChatScreen(
        mode: NiswahAssistantMode.fiqhAdvisory,
        initialThreadId: 'general-thread',
        viewModelForTesting: ChatViewModel(repository: repo),
      ),
    );
    expect(repo.loadedThreadIds, isEmpty);

    final repo2 = _Repo([_thread('fiqh-thread', ChatThreadType.fiqhAdvisory)]);
    await _pumpChat(
      tester,
      DrNiswahChatScreen(
        key: const Key('second'),
        mode: NiswahAssistantMode.fiqhAdvisory,
        initialThreadId: 'fiqh-thread',
        viewModelForTesting: ChatViewModel(repository: repo2),
      ),
    );
    expect(repo2.loadedThreadIds, ['fiqh-thread']);
  });

  test('every chat thread type maps to exactly one chat (dream has its own screen)', () {
    for (final mode in NiswahAssistantMode.values) {
      expect(assistantModeForThreadType(chatThreadTypeFor(mode)), mode);
    }
    expect(assistantModeForThreadType(ChatThreadType.dreamInterpreter), isNull);
  });

  testWidgets(
    'a suggestion to the chat she is already in is not shown; another chat is',
    (tester) async {
      final vm = ChatViewModel(repository: _Repo())
        ..currentThreadId = 't'
        ..messages = [
          _m('1', ChatRole.user, 'سؤال'),
          _m('2', ChatRole.assistant, 'جواب الفقه', {
            'route': 'fiqh',
            'route_question': 'سؤال',
          }),
        ];
      await _pumpChat(
        tester,
        DrNiswahChatScreen(
          mode: NiswahAssistantMode.fiqhAdvisory,
          viewModelForTesting: vm,
        ),
      );
      expect(find.byKey(const Key('chat-route-button')), findsNothing);

      final vm2 = ChatViewModel(repository: _Repo())
        ..currentThreadId = 't'
        ..messages = [
          _m('1', ChatRole.user, 'هل يجوز الجماع وقت الحيض؟'),
          _m('2', ChatRole.assistant, 'لا يجوز...', {
            'route': 'fiqh',
            'route_question': 'هل يجوز الجماع وقت الحيض؟',
          }),
        ];
      await _pumpChat(
        tester,
        DrNiswahChatScreen(key: const Key('general'), viewModelForTesting: vm2),
      );
      expect(find.byKey(const Key('chat-route-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat-route-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final opened = tester.widget<DrNiswahChatScreen>(
        find.byType(DrNiswahChatScreen).last,
      );
      expect(opened.mode, NiswahAssistantMode.fiqhAdvisory);
      expect(opened.routedFrom, NiswahAssistantMode.general);
      expect(opened.initialDraft, 'هل يجوز الجماع وقت الحيض؟');
    },
  );

  testWidgets('Doctor Niswah\'s "فقه" tile opens the Fiqh advisor', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      DrNiswahChatScreen(
        mode: NiswahAssistantMode.health,
        viewModelForTesting: ChatViewModel(repository: _Repo()),
      ),
    );
    await tester.tap(find.byKey(const Key('chat-topic-fiqh')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final opened = tester.widget<DrNiswahChatScreen>(
      find.byType(DrNiswahChatScreen).last,
    );
    expect(opened.mode, NiswahAssistantMode.fiqhAdvisory);
    expect(opened.routedFrom, NiswahAssistantMode.health);
  });

  testWidgets(
    'the AI notice is shown once under an unsourced answer and not under a greeting',
    (tester) async {
      final vm = ChatViewModel(repository: _Repo())
        ..currentThreadId = 't'
        ..messages = [
          _m('1', ChatRole.user, 'السلام عليكم'),
          _m('2', ChatRole.assistant, 'وعليكم السلام', {
            'notice': {'aiGenerated': false, 'topic': 'social'},
          }),
          _m('3', ChatRole.user, 'هل الجماع وقت الدورة له أضرار؟'),
          _m('4', ChatRole.assistant, 'في الغالب لا...', {
            'notice': {'aiGenerated': true, 'topic': 'health'},
          }),
          _m('5', ChatRole.user, 'لماذا؟'),
          _m('6', ChatRole.assistant, 'لأن...', {
            'notice': {'aiGenerated': true, 'topic': 'health'},
          }),
        ];
      await _pumpChat(
        tester,
        DrNiswahChatScreen(
          mode: NiswahAssistantMode.health,
          viewModelForTesting: vm,
        ),
      );
      expect(
        find.text('معلومة عامة مولّدة بالذكاء الاصطناعي، وقد تحتمل الخطأ.'),
        findsOneWidget,
      );
    },
  );
}
