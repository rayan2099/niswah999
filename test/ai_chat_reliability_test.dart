import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/errors/app_error_reporter.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/network/ai_failure.dart';
import 'package:niswah/core/network/ai_function_gateway.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_message.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_thread.dart';
import 'package:niswah/features/ai_assistant/domain/repositories/chat_repository.dart';
import 'package:niswah/features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart';
import 'package:niswah/features/ai_assistant/presentation/viewmodels/chat_view_model.dart';
import 'package:niswah/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Testing feedback 2026-10-30: "تعذر إرسال الرسالة" for every kind of
/// failure, follow-ups losing their meaning, failures shown as replies and
/// repeated source cards. Driven through the AiFunctionGateway test seam:
/// these prove the app's handling, NOT live model quality.
class _Repo implements ChatRepository {
  final saved = <ChatMessage>[];

  @override
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String userId,
    required ChatRole role,
    required String content,
    Map<String, dynamic>? metadata,
    String? messageId,
  }) async {
    final message = ChatMessage(
      id: messageId ?? 'generated',
      threadId: threadId,
      userId: userId,
      role: role,
      content: content,
      metadata: metadata ?? const {},
      createdAt: DateTime.now(),
    );
    // Upsert by id, like the real repository.
    saved.removeWhere((m) => m.id == message.id);
    saved.add(message);
    return message;
  }

  @override
  Future<ChatThread> createThread({
    required String userId,
    required ChatThreadType threadType,
    String? title,
    Map<String, dynamic>? metadata,
    String? threadId,
  }) async => throw UnimplementedError();

  @override
  Future<List<ChatThread>> getThreads({required String userId}) async => [];

  @override
  Future<List<ChatMessage>> getMessages({
    required String threadId,
    required String userId,
  }) async => [];

  @override
  Future<void> deleteThread({
    required String threadId,
    required String userId,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  setUp(() {
    AppLocaleController.instance.setArabic(true);
    AppErrorReporter.onReport = (
      error,
      stack, {
      context,
      feature,
      retryAttempt,
      recordId,
    }) async {};
  });

  tearDown(() {
    AiFunctionGateway.testOverride = null;
    AppErrorReporter.onReport = null;
  });

  group('failure categories', () {
    test('the server category wins; the status is the fallback', () {
      AiFailure f(int status, [Object? body]) =>
          AiFunctionGateway.failureFrom(status, body, 'req-1234567890');
      expect(
        f(503, {'category': 'provider_busy'}).category,
        AiFailureCategory.providerBusy,
      );
      expect(
        f(504, {'category': 'timeout'}).category,
        AiFailureCategory.timeout,
      );
      expect(
        f(503, {'category': 'service_misconfigured'}).category,
        AiFailureCategory.serviceMisconfigured,
      );
      // The platform gateway rejects an expired JWT before the function runs.
      expect(
        f(401, {'msg': 'Invalid JWT'}).category,
        AiFailureCategory.authExpired,
      );
      // A deployment from before categories existed.
      expect(
        f(502, {'error': 'x'}).category,
        AiFailureCategory.providerUnavailable,
      );
      final limited = f(429, {
        'category': 'rate_limited',
        'retryAfterSeconds': 90,
        'correlationId': 'abcdef12-0000-4000-8000-000000000000',
      });
      expect(limited.retryAfter, const Duration(seconds: 90));
      expect(limited.shortReference, 'abcdef12');
      expect(limited.message, contains('2 دقيقة'));
    });

    test(
      'each category has its own message, distinct from the old generic one',
      () {
        final messages = AiFailureCategory.values
            .map((c) => AiFailure(c).message)
            .toSet();
        expect(messages.length, AiFailureCategory.values.length);
        expect(
          messages,
          isNot(contains('تعذر إرسال الرسالة. حاولي مرة أخرى.')),
        );
      },
    );

    test('invokeChat maps transport failures', () async {
      final client = Supabase.instance.client;
      AiFunctionGateway.testOverride = (_, _) async =>
          throw const FunctionException(
            status: 503,
            details: {'category': 'provider_busy', 'correlationId': 'c-1'},
          );
      await expectLater(
        AiFunctionGateway.invokeChat(client, 'ai-assistant-chat', body: {}),
        throwsA(
          isA<AiFailure>()
              .having(
                (f) => f.category,
                'category',
                AiFailureCategory.providerBusy,
              )
              .having((f) => f.correlationId, 'correlationId', 'c-1'),
        ),
      );
      AiFunctionGateway.testOverride = (_, _) async =>
          throw const FunctionsFetchException(details: 'socket closed');
      await expectLater(
        AiFunctionGateway.invokeChat(client, 'ai-assistant-chat', body: {}),
        throwsA(
          isA<AiFailure>().having(
            (f) => f.category,
            'category',
            AiFailureCategory.offline,
          ),
        ),
      );
      AiFunctionGateway.testOverride = (_, _) async =>
          FunctionResponse(status: 200, data: 'not json');
      await expectLater(
        AiFunctionGateway.invokeChat(client, 'ai-assistant-chat', body: {}),
        throwsA(
          isA<AiFailure>().having(
            (f) => f.category,
            'category',
            AiFailureCategory.malformedResponse,
          ),
        ),
      );
    });
  });

  group('general assistant conversation', () {
    late _Repo repo;
    late ChatViewModel vm;
    late List<Map<String, dynamic>?> sent;

    setUp(() {
      repo = _Repo();
      vm = ChatViewModel(repository: repo);
      sent = [];
    });

    Future<void> send(String text) => vm.sendMessage(
      threadId: 't',
      userId: 'u',
      content: text,
      threadType: ChatThreadType.general,
    );

    test('a follow-up carries the earlier turns ("لماذا؟")', () async {
      AiFunctionGateway.testOverride = (_, body) async {
        sent.add(body);
        return FunctionResponse(
          status: 200,
          data: {'text': 'reply ${sent.length}'},
        );
      };
      await send('هل الجماع حلال وقت الدورة؟');
      await send('لماذا؟');
      expect(sent.first!['history'], isEmpty);
      expect(sent.last!['history'], [
        {'role': 'user', 'content': 'هل الجماع حلال وقت الدورة؟'},
        {'role': 'assistant', 'content': 'reply 1'},
      ]);
      expect(sent.last!['content'], 'لماذا؟');
    });

    test(
      'a failure is a failed bubble with a retry, never an assistant reply',
      () async {
        AiFunctionGateway.testOverride = (_, _) async =>
            throw const FunctionException(
              status: 504,
              details: {'category': 'timeout'},
            );
        await send('ممكن تجاوب على السؤال؟');
        expect(vm.messages, hasLength(1));
        final failed = vm.messages.single;
        expect(failed.role, ChatRole.user);
        expect(failed.content, 'ممكن تجاوب على السؤال؟', reason: 'input kept');
        expect(failed.metadata[ChatViewModel.deliveryKey], 'failed');
        expect(vm.lastFailure?.category, AiFailureCategory.timeout);
        expect(vm.errorMessage, AiFailure(AiFailureCategory.timeout).message);
        await pumpEventQueue();
        expect(repo.saved, isEmpty, reason: 'nothing stored for a failed send');

        // Retry succeeds: same message, same id, one reply, stored once.
        AiFunctionGateway.testOverride = (_, body) async {
          sent.add(body);
          return FunctionResponse(status: 200, data: {'text': 'نعم.'});
        };
        await vm.retryMessage(
          message: failed,
          threadType: ChatThreadType.general,
        );
        expect(vm.messages.map((m) => m.role), [
          ChatRole.user,
          ChatRole.assistant,
        ]);
        expect(vm.messages.first.id, failed.id);
        expect(
          vm.messages.first.metadata.containsKey(ChatViewModel.deliveryKey),
          isFalse,
        );
        expect(vm.errorMessage, isNull);
        expect(
          sent.single!['history'],
          isEmpty,
          reason: 'the failed turn is not history',
        );
        await pumpEventQueue();
        expect(repo.saved.where((m) => m.role == ChatRole.user), hasLength(1));
        expect(repo.saved.first.id, failed.id);
      },
    );

    test('a failed message can be taken back into the composer', () async {
      AiFunctionGateway.testOverride = (_, _) async =>
          throw const FunctionsFetchException(details: 'offline');
      await send('سؤالي');
      final text = vm.takeBackFailedMessage(vm.messages.single);
      expect(text, 'سؤالي');
      expect(vm.messages, isEmpty);
      expect(vm.errorMessage, isNull);
    });

    test(
      'a reply pointing to the Fiqh advisor carries the route and the question',
      () async {
        AiFunctionGateway.testOverride = (_, _) async => FunctionResponse(
          status: 200,
          data: {'text': 'هذا سؤال فقهي.', 'route': 'fiqh'},
        );
        await send('هل الجماع حلال وقت الدورة؟');
        final reply = vm.messages.last;
        expect(reply.metadata['route'], 'fiqh');
        expect(reply.metadata['route_question'], 'هل الجماع حلال وقت الدورة؟');
      },
    );

    test('a reply that arrives after an account switch is dropped', () async {
      final release = Completer<void>();
      AiFunctionGateway.testOverride = (_, _) async {
        await release.future;
        return FunctionResponse(status: 200, data: {'text': 'late reply'});
      };
      final pending = send('سؤال');
      await pumpEventQueue();
      await NotificationService.instance.cancelAll(); // sign-out/switch
      release.complete();
      await pending;
      await pumpEventQueue();
      expect(vm.messages.where((m) => m.role == ChatRole.assistant), isEmpty);
      expect(repo.saved, isEmpty);
    });
  });

  group('fiqh advisor failure', () {
    test('is a failed send, not a "sources unreachable" answer', () async {
      final vm = ChatViewModel(repository: _Repo());
      AiFunctionGateway.testOverride = (_, _) async =>
          throw const FunctionException(
            status: 503,
            details: {'category': 'provider_unavailable'},
          );
      await vm.sendMessage(
        threadId: 't',
        userId: 'u',
        content: 'ما حكم الصلاة للحائض؟',
        threadType: ChatThreadType.fiqhAdvisory,
      );
      expect(vm.messages.single.role, ChatRole.user);
      expect(vm.messages.single.metadata[ChatViewModel.deliveryKey], 'failed');
      expect(vm.lastFailure?.category, AiFailureCategory.providerUnavailable);
    });
  });

  group('sources', () {
    test('one entry per document, original order', () {
      final cites = uniqueCitations([
        for (var i = 1; i <= 4; i++)
          {
            'title': 'Urgent Maternal Warning Signs and Symptoms',
            'url': 'https://www.nhs.uk/urgent',
          },
        {'title': 'Recovering from birth', 'url': 'https://www.nhs.uk/birth'},
        {'title': 'Recovering from birth', 'url': 'https://www.nhs.uk/birth'},
        {
          'title': 'Your menstrual cycle',
          'url': 'https://www.womenshealth.gov/cycle',
        },
      ]);
      expect(cites.map((c) => c['title']), [
        'Urgent Maternal Warning Signs and Symptoms',
        'Recovering from birth',
        'Your menstrual cycle',
      ]);
    });

    test(
      'publisher labels are Arabic for known publishers, the address otherwise',
      () {
        expect(
          sourcePublisherLabel('https://www.womenshealth.gov/x', arabic: true),
          'مكتب صحة المرأة الأمريكي',
        );
        expect(
          sourcePublisherLabel('https://islamweb.net/ar/fatwa/1', arabic: true),
          'إسلام ويب',
        );
        expect(
          sourcePublisherLabel('https://g1.islamweb.net/x', arabic: true),
          'إسلام ويب',
        );
        expect(
          sourcePublisherLabel('https://unknown.example.org/a', arabic: true),
          'unknown.example.org',
        );
      },
    );
  });

  group('dream interpreter (quality benchmark, regression)', () {
    test('the full transcript is sent as User/Assistant lines ending in Assistant:', () async {
      final prompts = <String>[];
      AiFunctionGateway.testOverride = (_, body) async {
        prompts.add(body!['prompt'] as String);
        return FunctionResponse(status: 200, data: {'text': 'سؤال توضيحي؟'});
      };
      final vm = DreamInterpreterViewModel();
      await vm.sendMessage(userId: 'u', message: 'رأيت نهرًا');
      await vm.sendMessage(userId: 'u', message: 'كان الماء صافيًا');
      expect(
        prompts.last,
        'User: رأيت نهرًا\nAssistant: سؤال توضيحي؟\nUser: كان الماء صافيًا\nAssistant:',
      );
    });

    test('a long conversation keeps the dream and the latest turns under the limit', () async {
      AiFunctionGateway.testOverride = (_, body) async =>
          FunctionResponse(status: 200, data: {'text': 'ر' * 1500});
      final vm = DreamInterpreterViewModel();
      await vm.sendMessage(userId: 'u', message: 'الحلم الأول');
      for (var i = 0; i < 8; i++) {
        await vm.sendMessage(userId: 'u', message: 'تفصيل $i');
      }
      final prompt = vm.buildTranscriptPromptForTesting();
      expect(
        prompt.length,
        lessThanOrEqualTo(DreamInterpreterViewModel.maxPromptChars),
      );
      expect(prompt, startsWith('User: الحلم الأول'));
      expect(prompt, contains('تفصيل 7'));
      expect(prompt, endsWith('Assistant:'));
    });

    test('a failure keeps the conversation as it was and gives a categorized message', () async {
      AiFunctionGateway.testOverride = (_, _) async =>
          throw const FunctionException(
            status: 504,
            details: {'category': 'timeout'},
          );
      final vm = DreamInterpreterViewModel();
      await vm.sendMessage(userId: 'u', message: 'رأيت نهرًا');
      expect(vm.transcript, isEmpty);
      expect(vm.lastFailure?.category, AiFailureCategory.timeout);
    });
  });
}
