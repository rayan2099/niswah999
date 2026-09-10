import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/selectable_chip.dart';
import '../../domain/entities/community_category_x.dart';
import '../../domain/entities/community_post.dart';
import '../community_palette.dart';
import '../viewmodels/community_feed_view_model.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

Future<void> showCommunityComposerSheet(
  BuildContext context, {
  required CommunityFeedViewModel viewModel,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: CommunityPalette.of(context).background,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder: (_) => _CommunityComposerSheet(viewModel: viewModel),
);

class _CommunityComposerSheet extends StatefulWidget {
  const _CommunityComposerSheet({required this.viewModel});
  final CommunityFeedViewModel viewModel;

  @override
  State<_CommunityComposerSheet> createState() =>
      _CommunityComposerSheetState();
}

class _CommunityComposerSheetState extends State<_CommunityComposerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  CommunityCategory _category = CommunityCategory.general;
  bool _anonymous = true;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final didCreate = await widget.viewModel.createPost(
      content: _contentController.text,
      category: _category,
      isAnonymous: _anonymous,
    );
    if (didCreate && mounted) Navigator.pop(context);
  }

  InputDecoration _fieldDecoration(
    CommunityColors palette, {
    required String label,
    String? hint,
    bool alignLabelWithHint = false,
  }) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: palette.textMuted),
    floatingLabelStyle: TextStyle(color: palette.blush),
    hintText: hint,
    hintStyle: TextStyle(color: palette.textFaint),
    alignLabelWithHint: alignLabelWithHint,
    filled: true,
    fillColor: palette.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.blush),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.error),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = CommunityPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBlush = isDark ? const Color(0xFF32171D) : Colors.white;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _t('Start a conversation', 'ابدئي محادثة'),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: palette.text,
                            fontFamily: AppTypography.serifFamily,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: _t('Close', 'إغلاق'),
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: palette.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: palette.blush.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notes_rounded, size: 17, color: palette.blush),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t(
                          'Text only · Photos and videos are not supported',
                          'نص فقط · الصور ومقاطع الفيديو غير مدعومة',
                        ),
                        style: TextStyle(
                          color: palette.blush,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _contentController,
                minLines: 5,
                maxLines: 8,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: palette.text),
                cursorColor: palette.blush,
                decoration: _fieldDecoration(
                  palette,
                  label: _t('Your post', 'منشوركِ'),
                  hint: _t(
                    'Share a question, experience, or words of support…',
                    'شاركي سؤالاً أو تجربة أو كلمات دعم…',
                  ),
                  alignLabelWithHint: true,
                ).copyWith(counterStyle: TextStyle(color: palette.textFaint)),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? _t(
                        'Write a message before posting.',
                        'اكتبي رسالة قبل النشر.',
                      )
                    : null,
              ),
              const SizedBox(height: 14),
              Text(
                _t('Topic', 'الموضوع'),
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in CommunityCategory.values)
                    SelectableChip(
                      label: category.label(),
                      selected: _category == category,
                      onTap: () => setState(() => _category = category),
                      dark: isDark,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: palette.blush,
                activeTrackColor: palette.border,
                title: Text(
                  _t('Post anonymously', 'النشر بشكل مجهول'),
                  style: TextStyle(color: palette.text),
                ),
                subtitle: Text(
                  _anonymous
                      ? _t(
                          'Your name will appear as Visitor.',
                          'سيظهر اسمكِ كزائرة.',
                        )
                      : _t(
                          'Your profile name will be visible.',
                          'سيظهر اسم ملفكِ الشخصي.',
                        ),
                  style: TextStyle(fontSize: 10, color: palette.textFaint),
                ),
                value: _anonymous,
                onChanged: (value) => setState(() => _anonymous = value),
              ),
              AnimatedBuilder(
                animation: widget.viewModel,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.viewModel.errorMessage != null) ...[
                      Text(
                        widget.viewModel.errorMessage!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton.icon(
                      onPressed: widget.viewModel.isSubmitting ? null : _submit,
                      icon: widget.viewModel.isSubmitting
                          ? SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: onBlush,
                                semanticsLabel: _t('Posting', 'جارٍ النشر'),
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(_t('Publish post', 'نشر المنشور')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: palette.blush,
                        foregroundColor: onBlush,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
