import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/dream_entry.dart';
import '../viewmodels/dream_interpreter_view_model.dart';

String _dr(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// The real signed-in user id where available. `dream_entries` is RLS-gated
/// on `auth.uid() = user_id`, so writing a placeholder string here fails for
/// any real session — 'demo-user' only remains as a fallback for local/dev
/// use without Supabase configured.
String _currentUserId() =>
    NiswahSupabase.clientOrNull?.auth.currentUser?.id ?? 'demo-user';

String _formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}

/// Which surface is showing: the conversations picker (when past dreams
/// exist) or the live chat. Distinct from the view model's data — leaving an
/// active chat to browse history shouldn't clear it.
enum _DreamView { picker, chat }

class DreamInterpreterScreen extends StatefulWidget {
  const DreamInterpreterScreen({super.key});
  @override
  State<DreamInterpreterScreen> createState() => _DreamInterpreterScreenState();
}

class _DreamInterpreterScreenState extends State<DreamInterpreterScreen> {
  late final DreamInterpreterViewModel _model;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  var _lastMessageCount = 0;
  var _userNavigated = false;
  // Defaults to the composer, since a first-ever open usually has no
  // history yet — avoids ever flashing the picker for the common case.
  // A cached hint from a previous open (below) or the network load then
  // corrects this to the picker almost immediately when there actually is
  // history, so returning users don't see a flash in that direction either.
  _DreamView _view = _DreamView.chat;

  String get _historyPrefsKey => 'dream_has_history_${_currentUserId()}';

  @override
  void initState() {
    super.initState();
    _model = DreamInterpreterViewModel();
    _model.addListener(_followNewestMessage);
    unawaited(_restoreCachedView());
    _model.loadEntries(userId: _currentUserId()).then((_) {
      if (!mounted) return;
      final hasHistory = _model.entries.isNotEmpty;
      unawaited(_cacheHasHistory(hasHistory));
      if (_userNavigated) return;
      final correctView = hasHistory ? _DreamView.picker : _DreamView.chat;
      if (_view != correctView) setState(() => _view = correctView);
    });
  }

  Future<void> _restoreCachedView() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _userNavigated) return;
    if (prefs.getBool(_historyPrefsKey) == true) {
      setState(() => _view = _DreamView.picker);
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
    if (_model.transcript.length == _lastMessageCount) return;
    _lastMessageCount = _model.transcript.length;
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
    setState(() => _view = _DreamView.picker);
  }

  void _startNewFromPicker() {
    _userNavigated = true;
    _model.startNewDream();
    setState(() => _view = _DreamView.chat);
  }

  void _resumeFromPicker(DreamEntry entry) {
    _userNavigated = true;
    _model.resumeEntry(entry);
    setState(() => _view = _DreamView.chat);
  }

  Future<void> _deleteFromPicker(DreamEntry entry) async {
    await _model.deleteEntry(userId: _currentUserId(), entryId: entry.id);
    if (mounted && _model.entries.isEmpty) {
      _userNavigated = true;
      setState(() => _view = _DreamView.chat);
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
            _DreamHeader(
              onClose: () => Navigator.maybePop(context),
              onHistory: _view == _DreamView.chat && _model.entries.isNotEmpty
                  ? _openPicker
                  : null,
              onNewDream: _view == _DreamView.chat && _model.transcript.isNotEmpty
                  ? _model.startNewDream
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
      case _DreamView.picker:
        return _ConversationsPicker(
          entries: _model.entries,
          isLoading: _model.isLoading,
          onNewDream: _startNewFromPicker,
          onSelect: _resumeFromPicker,
          onDelete: _deleteFromPicker,
        );
      case _DreamView.chat:
        return _ChatView(
          model: _model,
          controller: _controller,
          scrollController: _scrollController,
          onSend: _submit,
        );
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await _model.sendMessage(userId: _currentUserId(), message: text);
  }
}

class _ChatView extends StatelessWidget {
  const _ChatView({
    required this.model,
    required this.controller,
    required this.scrollController,
    required this.onSend,
  });

  final DreamInterpreterViewModel model;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: double.infinity,
        color: const Color(0xFFF7F4FF),
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Text(
          _dr(
            'Share your vision for an Islamic-based interpretation',
            'شاركي رؤياكِ لتفسير مبني على المنظور الإسلامي',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF7262A8), fontSize: 8.5),
        ),
      ),
      Expanded(
        child: model.transcript.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                controller: scrollController,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                itemCount:
                    (model.isResumedConversation ? 1 : 0) +
                    model.transcript.length +
                    (model.isSubmitting ? 1 : 0),
                itemBuilder: (context, index) {
                  var i = index;
                  if (model.isResumedConversation) {
                    if (i == 0) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: Center(child: _ResumedBadge()),
                      );
                    }
                    i -= 1;
                  }
                  if (i < model.transcript.length) {
                    return _DreamBubble(message: model.transcript[i]);
                  }
                  return const _TypingIndicator();
                },
              ),
      ),
      if (model.errorMessage != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: _DreamNotice(
            message: _dr(
              'The dream could not be interpreted. Please try again.',
              'تعذر تفسير الرؤيا. حاولي مرة أخرى.',
            ),
            isError: true,
          ),
        ),
      if (model.warningMessage != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: _DreamNotice(
            message: _dr(
              'The interpretation is shown, but it could not be saved to your history.',
              'ظهر التفسير، لكن تعذر حفظه في سجلكِ.',
            ),
          ),
        ),
      _DreamComposer(controller: controller, busy: model.isSubmitting, onSend: onSend),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
        child: Text(
          _dr(
            'These responses are AI-generated for general guidance. Consult specialists for specific cases.',
            'هذه الردود مولدة آلياً للإرشاد العام. راجعي المختصين للحالات الخاصة.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFB7AEB7), fontSize: 7.5),
        ),
      ),
    ],
  );
}

