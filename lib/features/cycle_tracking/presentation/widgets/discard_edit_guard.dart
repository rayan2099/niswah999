import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';

/// PT-178: wraps a tracking sheet so Back, a Close button that calls
/// `Navigator.maybePop`, or a tap outside never silently drops a change she
/// has made but not saved, and never closes the sheet while a save is in
/// flight (its outcome must reach her). With nothing changed, the sheet
/// closes as before.
class DiscardEditGuard extends StatelessWidget {
  const DiscardEditGuard({
    super.key,
    required this.hasUnsavedChange,
    required this.saving,
    required this.child,
  });

  final bool hasUnsavedChange;
  final bool saving;
  final Widget child;

  static String _t(String en, String ar) =>
      AppLocaleController.instance.text(en, ar);

  Future<void> _confirm(BuildContext context) async {
    if (saving) return;
    final arabic = AppLocaleController.instance.isArabic;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(_t('Discard this change?', 'تجاهل هذا التعديل؟')),
          content: Text(
            _t(
              "What you changed here hasn't been saved. Your records stay "
                  'as they are.',
              'ما غيّرتِه هنا لم يُحفظ. ستبقى سجلاتكِ كما هي.',
            ),
          ),
          actions: [
            TextButton(
              key: const Key('discard-edit-keep'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_t('Keep editing', 'متابعة التعديل')),
            ),
            TextButton(
              key: const Key('discard-edit-discard'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_t('Discard', 'تجاهل')),
            ),
          ],
        ),
      ),
    );
    if (discard == true && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !saving && !hasUnsavedChange,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _confirm(context);
    },
    child: child,
  );
}
