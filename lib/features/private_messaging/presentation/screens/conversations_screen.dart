import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/private_conversation.dart';
import '../conversation_title.dart';
import '../viewmodels/conversations_view_model.dart';
import 'chat_detail_screen.dart';

String _pm(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Lists all active private conversations for the current user.
class ConversationsScreen extends StatefulWidget {
  final ConversationsViewModel viewModel;

  const ConversationsScreen({super.key, required this.viewModel});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.loadConversations();
  }

  Future<void> _openConversation(PrivateConversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatDetailScreen(
          conversation: conversation,
          currentUserId: widget.viewModel.currentUserId,
          otherDisplayName: widget.viewModel.displayNameFor(conversation),
        ),
      ),
    );
    widget.viewModel.loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          _pm('Messages', 'الرسائل'),
          style: TextStyle(
            color: const Color(0xFF8E244D),
            fontFamily: AppTypography.serifFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: widget.viewModel,
        builder: (context, _) {
          if (widget.viewModel.isLoading &&
              widget.viewModel.conversations.isEmpty) {
            return Center(
              child: CircularProgressIndicator(
                color: const Color(0xFFE91E4D),
                semanticsLabel: _pm(
                  'Loading conversations',
                  'جارٍ تحميل المحادثات',
                ),
              ),
            );
          }
          if (widget.viewModel.errorMessage != null &&
              widget.viewModel.conversations.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.brandSecondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _pm(
                        'Could not load your messages. Please try again.',
                        'تعذّر تحميل رسائلك. حاولي مرة أخرى.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }
          if (widget.viewModel.conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 44,
                    color: AppColors.brandSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _pm('No conversations yet', 'لا توجد محادثات بعد'),
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            color: const Color(0xFFE91E4D),
            onRefresh: widget.viewModel.loadConversations,
            child: ListView.separated(
              itemCount: widget.viewModel.conversations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final conversation = widget.viewModel.conversations[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFFFE4E6),
                    child: Icon(
                      Icons.person_rounded,
                      color: const Color(0xFF8E244D),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    conversationTitle(
                      widget.viewModel.displayNameFor(conversation),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _pm('Tap to open chat', 'اضغطي لفتح المحادثة'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.brandSecondary,
                  ),
                  onTap: () => _openConversation(conversation),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