class _ConversationsPicker extends StatelessWidget {
  const _ConversationsPicker({
    required this.entries,
    required this.isLoading,
    required this.onNewDream,
    required this.onSelect,
    required this.onDelete,
  });

  final List<DreamEntry> entries;
  final bool isLoading;
  final VoidCallback onNewDream;
  final ValueChanged<DreamEntry> onSelect;
  final ValueChanged<DreamEntry> onDelete;

  Future<void> _confirmDelete(BuildContext context, DreamEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_dr('Delete this dream?', 'حذف هذه الرؤيا؟')),
        content: Text(
          _dr(
            'This will remove the conversation and its interpretation permanently.',
            'سيؤدي هذا إلى حذف المحادثة وتفسيرها نهائياً.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_dr('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _dr('Delete', 'حذف'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete(entry);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        flex: 3,
        child: entries.isEmpty
            ? Center(
                child: isLoading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.istihadah,
                        ),
                      )
                    : Text(
                        _dr('No past dreams yet', 'لا توجد رؤى سابقة بعد'),
                        style: const TextStyle(color: Color(0xFF9589AC)),
                      ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1ECFF),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.nightlight_round,
                        color: AppColors.istihadah,
                        size: 17,
                      ),
                    ),
                    title: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF4C3B78),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      _formatDate(entry.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF9589AC),
                        fontSize: 10,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                      ),
                      onPressed: () => _confirmDelete(context, entry),
                    ),
                    onTap: () => onSelect(entry),
                  );
                },
              ),
      ),
      Expanded(
        flex: 2,
        child: Center(
          child: InkWell(
            onTap: onNewDream,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: AppColors.istihadah,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.istihadah.withValues(alpha: 0.3),
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
                      _dr('New', 'محادثة جديدة'),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF1ECFF),
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Icon(
              Icons.nightlight_round,
              color: AppColors.istihadah,
              size: 32,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _dr('Dream Interpreter', 'مفسر الأحلام'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: const Color(0xFF4C3B78),
              fontFamily: AppTypography.serifFamily,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _dr(
              'Share your dream for a reflective interpretation',
              'شاركي حلمكِ لتفسير وتأمل متزن',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9589AC), fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class _DreamComposer extends StatelessWidget {
  const _DreamComposer({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 58),
    margin: const EdgeInsets.fromLTRB(18, 8, 18, 0),
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: const Color(0xFFE4DCF3)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x124C3B78),
          blurRadius: 18,
          offset: Offset(0, 6),
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
              controller: controller,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                color: Color(0xFF4C3B78),
                fontSize: 13,
                height: 1.4,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: _dr(
                  'Describe your dream...',
                  'اكتبي تفاصيل رؤياكِ...',
                ),
                hintStyle: const TextStyle(
                  color: Color(0xFFB5ABB9),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        SizedBox.square(
          dimension: 46,
          // Scoped to just this button so typing in the field above never
          // rebuilds the rest of the composer (or screen) per keystroke.
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => IconButton.filled(
              onPressed: busy || value.text.trim().isEmpty ? null : onSend,
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: AppColors.istihadah,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE5E2EA),
              ),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded, size: 20),
            ),
          ),
        ),
      ],
    ),
  );
}

