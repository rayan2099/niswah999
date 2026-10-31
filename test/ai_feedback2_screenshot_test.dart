import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_message.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_thread.dart';
import 'package:niswah/features/ai_assistant/domain/repositories/chat_repository.dart';
import 'package:niswah/features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart';
import 'package:niswah/features/ai_assistant/presentation/viewmodels/chat_view_model.dart';

import 'support/parity_test_harness.dart';

/// Synthetic UI renders for TestFlight Feedback 2. The reply texts are
/// hand-written fixtures that show the layout (notice lines, route button,
/// no unrelated sources); they are NOT model output. SCREENSHOT_DIR writes
/// PNGs; without it the test only checks the screens build.
class _Repo implements ChatRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<List<ChatThread>> getThreads({required String userId}) async => [];
}

ChatMessage _m(
  String id,
  ChatRole role,
  String text, [
  Map<String, dynamic> meta = const {},
]) => ChatMessage(
  id: id,
  threadId: 't',
  userId: 'u',
  role: role,
  content: text,
  metadata: meta,
  createdAt: DateTime(2026, 10, 31, 13),
);

Future<void> _shot(
  WidgetTester tester,
  String name,
  NiswahAssistantMode mode,
  List<ChatMessage> messages,
) async {
  final vm = ChatViewModel(repository: _Repo())
    ..currentThreadId = 't'
    ..messages = messages;
  await ParityTestHarness.pump(
    tester,
    arabic: true,
    homeOverride: RepaintBoundary(
      key: const Key('shot'),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: DrNiswahChatScreen(mode: mode, viewModelForTesting: vm),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  final dir = Platform.environment['SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets(
    'Doctor Niswah: unsourced answer with the AI notice, follow-up without repeat',
    (tester) async {
      await _shot(tester, 'after_doctor_notice', NiswahAssistantMode.health, [
        _m('1', ChatRole.user, 'هل الجماع وقت الدورة له أضرار؟'),
        _m(
          '2',
          ChatRole.assistant,
          '[نص تجريبي] إجابة مباشرة قصيرة عن السؤال، ثم ما يهم عمليًا.',
          {
            'notice': {'aiGenerated': true, 'topic': 'health'},
          },
        ),
        _m('3', ChatRole.user, 'لماذا؟'),
        _m('4', ChatRole.assistant, '[نص تجريبي] متابعة في نفس السياق.', {
          'notice': {'aiGenerated': true, 'topic': 'health'},
        }),
      ]);
      expect(
        find.text('معلومة عامة مولّدة بالذكاء الاصطناعي، وقد تحتمل الخطأ.'),
        findsOneWidget,
      );
      expect(find.textContaining('Urgent Maternal'), findsNothing);
    },
  );

  testWidgets('Niswah AI: answers, then offers the Fiqh advisor', (
    tester,
  ) async {
    await _shot(
      tester,
      'after_general_fiqh_route',
      NiswahAssistantMode.general,
      [
        _m('1', ChatRole.user, 'هل يجوز الجماع وقت الحيض؟'),
        _m(
          '2',
          ChatRole.assistant,
          '[نص تجريبي] الحكم العام باختصار، ثم سطر يقترح المستشارة الفقهية للتفصيل.',
          {
            'notice': {'aiGenerated': true, 'verify': 'fiqh', 'topic': 'fiqh'},
            'route': 'fiqh',
            'route_question': 'هل يجوز الجماع وقت الحيض؟',
          },
        ),
      ],
    );
    expect(find.byKey(const Key('chat-route-button')), findsOneWidget);
  });

  testWidgets('Fiqh advisor: header and banner', (tester) async {
    await _shot(
      tester,
      'after_fiqh_advisor_empty',
      NiswahAssistantMode.fiqhAdvisory,
      const [],
    );
    expect(find.text('المستشارة الفقهية'), findsWidgets);
  });
}
