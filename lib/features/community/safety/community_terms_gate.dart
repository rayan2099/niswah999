import 'package:flutter/material.dart';

import '../../../core/localization/app_locale_controller.dart';
import 'community_guidelines_screen.dart';
import 'community_safety_controller.dart';
import 'community_terms.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Makes sure the member accepted the current [CommunityTerms] before she
/// enters Community or private messages. Returns true when she has (now or
/// before); false when she declined or acceptance could not be saved.
///
/// Called from the Community tab tap in main.dart and from Profile →
/// Messages, the two entry points to user-generated content.
Future<bool> ensureCommunityTermsAccepted(
  BuildContext context, {
  CommunitySafetyController? controller,
}) async {
  final safety = controller ?? CommunitySafetyController.instance;
  if (await safety.refreshTermsAccepted() == true) return true;
  if (!context.mounted) return false;

  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _CommunityTermsDialog(safety: safety),
  );
  return accepted == true;
}

class _CommunityTermsDialog extends StatefulWidget {
  const _CommunityTermsDialog({required this.safety});

  final CommunitySafetyController safety;

  @override
  State<_CommunityTermsDialog> createState() => _CommunityTermsDialogState();
}

class _CommunityTermsDialogState extends State<_CommunityTermsDialog> {
  bool _agreed = false;
  bool _saving = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.safety.acceptTerms();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _t(
          'Could not save your answer. Check your connection and try again.',
          'تعذر حفظ إجابتكِ. تحققي من اتصالكِ وحاولي مجدداً.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(CommunityTerms.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              CommunityTerms.summary,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (final rule in CommunityTerms.rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $rule', style: textTheme.bodySmall),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CommunityGuidelinesScreen(),
                ),
              ),
              child: Text(
                _t('Read the full guidelines', 'اقرئي الإرشادات كاملة'),
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('community-terms-agree'),
              value: _agreed,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _agreed = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                _t(
                  'I agree to the community guidelines and understand that '
                      'abusive content or behaviour is not tolerated.',
                  'أوافق على إرشادات المجتمع وأفهم أن المحتوى أو السلوك '
                      'المسيء غير مقبول.',
                ),
                style: textTheme.bodySmall,
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(_t('Not now', 'ليس الآن')),
        ),
        FilledButton(
          key: const ValueKey('community-terms-accept'),
          onPressed: _agreed && !_saving ? _accept : null,
          child: Text(_t('Agree and continue', 'أوافق وأتابع')),
        ),
      ],
    );
  }
}
