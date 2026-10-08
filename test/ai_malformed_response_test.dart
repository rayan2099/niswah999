import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/network/ai_function_gateway.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/ai_advisor/ai_advisor_service.dart';
import 'package:niswah/features/ai_assistant/data/services/dr_niswah_backend_service.dart';
import 'package:niswah/features/ai_assistant/domain/services/dr_niswah_red_flags.dart';
import 'package:niswah/features/ai_assistant/presentation/viewmodels/chat_view_model.dart';
import 'package:niswah/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AI-08 — a malformed backend reply. Driven through the AiFunctionGateway
/// test seam (no live model). Every assistant must fail HONESTLY: never a
/// blank bubble, never an empty history row, and — for Doctor Niswah — never
/// the URGENT red-flag banner for a routine question (found by reading the
/// old code: an empty reply was silently replaced by the banner).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() => AiFunctionGateway.testOverride = null);

  void reply(Object? data, {int status = 200}) {
    AiFunctionGateway.testOverride = (name, body) async =>
        FunctionResponse(status: status, data: data);
  }

  final malformed = <String, Object?>{
    'bare string': 'not json',
    'empty map': <String, dynamic>{},
    'empty text': {'reply': '', 'text': ''},
    'blank text': {'reply': '   ', 'text': '   '},
    'non-string text': {'reply': 42, 'text': 42},
    'list': [1, 2, 3],
    'null': null,
  };

  group('Doctor Niswah', () {
    for (final entry in malformed.entries) {
      test('${entry.key}: throws, is not shown as an answer', () async {
        reply(entry.value);
        await expectLater(
          DrNiswahBackendService.instance.send(threadId: 't', content: 'hello'),
          throwsA(isA<StateError>()),
        );
      });
    }

    test('an empty reply for a ROUTINE question is an error, not the urgent banner', () async {
      reply(<String, dynamic>{'reply': '', 'urgent': false});
      final vm = ChatViewModel();
      await expectLater(
        vm.sendViaDrNiswahBackendForTesting(
          threadId: 't',
          userId: 'u',
          content: 'what is a normal cycle length?',
        ),
        throwsA(isA<StateError>()),
      );
      expect(vm.messages, isEmpty, reason: 'no banner, no blank bubble');
    });

    test('a server-flagged urgent message with no text still shows the safety banner', () async {
      reply(<String, dynamic>{'reply': '', 'urgent': true});
      final vm = ChatViewModel();
      await vm.sendViaDrNiswahBackendForTesting(
        threadId: 't',
        userId: 'u',
        content: 'I feel unwell',
      );
      expect(vm.messages.single.content, DrNiswahRedFlags.bannerTextAr);
    });

    test('a well-formed reply is shown as is', () async {
      reply(<String, dynamic>{'reply': 'Drink water.', 'urgent': false});
      final vm = ChatViewModel();
      await vm.sendViaDrNiswahBackendForTesting(
        threadId: 't',
        userId: 'u',
        content: 'hello',
      );
      expect(vm.messages.single.content, 'Drink water.');
    });
  });

  group('Fiqh advisor', () {
    for (final entry in malformed.entries) {
      test('${entry.key}: fails honestly in the user\'s language', () async {
        AppLocaleController.instance.setArabic(false);
        reply(entry.value);
        final answer = await AiAdvisorService.instance.askFiqh(
          question: 'q',
          madhhab: null,
          madhhabState: MadhhabSelectionState.unset,
        );
        expect(answer.text.trim(), isNotEmpty);
        expect(answer.text, contains("couldn't be reached"));
        expect(answer.text, isNot(matches(RegExp(r'[؀-ۿ]'))));
        expect(answer.citations, isEmpty);
      });
    }

    test('Arabic users get the Arabic fallback', () async {
      AppLocaleController.instance.setArabic(true);
      reply('garbage');
      final answer = await AiAdvisorService.instance.askFiqh(
        question: 'q',
        madhhab: null,
        madhhabState: MadhhabSelectionState.unset,
      );
      expect(answer.text, contains('المصادر'));
    });

    test('a request carries the madhhab context the app knows', () async {
      Map<String, dynamic>? sent;
      AiFunctionGateway.testOverride = (name, body) async {
        sent = body;
        return FunctionResponse(status: 200, data: {'text': 'ok'});
      };
      await AiAdvisorService.instance.askFiqh(
        question: 'q',
        madhhab: null,
        madhhabState: MadhhabSelectionState.unset,
      );
      expect(sent?['madhhab_state'], 'unset');
      expect(sent?.containsKey('madhhab'), isTrue);
      expect(sent?['madhhab'], isNull, reason: 'never a fabricated madhhab');
    });
  });

  group('Dream interpreter', () {
    for (final entry in malformed.entries) {
      test('${entry.key}: no blank interpretation, an honest error', () async {
        reply(entry.value);
        final vm = DreamInterpreterViewModel();
        await vm.sendMessage(userId: 'u', message: 'I dreamt of a river');
        expect(vm.errorMessage, isNotNull);
        expect(
          vm.transcript.where((m) => m.role == DreamMessageRole.assistant),
          isEmpty,
        );
      });
    }
  });
}
