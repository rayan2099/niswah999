import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/pregnancy_status_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_thread.dart';
import '../viewmodels/chat_view_model.dart';

String _ai(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// The real signed-in user id where available. `chat_threads`/`chat_messages`
/// are RLS-gated on `auth.uid() = user_id`, so writing a placeholder string
/// here fails for any real session — 'demo-user' only remains as a fallback
/// for local/dev use without Supabase configured.
String _currentUserId() =>
    NiswahSupabase.clientOrNull?.auth.currentUser?.id ?? 'demo-user';

String _formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}

enum NiswahAssistantMode { general, health, fiqhAdvisory }

ChatThreadType chatThreadTypeFor(NiswahAssistantMode mode) => switch (mode) {
  NiswahAssistantMode.health => ChatThreadType.drNiswah,
  NiswahAssistantMode.general => ChatThreadType.general,
  NiswahAssistantMode.fiqhAdvisory => ChatThreadType.fiqhAdvisory,
};

String defaultThreadTitleFor(NiswahAssistantMode mode) => switch (mode) {
  NiswahAssistantMode.health => 'Doctor Niswah',
  NiswahAssistantMode.general => 'Niswah AI',
  NiswahAssistantMode.fiqhAdvisory => 'Fiqh advisory',
};

Color _modeAccent(NiswahAssistantMode mode) => switch (mode) {
  NiswahAssistantMode.health => const Color(0xFF08705E),
  NiswahAssistantMode.fiqhAdvisory => const Color(0xFF9A6700),
  NiswahAssistantMode.general => const Color(0xFFE91E4D),
};

/// Which surface is showing: the conversations picker (when past chats
/// exist for this mode) or the live chat. Distinct from the view model's
/// data — leaving an active chat to browse history shouldn't clear it.
enum _ChatView { picker, chat }

class DrNiswahChatScreen extends StatefulWidget {
  const DrNiswahChatScreen({
    super.key,
    this.mode = NiswahAssistantMode.general,
  });

  final NiswahAssistantMode mode;
  @override
  State<DrNiswahChatScreen> createState() => _DrNiswahChatScreenState();
}

class _DrNiswahChatScreenState extends State<DrNiswahChatScreen> {
  late final ChatViewModel _model;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  var _lastMessageCount = 0;
  var _userNavigated = false;
  // Defaults to the composer, since a first-ever open usually has no
  // history yet — avoids ever flashing the picker for the common case.
  // A cached hint from a previous open or the network load then corrects
  // this to the picker almost immediately when there actually is history,
  // so returning users don't see a flash in that direction either.
  _ChatView _view = _ChatView.chat;

  String get _historyPrefsKey =>
      'chat_has_history_${_currentUserId()}_${chatThreadTypeFor(widget.mode).name}';

  @override
  void initState() {
    super.initState();
    _model = ChatViewModel();
    _model.addListener(_followNewestMessage);
    unawaited(_restoreCachedView());
    _model.loadThreads(userId: _currentUserId()).then((_) {
      if (!mounted) return;
      final type = chatThreadTypeFor(widget.mode);
      final hasHistory = _model.threads.any(
        (thread) => thread.threadType == type,
      );
      unawaited(_cacheHasHistory(hasHistory));
      if (_userNavigated) return;
      final correctView = hasHistory ? _ChatView.picker : _ChatView.chat;
      if (_view != correctView) setState(() => _view = correctView);
    });
  }

