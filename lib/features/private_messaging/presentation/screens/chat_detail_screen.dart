import '../../../../core/widgets/app_route_observer.dart';
import '../../../notifications/data/services/app_notification_session.dart';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../community/safety/community_safety_actions.dart';
import '../../../community/safety/community_safety_controller.dart';
import '../../../community/safety/community_safety_models.dart';
import '../../domain/entities/private_conversation.dart';
import '../../private_messaging_locator.dart';
import '../conversation_title.dart';
import '../viewmodels/chat_detail_view_model.dart';

String _pm(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// 1:1 private chat between the current user and another participant.
class ChatDetailScreen extends StatefulWidget {
  final PrivateConversation conversation;
  final String currentUserId;

  /// The other participant's published display name, when known.
  final String? otherDisplayName;

  const ChatDetailScreen({
    super.key,
    required this.conversation,
    required this.currentUserId,
    this.otherDisplayName,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with WidgetsBindingObserver, RouteAware {
  late final ChatDetailViewModel _viewModel;
  final _conversationOwner = Object();
  ModalRoute<dynamic>? _observedRoute;
  void _publishVisible() {
    AppNotificationSession.instance.showConversation(
      widget.conversation.id,
      _conversationOwner,
      () =>
          mounted &&
          _viewModel.active &&
          (ModalRoute.of(context)?.isCurrent ?? false),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !identical(route, _observedRoute)) {
      appRouteObserver.unsubscribe(this);
      _observedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() => _publishVisible();
  @override
  void didPopNext() {
    _publishVisible();
    _viewModel.loadMessages();
  }

  @override
  void didPushNext() =>
      AppNotificationSession.instance.hideConversation(_conversationOwner);
  @override
  void didPop() =>
      AppNotificationSession.instance.hideConversation(_conversationOwner);

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _viewModel = ChatDetailViewModel(
      repository: privateMessagingRepository,
      conversationId: widget.conversation.id,
      currentUserId: widget.currentUserId,
      isVisible: () => mounted && (ModalRoute.of(context)?.isCurrent ?? false),
    )..loadMessages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    AppNotificationSession.instance.hideConversation(_conversationOwner);
    _inputController.dispose();
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _viewModel.active = state == AppLifecycleState.resumed;
    if (_viewModel.active) {
      _publishVisible();
    } else {
      AppNotificationSession.instance.hideConversation(_conversationOwner);
    }
    if (_viewModel.active) _viewModel.loadMessages();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    _inputController.clear();
    final sent = await _viewModel.sendMessage(text);
    if (sent) {
      _scrollToBottom();
    } else if (mounted && _inputController.text.isEmpty) {
      // Keep what she wrote so she can edit it (e.g. a blocked word).
      _inputController.text = text;
    }
  }

  String get _otherUserId =>
      widget.conversation.otherParticipant(widget.currentUserId);

  Future<void> _blockOther() async {
    final blocked = await confirmBlockMember(
      context,
      userId: _otherUserId,
      displayName: widget.otherDisplayName,
    );
    if (blocked && mounted) Navigator.of(context).pop();
  }

  void _reportMessage(String messageId) => showCommunityReportSheet(
    context,
    targetType: ReportTargetType.message,
    targetId: messageId,
  );

  @override
  Widget build(BuildContext context) {
    final otherUser = conversationTitle(widget.otherDisplayName);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('chat-detail-menu'),
            tooltip: _pm('More options', 'خيارات أخرى'),
            onSelected: (value) {
              switch (value) {
                case 'report':
                  showCommunityReportSheet(
                    context,
                    targetType: ReportTargetType.user,
                    targetId: _otherUserId,
                  );
                case 'block':
                  _blockOther();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'report',
                child: Text(_pm('Report member', 'الإبلاغ عن العضوة')),
              ),
              PopupMenuItem(
                value: 'block',
                child: Text(_pm('Block member', 'حظر العضوة')),
              ),
            ],
          ),
        ],
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFFFE4E6),
              child: Icon(
                Icons.person_rounded,
                color: const Color(0xFF8E244D),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                otherUser,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF8E244D),
                  fontFamily: AppTypography.serifFamily,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: _viewModel,
                builder: (context, _) {
                  if (_viewModel.isLoading && _viewModel.messages.isEmpty) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: const Color(0xFFE91E4D),
                        semanticsLabel: _pm(
                          'Loading messages',
                          'جارٍ تحميل الرسائل',
                        ),
                      ),
                    );
                  }
                  if (_viewModel.messages.isEmpty) {
                    return Center(
                      child: Text(
                        _pm(
                          'Say salam and start the conversation',
                          'ابدئي المحادثة بالسلام',
                        ),
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  _scrollToBottom();
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _viewModel.messages.length,
                    itemBuilder: (context, index) {
                      final message = _viewModel.messages[index];
                      final mine = _viewModel.isMine(message);
                      return GestureDetector(
                        onLongPress: mine
                            ? null
                            : () => _reportMessage(message.id),
                        child: Align(
                          alignment: mine
                              ? AlignmentDirectional.centerEnd
                              : AlignmentDirectional.centerStart,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? const Color(0xFFE91E4D)
                                  : Colors.white,
                              borderRadius: BorderRadiusDirectional.only(
                                topStart: const Radius.circular(16),
                                topEnd: const Radius.circular(16),
                                bottomStart: Radius.circular(mine ? 16 : 4),
                                bottomEnd: Radius.circular(mine ? 4 : 16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.content,
                                  style: TextStyle(
                                    color: mine ? Colors.white : Colors.black87,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      _formatTime(message.createdAt),
                                      style: TextStyle(
                                        color: mine
                                            ? Colors.white70
                                            : AppColors.textSecondary,
                                        fontSize: 9,
                                      ),
                                    ),
                                    if (mine) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        message.isRead
                                            ? Icons.done_all_rounded
                                            : Icons.done_rounded,
                                        size: 12,
                                        color: Colors.white70,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: _viewModel,
              builder: (context, _) {
                if (_viewModel.errorMessage == null) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _viewModel.sendError?.message() ??
                        _pm('Message failed to send', 'فشل إرسال الرسالة'),
                    style: const TextStyle(
                      color: Color(0xFFE91E4D),
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: CommunitySafetyController.instance,
              builder: (context, composer) =>
                  CommunitySafetyController.instance.isBlocked(_otherUserId)
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _pm(
                          'You blocked this member. Unblock her from Profile → Blocked members to message again.',
                          'لقد حظرتِ هذه العضوة. ألغي الحظر من الملف الشخصي ← العضوات المحظورات لمراسلتها مجدداً.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : composer!,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: _pm('Write a message…', 'اكتبي رسالة…'),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: Color(0xFFFFE4E6),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: Color(0xFFFFE4E6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedBuilder(
                      animation: _viewModel,
                      builder: (context, _) {
                        return FloatingActionButton.small(
                          heroTag: 'send-private-message',
                          onPressed: _viewModel.isSending ? null : _send,
                          backgroundColor: const Color(0xFFE91E4D),
                          foregroundColor: Colors.white,
                          child: _viewModel.isSending
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                    semanticsLabel: _pm(
                                      'Sending message',
                                      'جارٍ إرسال الرسالة',
                                    ),
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}
