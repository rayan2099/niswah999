import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities/community_category_x.dart';
import '../../domain/entities/community_post.dart';
import '../community_palette.dart';
import '../viewmodels/community_feed_view_model.dart';
import '../viewmodels/post_detail_view_model.dart';
import '../widgets/community_comment_composer.dart';
import '../widgets/community_comment_tile.dart';
import '../widgets/community_engagement_bar.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Full post + comment thread. Takes the already-loaded [CommunityPost]
/// from the feed (no extra fetch needed) and loads its comments on init.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.currentUserName,
    required this.feedViewModel,
    this.onMessageAuthor,
    this.onAuthorTap,
  });

  final CommunityPost post;
  final String? currentUserId;
  final String currentUserName;

  /// So a comment added/removed here updates the list's count without a
  /// full reload when the user navigates back.
  final CommunityFeedViewModel feedViewModel;
  final VoidCallback? onMessageAuthor;
  final VoidCallback? onAuthorTap;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late final PostDetailViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = PostDetailViewModel(
      initialPost: widget.post,
      currentUserId: widget.currentUserId,
      currentUserName: widget.currentUserName,
    )..loadComments();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<bool> _addComment(String content) async {
    final countBefore = _viewModel.post.commentCount;
    final didAdd = await _viewModel.addComment(content);
    if (_viewModel.post.commentCount != countBefore) {
      widget.feedViewModel.bumpCommentCount(widget.post.id);
    }
    return didAdd;
  }

  Future<void> _deleteComment(String commentId) async {
    final countBefore = _viewModel.post.commentCount;
    await _viewModel.deleteComment(commentId);
    final delta = _viewModel.post.commentCount - countBefore;
    if (delta != 0) {
      widget.feedViewModel.bumpCommentCount(widget.post.id, delta: delta);
    }
  }

  Future<void> _handleDeletePost() async {
    final palette = CommunityPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.surfaceElevated,
        title: Text(
          _t('Delete post?', 'حذف المنشور؟'),
          style: TextStyle(color: palette.text),
        ),
        content: Text(
          _t('This cannot be undone.', 'لا يمكن التراجع عن هذا الإجراء.'),
          style: TextStyle(color: palette.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              _t('Cancel', 'إلغاء'),
              style: TextStyle(color: palette.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _t('Delete', 'حذف'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await _viewModel.deletePost();
    if (success && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CommunityPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.text),
        title: Text(
          _t('Post', 'المنشور'),
          style: TextStyle(
            color: palette.text,
            fontFamily: AppTypography.serifFamily,
          ),
        ),
        actions: [
          AnimatedBuilder(
            animation: _viewModel,
            builder: (context, _) {
              final isOwnPost =
                  widget.currentUserId != null &&
                  _viewModel.post.userId == widget.currentUserId;
              if (!isOwnPost) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz_rounded, color: palette.text),
                onSelected: (value) {
                  if (value == 'delete') _handleDeletePost();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(_t('Delete post', 'حذف المنشور')),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _viewModel,
          builder: (context, _) {
            final post = _viewModel.post;
            final displayName = post.isAnonymous
                ? _t('Visitor', 'زائرة')
                : post.authorName;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: palette.divider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: post.isAnonymous
                                        ? null
                                        : widget.onAuthorTap,
                                    borderRadius: BorderRadius.circular(14),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          UserAvatar(
                                            displayName: displayName,
                                            isAnonymous: post.isAnonymous,
                                            dark: isDark,
                                          ),
                                          const SizedBox(width: 11),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  displayName,
                                                  style: TextStyle(
                                                    color: palette.text,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                Text(
                                                  post.category.label(),
                                                  style: TextStyle(
                                                    color: palette.blush,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!post.isAnonymous &&
                                              widget.onAuthorTap != null)
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
                                  ContactAuthorButton(
                                    onTap: widget.onMessageAuthor!,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              post.content,
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 13,
                                height: 1.65,
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
                              onLike: _viewModel.toggleLike,
                              onCommentTap: () {},
                              onMessageTap: null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _t('Comments', 'التعليقات'),
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (_viewModel.isLoadingComments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: palette.blush,
                              semanticsLabel: _t('Loading comments', 'جارٍ تحميل التعليقات'),
                            ),
                          ),
                        )
                      else if (_viewModel.comments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            _t(
                              'Be the first to comment.',
                              'كوني أول من يعلّق.',
                            ),
                            style: TextStyle(
                              color: palette.textFaint,
                              fontSize: 11,
                            ),
                          ),
                        )
                      else
                        ..._viewModel.comments.map(
                          (comment) => CommunityCommentTile(
                            comment: comment,
                            isOwnComment:
                                widget.currentUserId != null &&
                                comment.userId == widget.currentUserId,
                            onDelete: () => _deleteComment(comment.id),
                          ),
                        ),
                    ],
                  ),
                ),
                CommunityCommentComposer(
                  isSubmitting: _viewModel.isSubmittingComment,
                  onSubmit: _addComment,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
