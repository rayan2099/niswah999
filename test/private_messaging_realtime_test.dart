import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/private_messaging/data/repositories/mock_private_messaging_repository.dart';
import 'package:niswah/features/private_messaging/domain/repositories/private_messaging_realtime.dart';
import 'package:niswah/features/private_messaging/domain/entities/private_message.dart';
import 'package:niswah/features/private_messaging/presentation/viewmodels/chat_detail_view_model.dart';
import 'package:niswah/features/private_messaging/presentation/widgets/unread_messages_badge.dart';

class LiveRepo extends MockPrivateMessagingRepository
    implements PrivateMessagingRealtime {
  LiveRepo() : super(currentUserId: 'a');
  Completer<List<PrivateMessage>>? held;
  List<PrivateMessage> rows = [];
  int marked = 0, unread = 0, cancelled = 0;
  void Function(PrivateMessage)? incoming;
  VoidCallback? changes, resync;
  @override
  Future<List<PrivateMessage>> fetchMessages(String id) async =>
      held?.future ?? rows;
  @override
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String readerId,
  }) async {
    marked++;
  }

  @override
  Future<int> fetchUnreadCount() async => unread;
  @override
  void Function() watchConversation(
    String id,
    void Function(PrivateMessage) onMessage, {
    VoidCallback? onResync,
  }) {
    incoming = onMessage;
    resync = onResync;
    return () => cancelled++;
  }

  @override
  void Function() watchChanges(VoidCallback callback) {
    changes = callback;
    return () => cancelled++;
  }
}

PrivateMessage message(String id, {bool read = false, String sender = 'b'}) =>
    PrivateMessage(
      id: id,
      conversationId: 'thread',
      senderId: sender,
      content: 'synthetic',
      isRead: read,
      createdAt: DateTime.utc(2030, 1, 1, id == 'older' ? 0 : 1),
    );
void main() {
  test('an incoming event during loading is retained and duplicates are suppressed', () async {
    final repo = LiveRepo()..held = Completer();
    final vm = ChatDetailViewModel(
      repository: repo,
      conversationId: 'thread',
      currentUserId: 'a',
    );
    final load = vm.loadMessages();
    repo.incoming!(message('new'));
    repo.incoming!(message('new'));
    repo.held!.complete([message('older')]);
    await load;
    expect(vm.messages.map((m) => m.id), ['older', 'new']);
    expect(repo.marked, greaterThan(0));
    vm.dispose();
    expect(repo.cancelled, 1);
  });
  test(
    'hidden/background conversations do not mark incoming messages read',
    () async {
      final repo = LiveRepo();
      var visible = false;
      final vm = ChatDetailViewModel(
        repository: repo,
        conversationId: 'thread',
        currentUserId: 'a',
        isVisible: () => visible,
      );
      repo.incoming!(message('one'));
      expect(repo.marked, 0);
      visible = true;
      vm.active = false;
      repo.incoming!(message('two'));
      expect(repo.marked, 0);
      vm.active = true;
      repo.incoming!(message('three'));
      expect(repo.marked, 1);
      vm.dispose();
    },
  );
  test(
    'server read receipts beat older received-event state on reconnect',
    () async {
      final repo = LiveRepo();
      final vm = ChatDetailViewModel(
        repository: repo,
        conversationId: 'thread',
        currentUserId: 'a',
      );
      repo.incoming!(message('mine', sender: 'a'));
      repo.rows = [message('mine', sender: 'a', read: true)];
      await vm.loadMessages();
      expect(vm.messages.single.isRead, true);
      vm.dispose();
    },
  );
  testWidgets(
    'unread badge responds to live events and resume, and cancels on dispose',
    (tester) async {
      final repo = LiveRepo()..unread = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: UnreadMessagesBadge(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      repo.unread = 3;
      repo.changes!();
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      repo.unread = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('3'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(repo.cancelled, 1);
    },
  );
}
