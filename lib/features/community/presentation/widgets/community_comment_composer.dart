import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../community_palette.dart';

/// Pinned bottom text input for adding a comment on the post detail screen.
class CommunityCommentComposer extends StatefulWidget {
  const CommunityCommentComposer({
    super.key,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final bool isSubmitting;
  final Future<bool> Function(String) onSubmit;

  @override
  State<CommunityCommentComposer> createState() =>
      _CommunityCommentComposerState();
}

class _CommunityCommentComposerState extends State<CommunityCommentComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    final didSubmit = await widget.onSubmit(text);
    if (didSubmit && mounted) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = CommunityPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBlush = isDark ? const Color(0xFF32171D) : Colors.white;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: palette.background,
          border: Border(top: BorderSide(color: palette.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                maxLength: 500,
                maxLines: 4,
                style: TextStyle(color: palette.text),
                cursorColor: palette.blush,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: AppLocaleController.instance.text(
                    'Write a supportive comment…',
                    'اكتبي تعليقاً داعماً…',
                  ),
                  hintStyle: TextStyle(color: palette.textFaint),
                  counterStyle: TextStyle(color: palette.textFaint),
                  filled: true,
                  fillColor: palette.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: palette.blush),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.small(
              heroTag: 'send-community-comment',
              onPressed: widget.isSubmitting ? null : _submit,
              backgroundColor: palette.blush,
              foregroundColor: onBlush,
              child: widget.isSubmitting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: onBlush,
                        semanticsLabel: AppLocaleController.instance.text(
                          'Sending comment',
                          'جارٍ إرسال التعليق',
                        ),
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
