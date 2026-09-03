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
  });

  final CommunityComment comment;
  final bool isOwnComment;
  final VoidCallback? onDelete;

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
          if (isOwnComment && onDelete != null)
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_horiz_rounded,
                color: palette.textFaint,
                size: 16,
              ),
              onSelected: (value) {
                if (value == 'delete') onDelete!.call();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(_t('Delete', 'حذف')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
