import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/preferences/notification_log_controller.dart';
import '../../../../core/services/notification_service.dart';
import '../../../notifications/domain/entities/notification_preference.dart';
import '../../../ai_advisor/ai_advisor_service.dart';
import '../../../ai_advisor/client_fiqh_state_provider.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/services/dr_niswah_red_flags.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../data/services/dr_niswah_backend_service.dart';

class ChatViewModel extends ChangeNotifier {
  ChatViewModel({ChatRepository? repository})
    : _repository = repository ?? ChatRepositoryImpl();

  final ChatRepository _repository;

  bool isLoading = false;
  bool isSending = false;
  String? errorMessage;
  List<ChatThread> threads = const <ChatThread>[];
  List<ChatMessage> messages = const <ChatMessage>[];
  String? currentThreadId;

  static const _redFlagNotificationBaseId = 900;

  /// Fires an immediate local notification + logs a feed entry the
  /// instant a red-flag concern is detected — more accurate than polling
  /// `flagged_conversations` later, since this runs right on the code
  /// path that already knows a message was flagged.
  void _notifyUrgent() {
    final id = _redFlagNotificationBaseId + (DateTime.now().millisecond % 100);
    const titleAr = 'مخاوف عاجلة في محادثتك';
    const bodyAr = 'تم رصد رسالة تستدعي اهتماماً عاجلاً في محادثتك مع طبيبة.';
    const titleEn = 'Urgent concern in your chat';
    const bodyEn =
        'A message needing urgent attention was flagged in your طبيبة chat.';

    unawaited(
      NotificationService.instance.showNow(
        id: id,
        title: titleAr,
        body: bodyAr,
      ),
    );
    unawaited(
      NotificationLogController.instance.add(
        NotificationLogEntry(
          id: 'redflag_${DateTime.now().microsecondsSinceEpoch}',
          type: NotificationType.wellbeing,
          titleAr: titleAr,
          bodyAr: bodyAr,
          titleEn: titleEn,
          bodyEn: bodyEn,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> loadThreads({required String userId}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      threads = await _repository.getThreads(userId: userId);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Clears the active thread locally without creating one in the backend
  /// yet — a real thread row is only created lazily on the first message
  /// sent (see the screen's send handler), so an abandoned "new chat" tap
  /// never leaves an empty thread cluttering history.
  void startNewChat() {
    currentThreadId = null;
    messages = const <ChatMessage>[];
    notifyListeners();
  }

  Future<void> createThread({
    required String userId,
    required ChatThreadType threadType,
    String? title,
  }) async {
    try {
      final thread = await _repository.createThread(
        userId: userId,
        threadType: threadType,
        title: title,
      );
      currentThreadId = thread.id;
      messages = const <ChatMessage>[];
      await loadThreads(userId: userId);
    } catch (error) {
      final now = DateTime.now();
      final localThread = ChatThread(
        id: 'local_${threadType.name}_${now.microsecondsSinceEpoch}',
        userId: userId,
        title: title ?? 'New conversation',
        threadType: threadType,
        status: ChatThreadStatus.active,
        metadata: const {'persistence': 'local'},
        createdAt: now,
        updatedAt: now,
      );
      currentThreadId = localThread.id;
      threads = [localThread, ...threads];
      messages = const [];
      errorMessage = null;
      notifyListeners();
    }
  }

  Future<void> deleteThread({
    required String threadId,
    required String userId,
  }) async {
    try {
      await _repository.deleteThread(threadId: threadId, userId: userId);
      threads = threads.where((thread) => thread.id != threadId).toList();
      if (currentThreadId == threadId) {
        currentThreadId = null;
        messages = const <ChatMessage>[];
      }
      notifyListeners();
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> loadMessages({
    required String threadId,
    required String userId,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      currentThreadId = threadId;
      messages = await _repository.getMessages(
        threadId: threadId,
        userId: userId,
      );
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage({
    required String threadId,
    required String userId,
    required String content,
    required ChatThreadType threadType,
  }) async {
    if (content.trim().isEmpty) {
      return;
    }

    isSending = true;
    errorMessage = null;
    notifyListeners();

    final now = DateTime.now();
    final optimisticUserMessage = ChatMessage(
      id: 'local_user_${now.microsecondsSinceEpoch}',
      threadId: threadId,
      userId: userId,
      role: ChatRole.user,
      content: content,
      metadata: const {},
      createdAt: now,
    );
    messages = [...messages, optimisticUserMessage];
    notifyListeners();

    try {
      switch (threadType) {
        case ChatThreadType.drNiswah:
          // No direct-to-Gemini fallback: if the backend is unreachable,
          // fail clearly rather than silently downgrading to an unaudited,
          // client-side call for a safety-relevant conversation (closes
          // SEC-001/AB-002 for this feature).
          if (!DrNiswahBackendService.instance.isAvailable) {
            throw StateError(
              'Dr. Niswah chat is temporarily unavailable. Please try again shortly.',
            );
          }
          await sendViaDrNiswahBackendForTesting(
            threadId: threadId,
            userId: userId,
            content: content,
          );
        case ChatThreadType.fiqhAdvisory:
          await _sendViaFiqhAdvisor(
            threadId: threadId,
            userId: userId,
            content: content,
          );
        case ChatThreadType.dreamInterpreter:
        case ChatThreadType.general:
          await _sendViaGeneralAssistant(
            threadId: threadId,
            userId: userId,
            content: content,
          );
      }
    } catch (error, stack) {
      errorMessage = error.toString();
      AppErrorReporter.report(
        error,
        stack,
        context: 'ChatViewModel.sendMessage',
      );
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  /// Backend path: the edge function owns the persona system prompt, the
  /// pregnancy-context lookup, the red-flag check, and the Gemini call, and
  /// persists both chat_messages rows itself.
  ///
  /// Public (not `_`-prefixed) and `@visibleForTesting` — a real, live
  /// production code path, exposed under this name specifically so its
  /// PJ-003 dual-signal fix can be exercised directly in a unit test:
  /// `DrNiswahBackendService.instance` is a hardcoded singleton with no DI
  /// seam, and throws deterministically when Supabase isn't configured
  /// (the default in a plain test environment), which is exactly the
  /// failure this method needs to be driven through to prove the fix.
  /// Same idiom as this file's own `persistUserMessageForTesting`.
  @visibleForTesting
  Future<void> sendViaDrNiswahBackendForTesting({
    required String threadId,
    required String userId,
    required String content,
  }) async {
    // Independent of the network call below, so a red-flag symptom is
    // never silently dropped if the backend is unreachable.
    final isRedFlagLocally = DrNiswahRedFlags.matches(content);

    try {
      final response = await DrNiswahBackendService.instance.send(
        threadId: threadId,
        content: content,
      );
      final assistantMessage = ChatMessage(
        id: 'local_assistant_${DateTime.now().microsecondsSinceEpoch}',
        threadId: threadId,
        userId: userId,
        role: ChatRole.assistant,
        content: response.reply.isNotEmpty
            ? response.reply
            : DrNiswahRedFlags.bannerTextAr,
        metadata: {'source': 'dr_niswah_backend', 'urgent': response.urgent},
        createdAt: DateTime.now(),
      );
      messages = [...messages, assistantMessage];
      notifyListeners();
      if (response.urgent) _notifyUrgent();
    } catch (error, stack) {
      if (isRedFlagLocally) {
        final bannerMessage = ChatMessage(
          id: 'local_urgent_${DateTime.now().microsecondsSinceEpoch}',
          threadId: threadId,
          userId: userId,
          role: ChatRole.assistant,
          content: DrNiswahRedFlags.bannerTextAr,
          metadata: const {'urgent': true, 'source': 'red_flag_local_fallback'},
          createdAt: DateTime.now(),
        );
        messages = [...messages, bannerMessage];
        notifyListeners();
        _notifyUrgent();
        // PJ-003: the reassuring banner above is already a complete,
        // coherent response to this failure for an urgent message — it
        // must not also be followed by a generic/alarming `errorMessage`
        // from the outer sendMessage() catch, which would previously
        // contradict the banner on the same screen for the same failed
        // request. The failure is still reported (never silently
        // discarded) directly here instead of relying on the outer
        // catch, since this path deliberately does not reach it anymore.
        AppErrorReporter.report(
          error,
          stack,
          context: 'ChatViewModel._sendViaDrNiswahBackend (red-flag fallback)',
          feature: 'ai_assistant',
        );
        return;
      }
      rethrow;
    }
  }

  /// Fiqh Advisor thread: server-side (`fiqh-advisor-chat` Edge Function)
  /// via [AiAdvisorService], which owns the Google-Search-grounded system
  /// prompt and the trusted-citation filter.
  Future<void> _sendViaFiqhAdvisor({
    required String threadId,
    required String userId,
    required String content,
  }) async {
    final persistUser = persistUserMessageForTesting(
      threadId: threadId,
      userId: userId,
      content: content,
    );

    // Fiqh Remediation Wave 1: null whenever the user's Madhhab is
    // UNSET/UNKNOWN — never a fabricated value. See Section F.
    final madhhabState = MadhhabController.instance.state;
    final selectedMadhhab = MadhhabController.instance.selectedOrNull;

    // AICTX remediation: best-effort, never blocking — a failure here
    // (no history, a network error) just means the field is omitted.
    final clientFiqhState = await ClientFiqhStateProvider()
        .currentClassification(selectedMadhhab);
    final result = await AiAdvisorService.instance.askFiqh(
      question: content,
      madhhab: selectedMadhhab,
      madhhabState: madhhabState,
      clientFiqhState: clientFiqhState,
    );

    final metadata = {
      'source': 'gemini',
      'grounded': true,
      'madhhab': selectedMadhhab?.name,
      'madhhab_state': madhhabState.name,
      'citations': result.citations.map((item) => item.toJson()).toList(),
    };
    await showAssistantReplyAndPersistForTesting(
      threadId: threadId,
      userId: userId,
      text: result.text,
      metadata: metadata,
      persistUser: persistUser,
    );
  }

  /// General assistant / dream-interpreter thread types: server-side
  /// (`ai-assistant-chat` Edge Function), which owns the system prompt.
  Future<void> _sendViaGeneralAssistant({
    required String threadId,
    required String userId,
    required String content,
  }) async {
    final client = NiswahSupabase.clientOrNull;
    if (client == null) {
      throw StateError('Supabase is not initialized.');
    }

    final persistUser = persistUserMessageForTesting(
      threadId: threadId,
      userId: userId,
      content: content,
    );

    final response = await client.functions.invoke(
      'ai-assistant-chat',
      // AICTX remediation: the general assistant previously received no
      // context at all. madhhab is cheap and always known client-side
      // (MadhhabController), so it's sent unconditionally now — the
      // Edge Function treats it as optional either way. Fiqh Remediation
      // Wave 1: null/'unset'/'unknown' are sent as-is, never a fabricated
      // madhhab (Section F).
      body: {
        'content': content,
        'madhhab': MadhhabController.instance.selectedOrNull?.name,
        'madhhab_state': MadhhabController.instance.state.name,
      },
    );
    final data = response.data;
    if (data is! Map || response.status != 200) {
      final error = data is Map ? data['error']?.toString() : null;
      throw StateError(
        error ?? 'AI assistant service failed (${response.status}).',
      );
    }

    await showAssistantReplyAndPersistForTesting(
      threadId: threadId,
      userId: userId,
      text: data['text']?.toString() ?? '',
      metadata: const {'source': 'gemini', 'grounded': false},
      persistUser: persistUser,
    );
  }

  /// Persists the user's own message in the background — a failure here
  /// must never block or hide the visible reply (DUAL/SPLIT AUTHORITY: the
  /// live response is response-delivery-authoritative; `chat_messages` is
  /// a separate, best-effort durable-history concern), but it must not be
  /// silently swallowed either (RR-001/DI-002: previously discarded via
  /// `onError: (_) => null` with zero observability — a message could
  /// vanish from persisted chat history forever with no trace anywhere).
  /// `messageId` is a stable, caller-generated id so persistence is safe
  /// to retry without risking a duplicate row (same pattern used by
  /// `CommunityFeedViewModel`/`DreamInterpreterViewModel`).
  ///
  /// Public (not `_`-prefixed) and `@visibleForTesting` — this is a real,
  /// live production code path (called from `_sendViaFiqhAdvisor`/
  /// `_sendViaGeneralAssistant`), exposed under this name specifically so
  /// its retry/observability behavior can be exercised directly in a unit
  /// test with an injected fake [ChatRepository], without needing to mock
  /// `AiAdvisorService`/Supabase Edge Functions (Reliability Evidence
  /// Closure wave, 2026-09-06). Same idiom as this file's own
  /// `SecureLocalStore.debugUserIdOverride`/`scrubSecretsForSentry`.
  @visibleForTesting
  Future<ChatMessage?> persistUserMessageForTesting({
    required String threadId,
    required String userId,
    required String content,
  }) {
    final messageId = const Uuid().v4();
    return _repository
        .sendMessage(
          threadId: threadId,
          userId: userId,
          role: ChatRole.user,
          content: content,
          messageId: messageId,
        )
        .then<ChatMessage?>(
          (message) => message,
          onError: (error, stack) {
            AppErrorReporter.report(
              error,
              stack,
              context: 'ChatViewModel._persistUserMessage',
              feature: 'ai_assistant',
              recordId: messageId,
            );
            return null;
          },
        );
  }

  /// Public/`@visibleForTesting` for the same reason as
  /// [persistUserMessageForTesting] — see its doc comment.
  @visibleForTesting
  Future<void> showAssistantReplyAndPersistForTesting({
    required String threadId,
    required String userId,
    required String text,
    required Map<String, dynamic> metadata,
    required Future<ChatMessage?> persistUser,
  }) async {
    final optimisticAssistantMessage = ChatMessage(
      id: 'local_assistant_${DateTime.now().microsecondsSinceEpoch}',
      threadId: threadId,
      userId: userId,
      role: ChatRole.assistant,
      content: text,
      metadata: metadata,
      createdAt: DateTime.now(),
    );
    messages = [...messages, optimisticAssistantMessage];
    notifyListeners();

    final assistantMessageId = const Uuid().v4();
    unawaited(() async {
      await persistUser;
      try {
        await _repository.sendMessage(
          threadId: threadId,
          userId: userId,
          role: ChatRole.assistant,
          content: text,
          metadata: metadata,
          messageId: assistantMessageId,
        );
      } catch (error, stack) {
        // The live response remains visible if history persistence fails
        // (unchanged) — but the failure itself must be observable, not
        // silently discarded (RR-001/DI-002).
        AppErrorReporter.report(
          error,
          stack,
          context: 'ChatViewModel._showAssistantReplyAndPersist',
          feature: 'ai_assistant',
          recordId: assistantMessageId,
        );
      }
    }());
  }
}
