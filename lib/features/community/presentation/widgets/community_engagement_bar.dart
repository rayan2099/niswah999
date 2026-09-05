import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../community_palette.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Like/comment/message row shown on both the feed's post cards and the
/// post detail screen. Dumb widget — callbacks bubble up to whoever owns
/// the relevant view model.
class CommunityEngagementBar extends StatelessWidget {
  const CommunityEngagementBar({
    super.key,
    required this.likeCount,
    required this.isLiked,
    required this.commentCount,
    required this.onLike,
    required this.onCommentTap,
    this.onMessageTap,
  });

  final int likeCount;
  final bool isLiked;
  final int commentCount;
  final VoidCallback onLike;
  final VoidCallback onCommentTap;

  /// Omitted entirely (not just disabled) for anonymous posts and your own
  /// posts — showing a disabled affordance would still imply the action
  /// exists there.
  final VoidCallback? onMessageTap;

  @override
  Widget build(BuildContext context) {
    final palette = CommunityPalette.of(context);
    return Row(
      children: [
        _EngagementButton(
          icon: isLiked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          iconColor: isLiked ? palette.blush : palette.textFaint,
          label: '$likeCount',
          semanticLabel: _t('Like post', 'الإعجاب بالمنشور'),
          onTap: onLike,
        ),
        const SizedBox(width: 18),
        _EngagementButton(
          icon: Icons.chat_bubble_outline_rounded,
          iconColor: palette.textFaint,
          label: '$commentCount',
          semanticLabel: _t('Open comments', 'فتح التعليقات'),
          onTap: onCommentTap,
        ),
        const Spacer(),
        if (onMessageTap != null)
          _EngagementButton(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: palette.blush,
            label: _t('Message', 'رسالة'),
            semanticLabel: _t('Message author', 'مراسلة صاحبة المنشور'),
            onTap: onMessageTap!,
          ),
      ],
    );
  }
}

/// Small pill button used to start a conversation with a post's author —
/// shown in the post card header and the detail screen, in place of a
/// message icon inside the engagement bar itself.
class ContactAuthorButton extends StatelessWidget {
  const ContactAuthorButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CommunityPalette.of(context);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.mail_outline_rounded, size: 15),
      label: Text(_t('Connect', 'تواصلي معها')),
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.blush,
        side: BorderSide(color: palette.border),
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        shape: const StadiumBorder(),
      ),
    );
  }
}

class _EngagementButton extends StatelessWidget {
  const _EngagementButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String? label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    // semanticLabel is deliberately a distinct, complete parameter from
    // the visible `label` (e.g. it can spell out "42 likes" while the
    // visible text just shows "42") — without this, the visible Text's
    // own semantics would merge in as a redundant trailing fragment.
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 21),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
