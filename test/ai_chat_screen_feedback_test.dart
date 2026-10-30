import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/network/ai_failure.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_message.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_thread.dart';
import 'package:niswah/features/ai_assistant/domain/repositories/chat_repository.dart';
import 'package:niswah/features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart';
import 'package:niswah/features/ai_assistant/presentation/viewmodels/chat_view_model.dart';

import 'support/parity_test_harness.dart';

/// Screen-level checks for the 2026-10-30 testing feedback: repeated source
/// cards, the generic "could not send" line, and failures with no way to
/// retry. The conversation is a synthetic UI fixture, not model output.
///
/// Set SCREENSHOT_DIR to also write PNGs of each state (used for the PR's
/// before/after evidence); without it nothing is written.
class _NoopRepo implements ChatRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<ChatThread>> getThreads({required String userId}) async => [];
}

class _VM extends ChatViewModel {
  _VM() : super(repository: _NoopRepo());
  void refresh() => notifyListeners();
}

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
  createdAt: DateTime(2026, 10, 30, 13, 56),
);

const _urgentUrl =
    'https://www.nhs.uk/pregnancy/related-conditions/complications/urgent-signs/';

Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('screenshot-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<ChatViewModel> _pump(
  WidgetTester tester,
  NiswahAssistantMode mode,
  List<ChatMessage> messages, {
  AiFailure? failure,
}) async {
  final vm = _VM()
    ..currentThreadId = 't'
    ..messages = messages;
  await ParityTestHarness.pump(
    tester,
    arabic: true,
    homeOverride: RepaintBoundary(
      key: const Key('screenshot-root'),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: DrNiswahChatScreen(mode: mode, viewModelForTesting: vm),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  // Set after the screen's initial thread load, which clears errors.
  if (failure != null) {
    vm
      ..lastFailure = failure
      ..errorMessage = failure.message
      ..refresh();
    await tester.pump();
  }
  return vm;
}

void main() {
  testWidgets('one source line per document, extras behind المصادر', (
    tester,
  ) async {
    await _pump(tester, NiswahAssistantMode.health, [
      _m('1', ChatRole.user, 'ما علاج اللون الاحمر الغامق للدم'),
      _m(
        '2',
        ChatRole.assistant,
        'لون الدم وحده لا يحدد علاجًا؛ المهم مصدره. هل أنتِ حامل أو بعد الولادة؟ ومتى بدأ النزول، وهل معه ألم؟',
        {
          'citations': [
            for (var i = 0; i < 4; i++)
              {
                'title': 'Urgent Maternal Warning Signs and Symptoms',
                'url': _urgentUrl,
              },
            {
              'title': 'Recovering from birth',
              'url': 'https://www.nhs.uk/baby/support-and-services/your-6-week-postnatal-check/',
            },
            {
              'title': 'Your menstrual cycle',
              'url': 'https://www.womenshealth.gov/menstrual-cycle/your-menstrual-cycle',
            },
          ],
        },
      ),
    ]);
    expect(find.text('المصادر (3)'), findsOneWidget);
    expect(
      find.text('Urgent Maternal Warning Signs and Symptoms'),
      findsOneWidget,
    );
    expect(
      find.text('Recovering from birth'),
      findsNothing,
      reason: 'collapsed',
    );
    expect(find.text('هيئة الخدمات الصحية البريطانية NHS'), findsOneWidget);
    await _capture(tester, 'after_sources_collapsed');

    await tester.tap(find.byKey(const Key('chat-sources-toggle')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Recovering from birth'), findsOneWidget);
    expect(find.text('Your menstrual cycle'), findsOneWidget);
    expect(
      find.text('Urgent Maternal Warning Signs and Symptoms'),
      findsOneWidget,
    );
    await _capture(tester, 'after_sources_expanded');
  });

  testWidgets('a failed send shows its reason, a reference, retry and edit', (
    tester,
  ) async {
    await _pump(
      tester,
      NiswahAssistantMode.general,
      [
        _m('1', ChatRole.user, 'هل الجماع حلال وقت الدورة؟'),
        _m(
          '2',
          ChatRole.assistant,
          'هذا سؤال عن حكم شرعي، والأدق أن تسألي المستشارة الفقهية في التطبيق لأنها تجيب من مكتبة فقهية مراجَعة وفق مذهبكِ.',
          {'route': 'fiqh', 'route_question': 'هل الجماع حلال وقت الدورة؟'},
        ),
        _m('3', ChatRole.user, 'لماذا؟', {ChatViewModel.deliveryKey: 'failed'}),
      ],
      failure: const AiFailure(
        AiFailureCategory.providerBusy,
        correlationId: '6f1c2a9e-3b4d-4e5f-8a9b-0c1d2e3f4a5b',
      ),
    );
    expect(find.text('تعذر إرسال الرسالة. حاولي مرة أخرى.'), findsNothing);
    expect(find.textContaining('المساعدة مشغولة الآن'), findsOneWidget);
    expect(find.textContaining('6f1c2a9e'), findsOneWidget);
    expect(find.byKey(const Key('chat-retry-3')), findsOneWidget);
    expect(find.byKey(const Key('chat-edit-3')), findsOneWidget);
    expect(find.text('اسألي المستشارة الفقهية'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('chat-retry-3'))).height,
      greaterThanOrEqualTo(44),
    );
    await _capture(tester, 'after_failed_send_and_route');

    await tester.tap(find.byKey(const Key('chat-edit-3')));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(
      field.controller?.text,
      'لماذا؟',
      reason: 'the text goes back to the composer',
    );
    expect(find.byKey(const Key('chat-retry-3')), findsNothing);
  });
}
