import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
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

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  late final ChatDetailViewModel _viewModel;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _viewModel = ChatDetailViewModel(
      repository: privateMessagingRepository,
      conversationId: widget.conversation.id,
      currentUserId: widget.currentUserId,
    )..loadMessages();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
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
    if (sent) _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final otherUser = conversationTitle(widget.otherDisplayName);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
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
                      return Align(
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
                    _pm('Message failed to send', 'فشل إرسال الرسالة'),
                    style: const TextStyle(
                      color: Color(0xFFE91E4D),
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
            Padding(
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
