import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/preferences/notification_log_controller.dart';
import '../../../../core/services/gemini_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../notifications/domain/entities/notification_preference.dart';
import '../../../ai_advisor/ai_advisor_service.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/services/dr_niswah_persona.dart';
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
      final useBackend =
          threadType == ChatThreadType.drNiswah &&
          DrNiswahBackendService.instance.isAvailable;

      if (useBackend) {
        await _sendViaDrNiswahBackend(
          threadId: threadId,
          userId: userId,
          content: content,
        );
      } else {
        await _sendViaDirectModel(
          threadId: threadId,
          userId: userId,
          content: content,
          threadType: threadType,
        );
      }
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  /// Backend path: the edge function owns the persona system prompt, the
  /// pregnancy-context lookup, the red-flag check, and the Gemini call, and
  /// persists both chat_messages rows itself.
  Future<void> _sendViaDrNiswahBackend({
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
    } catch (error) {
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
      }
      rethrow;
    }
  }

  /// Direct-to-Gemini fallback, used for fiqh/general threads always, and
  /// for Doctor Niswah when the Supabase backend isn't configured.
  Future<void> _sendViaDirectModel({
    required String threadId,
    required String userId,
    required String content,
    required ChatThreadType threadType,
  }) async {
    final isRedFlag =
        threadType == ChatThreadType.drNiswah &&
        DrNiswahRedFlags.matches(content);

    final persistUser = _repository
        .sendMessage(
          threadId: threadId,
          userId: userId,
          role: ChatRole.user,
          content: content,
        )
        .then<ChatMessage?>((message) => message, onError: (_) => null);

    // Shown regardless of whether the LLM call below succeeds or fails.
    if (isRedFlag) {
      final bannerMessage = ChatMessage(
        id: 'local_urgent_${DateTime.now().microsecondsSinceEpoch}',
        threadId: threadId,
        userId: userId,
        role: ChatRole.assistant,
        content: DrNiswahRedFlags.bannerTextAr,
        metadata: const {'urgent': true, 'source': 'red_flag_check'},
        createdAt: DateTime.now(),
      );
      messages = [...messages, bannerMessage];
      _notifyUrgent();
      notifyListeners();
      unawaited(() async {
        await persistUser;
        try {
          await _repository.sendMessage(
            threadId: threadId,
            userId: userId,
            role: ChatRole.assistant,
            content: bannerMessage.content,
            metadata: bannerMessage.metadata,
          );
        } catch (_) {
          // The live banner remains visible if history persistence fails.
        }
      }());
    }

    final result = threadType == ChatThreadType.fiqhAdvisory
        ? await AiAdvisorService.instance.askFiqh(
            question: content,
            madhhab: MadhhabController.instance.selected,
          )
        : await GeminiService.instance.generateText(
            prompt: content,
            systemInstruction: threadType == ChatThreadType.drNiswah
                ? await DrNiswahPersona.buildSystemInstruction(userId: userId)
                : '''
You are Niswah AI, a concise and supportive general assistant. Do not provide medical diagnoses or definitive religious rulings; direct those questions to the dedicated advisors.
Always reply in the same language the user's message is written in.
Write in plain prose only. Never use markdown syntax: no #, ##, ###, **, *, or numbered/bulleted list characters. The app displays raw text, not rendered markdown.
''',
          );

    final metadata = {
      'source': 'gemini',
      'grounded': threadType == ChatThreadType.fiqhAdvisory,
      'madhhab': MadhhabController.instance.selected.name,
      'citations': result.citations.map((item) => item.toJson()).toList(),
    };
    final optimisticAssistantMessage = ChatMessage(
      id: 'local_assistant_${DateTime.now().microsecondsSinceEpoch}',
      threadId: threadId,
      userId: userId,
      role: ChatRole.assistant,
      content: result.text,
      metadata: metadata,
      createdAt: DateTime.now(),
    );
    messages = [...messages, optimisticAssistantMessage];
    notifyListeners();

    unawaited(() async {
      await persistUser;
      try {
        await _repository.sendMessage(
          threadId: threadId,
          userId: userId,
          role: ChatRole.assistant,
          content: result.text,
          metadata: metadata,
        );
      } catch (_) {
        // The live response remains visible if history persistence fails.
      }
    }());
  }
}
