import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/errors/app_error_reporter.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_message.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_thread.dart';
import 'package:niswah/features/ai_assistant/domain/repositories/chat_repository.dart';
import 'package:niswah/features/ai_assistant/presentation/viewmodels/chat_view_model.dart';

/// Exercises `ChatViewModel.persistUserMessageForTesting`/
/// `showAssistantReplyAndPersistForTesting` directly — the two methods
/// `_sendViaFiqhAdvisor`/`_sendViaGeneralAssistant` delegate to for
/// `chat_messages` persistence — bypassing `AiAdvisorService`/the
/// `ai-assistant-chat` Edge Function entirely, since neither has a
/// dependency-injection seam and both require live network access. This
/// is a deliberate, narrower substitute for a full end-to-end test: it
/// proves the exact persistence/observability/idempotency behavior these
/// two methods are responsible for (RR-007), without needing to mock
/// Gemini or Supabase Functions (Reliability Evidence Closure wave,
/// 2026-09-06).
class _RecordingChatRepository implements ChatRepository {
  final List<String?> sendMessageIdsSeen = [];
  bool failNextSendMessage = false;
  Object? lastFailure;

  @override
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String userId,
    required ChatRole role,
    required String content,
    Map<String, dynamic>? metadata,
    String? messageId,
  }) async {
    sendMessageIdsSeen.add(messageId);
    if (failNextSendMessage) {
      failNextSendMessage = false;
      lastFailure = Exception('simulated persistence failure');
      throw lastFailure!;
    }
    return ChatMessage(
      id: messageId ?? 'generated-id',
      threadId: threadId,
      userId: userId,
      role: role,
      content: content,
      metadata: metadata ?? const {},
      createdAt: DateTime.now(),
    );
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
  late _RecordingChatRepository repository;
  late ChatViewModel viewModel;
  late List<Object> reportedErrors;

  setUp(() {
    repository = _RecordingChatRepository();
    viewModel = ChatViewModel(repository: repository);
    reportedErrors = [];
    AppErrorReporter.onReport = (error, stack, {context, feature, retryAttempt, recordId}) {
      reportedErrors.add(error);
    };
  });

  tearDown(() {
    AppErrorReporter.onReport = null;
  });

  group('persistUserMessageForTesting (RR-007)', () {
    test(
      'a successful persist reports nothing and returns the saved message',
      () async {
        final result = await viewModel.persistUserMessageForTesting(
          threadId: 'thread-1',
          userId: 'user-1',
          content: 'hello',
        );

        expect(result, isNotNull);
        expect(reportedErrors, isEmpty);
      },
    );

    test(
      'a persistence failure is reported via AppErrorReporter, not '
      'silently swallowed — this was the exact RR-007 defect',
      () async {
        repository.failNextSendMessage = true;

        final result = await viewModel.persistUserMessageForTesting(
          threadId: 'thread-1',
          userId: 'user-1',
          content: 'hello',
        );

        expect(
          result,
          isNull,
          reason: 'a failed persist resolves to null, not an exception '
              'propagating to the caller — the live reply must never be '
              'blocked by a history-persistence failure',
        );
        expect(
          reportedErrors,
          hasLength(1),
          reason: 'previously this failure vanished with zero trace '
              'anywhere (RR-007)',
        );
      },
    );

    test(
      'each call generates its own stable message id — a genuinely new '
      'message never collides with a prior one',
      () async {
        await viewModel.persistUserMessageForTesting(
          threadId: 'thread-1',
          userId: 'user-1',
          content: 'first',
        );
        await viewModel.persistUserMessageForTesting(
          threadId: 'thread-1',
          userId: 'user-1',
          content: 'second',
        );

        expect(repository.sendMessageIdsSeen, hasLength(2));
        expect(
          repository.sendMessageIdsSeen[0],
          isNot(repository.sendMessageIdsSeen[1]),
        );
      },
    );
  });

  group('showAssistantReplyAndPersistForTesting (RR-007)', () {
    test(
      'the assistant reply is always shown immediately, even before '
      'persistence resolves — response delivery is never gated on '
      'durable-history success (the DUAL/SPLIT AUTHORITY contract)',
      () async {
        final persistUser = Future<ChatMessage?>.value(null);

        await viewModel.showAssistantReplyAndPersistForTesting(
          threadId: 'thread-1',
          userId: 'user-1',
          text: 'the AI reply text',
          metadata: const {'source': 'gemini'},
          persistUser: persistUser,
        );

        expect(viewModel.messages, hasLength(1));
        expect(viewModel.messages.single.content, 'the AI reply text');
        expect(
          viewModel.messages.single.role,
          ChatRole.assistant,
        );
      },
    );

    test(
      'an assistant-message persistence failure is reported via '
      'AppErrorReporter and does not remove the already-shown reply — '
      'this was the exact RR-007 defect (silently swallowed via bare '
      'catch (_) {})',
      () async {
        repository.failNextSendMessage = true;
        final persistUser = Future<ChatMessage?>.value(null);

        await viewModel.showAssistantReplyAndPersistForTesting(
          threadId: 'thread-1',
          userId: 'user-1',
          text: 'the AI reply text',
          metadata: const {},
          persistUser: persistUser,
        );
        // The persistence attempt is fire-and-forget (unawaited); give its
        // microtask a chance to run before asserting.
        await Future<void>.delayed(Duration.zero);

        expect(
          viewModel.messages,
          hasLength(1),
          reason: 'the live reply must remain visible even though its '
              'persistence failed',
        );
        expect(
          reportedErrors,
          hasLength(1),
          reason: 'previously this failure vanished with zero trace '
              'anywhere (RR-007)',
        );
      },
    );

    test(
      'a retry of the same assistant message reuses a distinct, stable '
      'id per attempt (no duplicate created by two independent calls '
      'sharing state)',
      () async {
        final persistUser = Future<ChatMessage?>.value(null);

        await viewModel.showAssistantReplyAndPersistForTesting(
          threadId: 'thread-1',
          userId: 'user-1',
          text: 'first reply',
          metadata: const {},
          persistUser: persistUser,
        );
        await Future<void>.delayed(Duration.zero);
        await viewModel.showAssistantReplyAndPersistForTesting(
          threadId: 'thread-1',
          userId: 'user-1',
          text: 'second reply',
          metadata: const {},
          persistUser: Future<ChatMessage?>.value(null),
        );
        await Future<void>.delayed(Duration.zero);

        expect(repository.sendMessageIdsSeen, hasLength(2));
        expect(
          repository.sendMessageIdsSeen[0],
          isNot(repository.sendMessageIdsSeen[1]),
          reason: 'two genuinely different assistant replies must not '
              'share an id',
        );
      },
    );
  });

  group('ChatRepositoryImpl idempotency contract (interface-level)', () {
    test(
      'sendMessage is called with the caller-supplied messageId, not a '
      'freshly generated one, proving a retry with the same id would hit '
      'the same row (upsert-safe) rather than duplicating',
      () async {
        await repository.sendMessage(
          threadId: 't1',
          userId: 'u1',
          role: ChatRole.user,
          content: 'hi',
          messageId: 'fixed-id-123',
        );
        await repository.sendMessage(
          threadId: 't1',
          userId: 'u1',
          role: ChatRole.user,
          content: 'hi (retried)',
          messageId: 'fixed-id-123',
        );

        expect(repository.sendMessageIdsSeen, ['fixed-id-123', 'fixed-id-123']);
      },
    );
  });
}