  Future<void> _restoreCachedView() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _userNavigated) return;
    if (prefs.getBool(_historyPrefsKey) == true) {
      setState(() => _view = _ChatView.picker);
    }
  }

  Future<void> _cacheHasHistory(bool hasHistory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_historyPrefsKey, hasHistory);
  }

  @override
  void dispose() {
    _model.removeListener(_followNewestMessage);
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _followNewestMessage() {
    if (_model.messages.length == _lastMessageCount) return;
    _lastMessageCount = _model.messages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _openPicker() {
    _userNavigated = true;
    setState(() => _view = _ChatView.picker);
  }

  void _startNewFromPicker() {
    _userNavigated = true;
    _model.startNewChat();
    setState(() => _view = _ChatView.chat);
  }

  Future<void> _resumeFromPicker(ChatThread thread) async {
    _userNavigated = true;
    setState(() => _view = _ChatView.chat);
    await _model.loadMessages(threadId: thread.id, userId: _currentUserId());
  }

  Future<void> _deleteFromPicker(ChatThread thread) async {
    await _model.deleteThread(threadId: thread.id, userId: _currentUserId());
    final type = chatThreadTypeFor(widget.mode);
    if (mounted && !_model.threads.any((t) => t.threadType == type)) {
      _userNavigated = true;
      setState(() => _view = _ChatView.chat);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _model,
    builder: (_, _) => Scaffold(
      backgroundColor: const Color(0xFFFFFAF8),
      body: SafeArea(
        child: Column(
          children: [
            _AiHeader(
              mode: widget.mode,
              onClose: () => Navigator.maybePop(context),
              onHistory:
                  _view == _ChatView.chat &&
                      _model.threads.any(
                        (t) => t.threadType == chatThreadTypeFor(widget.mode),
                      )
                  ? _openPicker
                  : null,
              onNewChat: _view == _ChatView.chat && _model.messages.isNotEmpty
                  ? _model.startNewChat
                  : null,
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    ),
  );

  Widget _buildBody(BuildContext context) {
    switch (_view) {
      case _ChatView.picker:
        return _ConversationsPicker(
          mode: widget.mode,
          threads: _model.threads
              .where(
                (t) => t.threadType == chatThreadTypeFor(widget.mode),
              )
              .toList(),
          isLoading: _model.isLoading,
          onNewChat: _startNewFromPicker,
          onSelect: _resumeFromPicker,
          onDelete: _deleteFromPicker,
        );
      case _ChatView.chat:
        return _ChatBody(
          mode: widget.mode,
          model: _model,
          controller: _controller,
          scrollController: _scrollController,
          onSend: _send,
        );
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _model.isSending) return;
    _controller.clear();
    var threadId = _model.currentThreadId;
    if (threadId == null) {
      await _model.createThread(
        userId: _currentUserId(),
        threadType: chatThreadTypeFor(widget.mode),
        title: defaultThreadTitleFor(widget.mode),
      );
      threadId = _model.currentThreadId;
    }
    if (threadId == null) return;
    await _model.sendMessage(
      threadId: threadId,
      userId: _currentUserId(),
      content: text,
      threadType: chatThreadTypeFor(widget.mode),
    );
  }
}

class _ChatBody extends StatelessWidget {
  const _ChatBody({
    required this.mode,
    required this.model,
    required this.controller,
    required this.scrollController,
    required this.onSend,
  });

  final NiswahAssistantMode mode;
  final ChatViewModel model;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (mode == NiswahAssistantMode.fiqhAdvisory)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8C978)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_outlined, color: Color(0xFF9A6700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _ai(
                    'Answers use your selected Madhhab and Google Search grounding. Ambiguous cases are escalated to a qualified scholar.',
                    'تراعي الإجابات مذهبكِ المختار وتستند إلى البحث الموثق، وتُحال الحالات الملتبسة إلى مختصة شرعية.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF704D0A),
                    fontSize: 11,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      Expanded(
        child: model.messages.isEmpty
            ? _Welcome(
                mode: mode,
                onPrompt: (text) {
                  controller.text = text;
                  controller.selection = TextSelection.collapsed(
                    offset: text.length,
                  );
                },
              )
            : ListView.builder(
                controller: scrollController,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                itemCount: model.messages.length + (model.isSending ? 1 : 0),
                itemBuilder: (_, i) => i < model.messages.length
                    ? _Message(message: model.messages[i])
                    : const _TypingIndicator(),
              ),
      ),
      if (model.errorMessage != null)
        Container(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFCDD5)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.haid,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _ai(
                    'The message could not be sent. Please try again.',
                    'تعذر إرسال الرسالة. حاولي مرة أخرى.',
                  ),
                  style: const TextStyle(color: Color(0xFF9F1239), fontSize: 9),
                ),
              ),
            ],
          ),
        ),
      _Composer(
        mode: mode,
        enabled: NiswahSupabase.clientOrNull != null,
        controller: controller,
        busy: model.isSending,
        onSend: onSend,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
        child: Text(
          _ai(
            mode == NiswahAssistantMode.fiqhAdvisory
                ? 'AI guidance is not a binding fatwa. Review cited sources and consult a qualified scholar for complex cases.'
                : mode == NiswahAssistantMode.health
                ? 'Doctor Niswah offers health guidance, not diagnosis or emergency care. Consult a licensed clinician when needed.'
                : 'Niswah AI offers general guidance, not medical diagnoses or religious rulings.',
            mode == NiswahAssistantMode.fiqhAdvisory
                ? 'الإرشاد الآلي ليس فتوى ملزمة. راجعي المصادر واستشيري مختصة شرعية للحالات المعقدة.'
                : mode == NiswahAssistantMode.health
                ? 'الطبيبة نسوة تقدم إرشاداً صحياً عاماً، وليس تشخيصاً أو رعاية طارئة. راجعي طبيبة مختصة عند الحاجة.'
                : 'نسوة AI للمعلومات العامة، وليست بديلاً عن التشخيص الطبي أو الفتوى الشرعية.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFB99A91), fontSize: 8.5, height: 1.35),
        ),
      ),
    ],
  );
}

class _ConversationsPicker extends StatelessWidget {
  const _ConversationsPicker({
    required this.mode,
    required this.threads,
    required this.isLoading,
    required this.onNewChat,
    required this.onSelect,
    required this.onDelete,
  });

  final NiswahAssistantMode mode;
  final List<ChatThread> threads;
  final bool isLoading;
  final VoidCallback onNewChat;
  final ValueChanged<ChatThread> onSelect;
  final ValueChanged<ChatThread> onDelete;

  Future<void> _confirmDelete(BuildContext context, ChatThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_ai('Delete this chat?', 'حذف هذه المحادثة؟')),
        content: Text(
          _ai(
            'This will remove the conversation and its messages permanently.',
            'سيؤدي هذا إلى حذف المحادثة ورسائلها نهائياً.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_ai('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _ai('Delete', 'حذف'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete(thread);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _modeAccent(mode);
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: threads.isEmpty
              ? Center(
                  child: isLoading
                      ? SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                            semanticsLabel: _ai(
                              'Loading conversations',
                              'جارٍ تحميل المحادثات',
                            ),
                          ),
                        )
                      : Text(
                          _ai('No past chats yet', 'لا توجد محادثات سابقة بعد'),
                          style: const TextStyle(color: Color(0xFF9D7B72)),
                        ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                  itemCount: threads.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    final thread = threads[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: accent,
                          size: 17,
                        ),
                      ),
                      title: Text(
                        thread.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7F1D3C),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        _formatDate(thread.updatedAt),
                        style: const TextStyle(
                          color: Color(0xFF9D7B72),
                          fontSize: 10,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                        ),
                        tooltip: _ai('Delete conversation', 'حذف المحادثة'),
                        onPressed: () => _confirmDelete(context, thread),
                      ),
                      onTap: () => onSelect(thread),
                    );
                  },
                ),
        ),
        Expanded(
          flex: 2,
          child: Center(
            child: InkWell(
              onTap: onNewChat,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_rounded, color: Colors.white, size: 38),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        _ai('New', 'محادثة جديدة'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AiHeader extends StatelessWidget {
  const _AiHeader({
    required this.mode,
    required this.onClose,
    required this.onHistory,
    required this.onNewChat,
  });
  final NiswahAssistantMode mode;
  final VoidCallback onClose;
  final VoidCallback? onHistory;
  final VoidCallback? onNewChat;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 11),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFFFECE8))),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: Color(0xFF7F1D3C)),
          tooltip: _ai('Close', 'إغلاق'),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: mode == NiswahAssistantMode.health
                  ? const [Color(0xFF0F9F83), Color(0xFF08705E)]
                  : mode == NiswahAssistantMode.fiqhAdvisory
                  ? const [Color(0xFFB7791F), Color(0xFF805A16)]
                  : const [Color(0xFFEE315A), Color(0xFFB92564)],
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            mode == NiswahAssistantMode.health
                ? Icons.medical_services_outlined
                : mode == NiswahAssistantMode.fiqhAdvisory
                ? Icons.menu_book_outlined
                : Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mode == NiswahAssistantMode.health
                    ? _ai('Doctor Niswah', 'الطبيبة نسوة')
                    : mode == NiswahAssistantMode.fiqhAdvisory
                    ? _ai('Fiqh advisor', 'المستشارة الفقهية')
                    : _ai('Niswah AI', 'نسوة AI'),
                style: TextStyle(
                  color: Color(0xFF7F1D3C),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 2),
              Row(
                children: [
                  CircleAvatar(radius: 3, backgroundColor: Color(0xFF22C55E)),
                  SizedBox(width: 5),
                  Text(
                    _ai('Available now', 'متاحة الآن'),
                    style: TextStyle(color: Color(0xFF9D7B72), fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            mode == NiswahAssistantMode.health
                ? _ai('Health guidance', 'إرشاد صحي')
                : mode == NiswahAssistantMode.fiqhAdvisory
                ? _ai('Source required', 'بانتظار المصادر')
                : _ai('General assistant', 'مساعدة عامة'),
            style: const TextStyle(
              color: Color(0xFF9F3158),
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (onNewChat != null)
          IconButton(
            onPressed: onNewChat,
            tooltip: _ai('New chat', 'محادثة جديدة'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: Color(0xFF7F1D3C),
              size: 19,
            ),
          ),
        if (onHistory != null)
          IconButton(
            onPressed: onHistory,
            tooltip: _ai('History', 'السجل'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.history_rounded,
              color: Color(0xFF7F1D3C),
              size: 19,
            ),
          ),
      ],
    ),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.mode, required this.onPrompt});
  final NiswahAssistantMode mode;
  final ValueChanged<String> onPrompt;

  bool get _isPostpartum => PregnancyStatusController.instance.isNifasActive;
  bool get _isPregnant =>
      !_isPostpartum && PregnancyStatusController.instance.isPregnant;

  String get _firstPrompt {
    if (mode != NiswahAssistantMode.health) {
      return _ai(
        'How can I use Niswah to organize my day?',
        'كيف أستخدم نسوة لتنظيم يومي؟',
      );
    }
    if (_isPostpartum) {
      return _ai(
        'How long does nifas usually last?',
        'كم تستمر فترة النفاس عادة؟',
      );
    }
    if (_isPregnant) {
      return _ai(
        'Is this normal at my current week?',
        'هل هذا طبيعي في الأسبوع الحالي؟',
      );
    }
    return _ai(
      'When should cycle pain be checked by a doctor?',
      'متى يستدعي ألم الدورة مراجعة الطبيبة؟',
    );
  }

  String get _secondPrompt {
    if (mode != NiswahAssistantMode.health) {
      return _ai(
        'Suggest a gentle wellbeing routine',
        'اقترحي لي روتيناً لطيفاً للعافية',
      );
    }
    if (_isPostpartum) {
      return _ai(
        'When do I resume prayer and fasting?',
        'متى أستأنف الصلاة والصيام؟',
      );
    }
    if (_isPregnant) {
      return _ai(
        'What symptoms need urgent care?',
        'ما الأعراض التي تستدعي رعاية عاجلة؟',
      );
    }
    return _ai(
      'What symptoms should I track?',
      'ما الأعراض التي يُنصح بتسجيلها؟',
    );
  }

  String get _thirdPrompt {
    if (mode != NiswahAssistantMode.health) {
      return _ai('What can you help me with?', 'بماذا يمكنكِ مساعدتي؟');
    }
    if (_isPostpartum) {
      return _ai(
        'What postpartum symptoms need urgent care?',
        'ما الأعراض التي تستدعي رعاية عاجلة بعد الولادة؟',
      );
    }
    if (_isPregnant) {
      return _ai(
        'Can I fast in my current condition?',
        'هل يمكنني الصيام في وضعي الحالي؟',
      );
    }
    return _ai(
      'Could my symptoms need urgent care?',
      'هل قد تحتاج أعراضي إلى رعاية عاجلة؟',
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
    child: Column(
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: mode == NiswahAssistantMode.health
                ? const Color(0xFFE4F7F2)
                : const Color(0xFFFFE9EA),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            mode == NiswahAssistantMode.health
                ? Icons.medical_services_outlined
                : Icons.auto_awesome_rounded,
            color: mode == NiswahAssistantMode.health
                ? Color(0xFF08705E)
                : Color(0xFFE91E4D),
            size: 29,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _ai(
            mode == NiswahAssistantMode.health
                ? 'What health concern can I help with?'
                : 'How can I help you today?',
            mode == NiswahAssistantMode.health
                ? 'ما الاستفسار الصحي الذي يمكنني مساعدتكِ فيه؟'
                : 'كيف يمكنني مساعدتكِ اليوم؟',
          ),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF7F1D3C),
            fontFamily: AppTypography.serifFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _ai(
            mode == NiswahAssistantMode.health
                ? 'Share symptoms or a health concern for safe, general guidance and clear next steps.'
                : 'Your companion for everyday questions, app guidance, and general wellbeing.',
            mode == NiswahAssistantMode.health
                ? 'شاركي الأعراض أو مخاوفكِ الصحية لتحصلي على إرشاد عام وخطوات تالية واضحة.'
                : 'رفيقتكِ للأسئلة اليومية، واستخدام التطبيق، والعافية العامة.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF9D7B72), fontSize: 10, height: 1.5),
        ),
        const SizedBox(height: 24),
        if (mode == NiswahAssistantMode.health)
          Row(
            children: [
              Expanded(
                child: _isPostpartum
                    ? _Topic(
                        icon: Icons.spa_outlined,
                        label: _ai('Postpartum', 'نفاس'),
                        color: Color(0xFFE91E4D),
                      )
                    : _isPregnant
                    ? _Topic(
                        icon: Icons.pregnant_woman_rounded,
                        label: _ai('Pregnancy', 'الحمل'),
                        color: Color(0xFFE91E4D),
                      )
                    : _Topic(
                        icon: Icons.water_drop_outlined,
                        label: _ai('Cycle', 'الدورة'),
                        color: Color(0xFFE91E4D),
                      ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _Topic(
                  icon: Icons.favorite_border_rounded,
                  label: _ai('Health', 'صحة'),
                  color: Color(0xFF9B4A9C),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _Topic(
                  icon: Icons.menu_book_outlined,
                  label: _ai('Fiqh', 'فقه'),
                  color: Color(0xFF14926D),
                ),
              ),
            ],
          ),
        const SizedBox(height: 22),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            _ai('SUGGESTED QUESTIONS', 'أسئلة مقترحة'),
            style: const TextStyle(
              color: Color(0xFFB58A7E),
              fontSize: 8,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _Prompt(text: _firstPrompt, onTap: onPrompt),
        SizedBox(height: 8),
        _Prompt(text: _secondPrompt, onTap: onPrompt),
        SizedBox(height: 8),
        _Prompt(text: _thirdPrompt, onTap: onPrompt),
      ],
    ),
  );
}

class _Topic extends StatelessWidget {
  const _Topic({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFFFE6E2)),
    ),
    child: Column(
      children: [
        Icon(icon, color: color, size: 21),
        const SizedBox(height: 7),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF7F1D3C),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.text, required this.onTap});
  final String text;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onTap(text),
    borderRadius: BorderRadius.circular(15),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFFFE6E2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF885D54),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            color: Color(0xFFD8AAA0),
            size: 11,
          ),
        ],
      ),
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.mode,
    required this.enabled,
    required this.controller,
    required this.busy,
    required this.onSend,
  });
  final NiswahAssistantMode mode;
  final bool enabled;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 58),
    margin: const EdgeInsets.symmetric(horizontal: 18),
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFFFDCD8)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF7F1D3C).withValues(alpha: .07),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: TextField(
              enabled: enabled,
              controller: controller,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textAlign: TextAlign.start,
              style: const TextStyle(
                color: Color(0xFF5F403A),
                fontSize: 14,
                height: 1.35,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: _ai(
                  !enabled
                      ? 'AI connection unavailable'
                      : mode == NiswahAssistantMode.health
                      ? 'Describe a symptom or health concern...'
                      : mode == NiswahAssistantMode.fiqhAdvisory
                      ? 'Describe the case and your question...'
                      : 'Ask a general question...',
                  !enabled
                      ? 'اتصال الذكاء الاصطناعي غير متاح'
                      : mode == NiswahAssistantMode.health
                      ? 'صِفي عرضاً أو استفساراً صحياً...'
                      : mode == NiswahAssistantMode.fiqhAdvisory
                      ? 'اكتبي تفاصيل الحالة وسؤالكِ...'
                      : 'اسألي سؤالاً عاماً...',
                ),
                hintStyle: const TextStyle(
                  color: Color(0xFFC2A49D),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 46,
          height: 46,
          child: IconButton.filled(
            onPressed: !enabled || busy ? null : onSend,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: mode == NiswahAssistantMode.health
                  ? const Color(0xFF08705E)
                  : mode == NiswahAssistantMode.fiqhAdvisory
                  ? const Color(0xFF9A6700)
                  : const Color(0xFFE91E4D),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE8CAC5),
            ),
            icon: busy
                ? SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                      semanticsLabel: _ai('Sending message', 'جارٍ إرسال الرسالة'),
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded, size: 20),
          ),
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.message});
  final ChatMessage message;

  List<Map<String, dynamic>> get _citations =>
      (message.metadata['citations'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
  bool get _urgent => message.metadata['urgent'] == true;

  @override
  Widget build(BuildContext context) {
    final mine = message.role == ChatRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _urgent
                      ? const [Color(0xFFDC2626), Color(0xFF991B1B)]
                      : const [Color(0xFFEE315A), Color(0xFFB92564)],
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                _urgent ? Icons.emergency_outlined : Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              constraints: const BoxConstraints(maxWidth: 285),
              decoration: BoxDecoration(
                color: mine
                    ? const Color(0xFFE91E4D)
                    : _urgent
                    ? const Color(0xFFFEF2F2)
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 5),
                  bottomRight: Radius.circular(mine ? 5 : 18),
                ),
                border: mine
                    ? null
                    : Border.all(
                        color: _urgent
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFFFFE6E2),
                        width: _urgent ? 1.5 : 1,
                      ),
                boxShadow: mine
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x0A7F1D3C),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!mine && _urgent) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFF991B1B),
                          size: 13,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _ai('Urgent', 'عاجل'),
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    message.content,
                    style: TextStyle(
                      color: mine
                          ? Colors.white
                          : _urgent
                          ? const Color(0xFF7F1D1D)
                          : const Color(0xFF734C43),
                      fontSize: 11,
                      height: 1.5,
                      fontWeight: _urgent ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (!mine && _citations.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var index = 0; index < _citations.length; index++)
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(
                              Icons.open_in_new_rounded,
                              size: 13,
                            ),
                            label: Text(
                              '[${index + 1}] ${_citations[index]['title']}',
                              style: const TextStyle(fontSize: 9),
                            ),
                            onPressed: () {
                              final uri = Uri.tryParse(
                                _citations[index]['url']?.toString() ?? '',
                              );
                              if (uri != null) launchUrl(uri);
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE6E2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AU-014: deliberately no semanticsLabel here. Without one, a bare
          // CircularProgressIndicator contributes no node to the semantics
          // tree at all (confirmed: Flutter only creates one when
          // semanticsLabel/semanticsValue is set) — so a screen reader
          // skips straight to the adjacent "Niswah is thinking…" Text below,
          // which already announces the loading state in context. Adding a
          // label here would only produce a duplicate announcement.
          const SizedBox.square(
            dimension: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: Color(0xFFB92564),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _ai('Niswah is thinking…', 'نسوة تفكر…'),
            style: const TextStyle(color: Color(0xFF885D54), fontSize: 10),
          ),
        ],
      ),
    ),
  );
}