class _DreamNotice extends StatelessWidget {
  const _DreamNotice({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: isError ? const Color(0xFFFFF1F2) : const Color(0xFFFFF8E7),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isError ? const Color(0xFFFFCDD5) : const Color(0xFFE8C978),
      ),
    ),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: isError ? const Color(0xFF9F1239) : const Color(0xFF704D0A),
        fontSize: 10,
        height: 1.4,
      ),
    ),
  );
}

class _DreamHeader extends StatelessWidget {
  const _DreamHeader({
    required this.onClose,
    required this.onHistory,
    required this.onNewDream,
  });
  final VoidCallback onClose;
  final VoidCallback? onHistory;
  final VoidCallback? onNewDream;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 12, 11),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFF0EAF8))),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: Color(0xFF4C3B78)),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF1ECFF),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.nightlight_round,
            color: AppColors.istihadah,
            size: 21,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _dr('Dream Interpretation', 'تفسير الأحلام'),
                style: const TextStyle(
                  color: Color(0xFF4C3B78),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'v11.1-GEMINI',
                style: TextStyle(
                  color: Color(0xFFA597B0),
                  fontSize: 7.5,
                  letterSpacing: .7,
                ),
              ),
            ],
          ),
        ),
        if (onNewDream != null)
          IconButton(
            onPressed: onNewDream,
            tooltip: _dr('New dream', 'رؤيا جديدة'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: Color(0xFF4C3B78),
              size: 20,
            ),
          ),
        if (onHistory != null)
          IconButton(
            onPressed: onHistory,
            tooltip: _dr('History', 'السجل'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.history_rounded,
              color: Color(0xFF4C3B78),
              size: 20,
            ),
          ),
      ],
    ),
  );
}

class _ResumedBadge extends StatelessWidget {
  const _ResumedBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF1ECFF),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: const Color(0xFFE4DCF3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.history_rounded, size: 12, color: Color(0xFF7262A8)),
        const SizedBox(width: 5),
        Text(
          _dr('Continuing your last dream', 'متابعة آخر رؤيا محفوظة'),
          style: const TextStyle(
            color: Color(0xFF7262A8),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _DreamBubble extends StatelessWidget {
  const _DreamBubble({required this.message});
  final DreamMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.role == DreamMessageRole.user;
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
                color: const Color(0xFFF1ECFF),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.nightlight_round,
                color: AppColors.istihadah,
                size: 15,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              constraints: const BoxConstraints(maxWidth: 285),
              decoration: BoxDecoration(
                color: mine ? AppColors.istihadah : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 5),
                  bottomRight: Radius.circular(mine ? 5 : 18),
                ),
                border: mine
                    ? null
                    : Border.all(color: const Color(0xFFE4DCF3)),
                boxShadow: mine
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x0A4C3B78),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
              ),
              child: SelectableText(
                message.content,
                style: TextStyle(
                  color: mine ? Colors.white : const Color(0xFF594A71),
                  fontSize: 12.5,
                  height: 1.55,
                ),
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
        border: Border.all(color: const Color(0xFFE4DCF3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: AppColors.istihadah,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _dr('Reflecting…', 'تتأمل...'),
            style: const TextStyle(color: Color(0xFF9589AC), fontSize: 10),
          ),
        ],
      ),
    ),
  );
}
