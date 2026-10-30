import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities/community_category_x.dart';
import '../../domain/entities/community_post.dart';
import '../community_palette.dart';
import 'community_engagement_bar.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// A single feed post. Dumb widget — no view-model dependency, all actions
/// bubble up as callbacks so it stays reusable/testable.
///
/// Relies entirely on the ambient [Directionality] (set once at the app
/// root) to mirror correctly in Arabic — earlier versions of this card
/// hand-forced `TextDirection.ltr`/`.rtl` on parts of the header, which was
/// fragile and is deliberately not repeated here.
class CommunityPostCard extends StatefulWidget {
  const CommunityPostCard({
    super.key,
    required this.post,
    required this.isOwnPost,
    required this.onTap,
    required this.onLike,
    this.onDelete,
    this.onMessageAuthor,
    this.onAuthorTap,
    this.onReport,
    this.onBlock,
  });

  final CommunityPost post;
  final bool isOwnPost;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback? onDelete;
  final VoidCallback? onMessageAuthor;
  final VoidCallback? onAuthorTap;

  /// Report / block the author (App Store guideline 1.2). Shown in the
  /// ••• menu on other members' posts only.
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  @override
  State<CommunityPostCard> createState() => _CommunityPostCardState();
}

class _CommunityPostCardState extends State<CommunityPostCard> {
  static const _truncateLength = 220;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = CommunityPalette.of(context);
    final post = widget.post;
    final displayName = post.isAnonymous
        ? _t('Visitor', 'زائرة')
        : post.authorName;
    final isLong = post.content.length > _truncateLength;
    final displayContent = _expanded || !isLong
        ? post.content
        : '${post.content.substring(0, _truncateLength).trimRight()}…';

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppRadius.cardLarge - 4),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.cardLarge - 4),
          border: Border.all(color: palette.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: post.isAnonymous ? null : widget.onAuthorTap,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          UserAvatar(
                            displayName: displayName,
                            isAnonymous: post.isAnonymous,
                            dark:
                                Theme.of(context).brightness == Brightness.dark,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 7,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      displayName,
                                      style: TextStyle(
                                        color: palette.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.blush.withValues(
                                          alpha: 0.14,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.chip,
                                        ),
                                      ),
                                      child: Text(
                                        post.category.label(),
                                        style: TextStyle(
                                          color: palette.blush,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _relativeTime(post.createdAt),
                                  style: TextStyle(
                                    color: palette.textFaint,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!post.isAnonymous && widget.onAuthorTap != null)
                            Icon(
                              Icons.chevron_right_rounded,
                              color: palette.textFaint,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.onMessageAuthor != null)
                  ContactAuthorButton(onTap: widget.onMessageAuthor!),
                if ((widget.isOwnPost && widget.onDelete != null) ||
                    (!widget.isOwnPost &&
                        (widget.onReport != null || widget.onBlock != null)))
                  PopupMenuButton<String>(
                    key: const ValueKey('community-post-menu'),
                    padding: EdgeInsets.zero,
                    tooltip: _t('More options', 'خيارات أخرى'),
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: palette.textMuted,
                      size: 18,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'delete':
                          _confirmDelete(context);
                        case 'report':
                          widget.onReport?.call();
                        case 'block':
                          widget.onBlock?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      if (widget.isOwnPost)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(_t('Delete post', 'حذف المنشور')),
                        ),
                      if (!widget.isOwnPost && widget.onReport != null)
                        PopupMenuItem(
                          value: 'report',
                          child: Text(_t('Report post', 'الإبلاغ عن المنشور')),
                        ),
                      if (!widget.isOwnPost && widget.onBlock != null)
                        PopupMenuItem(
                          value: 'block',
                          child: Text(_t('Block member', 'حظر العضوة')),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              displayContent,
              style: TextStyle(color: palette.text, fontSize: 13, height: 1.65),
            ),
            if (isLong)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Text(
                    _expanded
                        ? _t('See less', 'عرض أقل')
                        : _t('See more', 'عرض المزيد'),
                    style: TextStyle(
                      color: palette.blush,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: post.tags
                    .map(
                      (tag) => Text(
                        '#$tag',
                        style: TextStyle(
                          color: palette.blush,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            Divider(height: 1, color: palette.divider),
            const SizedBox(height: 12),
            CommunityEngagementBar(
              likeCount: post.likeCount,
              isLiked: post.isLikedByCurrentUser,
              commentCount: post.commentCount,
              onLike: widget.onLike,
              onCommentTap: widget.onTap,
              onMessageTap: null,
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Delete post?', 'حذف المنشور؟')),
        content: Text(
          _t('This cannot be undone.', 'لا يمكن التراجع عن هذا الإجراء.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              widget.onDelete?.call();
            },
            child: Text(
              _t('Delete', 'حذف'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime createdAt) {
  final difference = AppClock.now().difference(createdAt);
  if (difference.inDays > 0) {
    return _t('${difference.inDays} days ago', 'قبل ${difference.inDays} يوم');
  }
  if (difference.inHours > 0) {
    return _t(
      '${difference.inHours} hours ago',
      'قبل ${difference.inHours} ساعة',
    );
  }
  return _t('Just now', 'الآن');
}
