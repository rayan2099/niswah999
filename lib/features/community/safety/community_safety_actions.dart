import 'package:flutter/material.dart';

import '../../../core/localization/app_locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import 'community_safety_controller.dart';
import 'community_safety_models.dart';
import 'community_write_error.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Asks why, then files a report. Returns true when a report was filed.
Future<bool> showCommunityReportSheet(
  BuildContext context, {
  required ReportTargetType targetType,
  required String targetId,
  CommunitySafetyController? controller,
}) async {
  final safety = controller ?? CommunitySafetyController.instance;
  final filed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      safety: safety,
    ),
  );
  if (filed == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            'Thank you. Our moderators review reports within 24 hours.',
            'شكراً لكِ. تراجع المشرفات البلاغات خلال 24 ساعة.',
          ),
        ),
      ),
    );
  }
  return filed == true;
}

/// Confirms, then blocks [userId]. Returns true when the member was blocked.
Future<bool> confirmBlockMember(
  BuildContext context, {
  required String userId,
  String? displayName,
  CommunitySafetyController? controller,
}) async {
  final safety = controller ?? CommunitySafetyController.instance;
  final name = displayName?.trim();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        name == null || name.isEmpty
            ? _t('Block this member?', 'حظر هذه العضوة؟')
            : _t('Block $name?', 'حظر $name؟'),
      ),
      content: Text(
        _t(
          'You won\'t see her posts or comments, and neither of you can '
              'message or comment on the other. She isn\'t told. You can '
              'unblock her from Profile → Blocked members.',
          'لن تري منشوراتها أو تعليقاتها، ولن تتمكن أيٌّ منكما من مراسلة '
              'الأخرى أو التعليق لها. لن يتم إعلامها. يمكنكِ إلغاء الحظر من '
              'الملف الشخصي ← العضوات المحظورات.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(_t('Cancel', 'إلغاء')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            _t('Block', 'حظر'),
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await safety.block(userId: userId, displayName: displayName);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            CommunityWriteError.from(error)?.message() ??
                _t(
                  'Could not block this member. Please try again.',
                  'تعذر حظر هذه العضوة. يُرجى المحاولة مجدداً.',
                ),
          ),
        ),
      );
    }
    return false;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('Member blocked', 'تم حظر العضوة'))),
    );
  }
  return true;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.safety,
  });

  final ReportTargetType targetType;
  final String targetId;
  final CommunitySafetyController safety;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String get _title => switch (widget.targetType) {
    ReportTargetType.post => _t('Report post', 'الإبلاغ عن المنشور'),
    ReportTargetType.comment => _t('Report comment', 'الإبلاغ عن التعليق'),
    ReportTargetType.message => _t('Report message', 'الإبلاغ عن الرسالة'),
    ReportTargetType.user => _t('Report member', 'الإبلاغ عن العضوة'),
  };

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.safety.report(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: reason,
        details: _details.text.trim().isEmpty ? null : _details.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error =
            CommunityWriteError.from(error)?.message() ??
            _t(
              'Could not send the report. Please try again.',
              'تعذر إرسال البلاغ. يُرجى المحاولة مجدداً.',
            );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 20,
          end: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                _t(
                  'Your report is private. Tell us what\'s wrong.',
                  'بلاغكِ سرّي. أخبرينا ما المشكلة.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: Column(
                  children: [
                    for (final reason in ReportReason.values)
                      RadioListTile<ReportReason>(
                        key: ValueKey('report-reason-${reason.name}'),
                        value: reason,
                        title: Text(reason.label()),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _details,
                maxLength: 1000,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: _t(
                    'Anything else? (optional)',
                    'تفاصيل إضافية (اختياري)',
                  ),
                ),
              ),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.error)),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const ValueKey('report-submit'),
                onPressed: _reason == null || _submitting ? null : _submit,
                child: Text(
                  _submitting
                      ? _t('Sending…', 'جارٍ الإرسال…')
                      : _t('Send report', 'إرسال البلاغ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
