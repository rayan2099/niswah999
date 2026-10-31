import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities/community_comment.dart';
import '../community_palette.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

class CommunityCommentTile extends StatelessWidget {
  const CommunityCommentTile({
    super.key,
    required this.comment,
    required this.isOwnComment,
    this.onDelete,
    this.onReport,
    this.onBlock,
  });

  final CommunityComment comment;
  final bool isOwnComment;
  final VoidCallback? onDelete;

  /// Report / block the commenter; offered on other members' comments.
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) {
    final palette = CommunityPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            displayName: comment.authorName,
            size: 32,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.authorName,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  comment.content,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if ((isOwnComment && onDelete != null) ||
              (!isOwnComment && (onReport != null || onBlock != null)))
            PopupMenuButton<String>(
              key: const ValueKey('community-comment-menu'),
              padding: EdgeInsets.zero,
              tooltip: _t('More options', 'خيارات أخرى'),
              icon: Icon(
                Icons.more_horiz_rounded,
                color: palette.textFaint,
                size: 16,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'delete':
                    onDelete?.call();
                  case 'report':
                    onReport?.call();
                  case 'block':
                    onBlock?.call();
                }
              },
              itemBuilder: (context) => [
                if (isOwnComment)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(_t('Delete', 'حذف')),
                  ),
                if (!isOwnComment && onReport != null)
                  PopupMenuItem(
                    value: 'report',
                    child: Text(_t('Report comment', 'الإبلاغ عن التعليق')),
                  ),
                if (!isOwnComment && onBlock != null)
                  PopupMenuItem(
                    value: 'block',
                    child: Text(_t('Block member', 'حظر العضوة')),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
