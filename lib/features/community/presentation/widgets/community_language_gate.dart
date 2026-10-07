import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/community_language_controller.dart';

/// Requirement 4: the first time a user enters Community (before a
/// `community_language` preference exists), Niswah must ask which
/// community she wants to browse. Called from `main.dart`'s tab-tap
/// handler — not `CommunityBoardScreen.initState`, which fires too
/// early, at app-shell-mount time, since every tab's screen mounts
/// immediately inside the home shell's `IndexedStack`.
///
/// Non-dismissible (no barrier tap, no back-button escape without a
/// choice) because, unlike Madhhab's "I don't know," there is no valid
/// "skip for now" answer here — every visit to Community must have a
/// community to show. Returns the chosen language, or null only if the
/// dialog is somehow popped without a selection (treated by the caller
/// as "don't navigate yet").
Future<CommunityLanguage?> showCommunityLanguageGate(
  BuildContext context,
) async {
  final chosen = await showDialog<CommunityLanguage>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(
          AppLocaleController.instance.text(
            'Which community would you like to browse?',
            'أي مجتمع تريدين تصفحه؟',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(CommunityLanguage.ar),
              child: Text(
                AppLocaleController.instance.text(
                  'Arabic Community',
                  'المجتمع العربي',
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(CommunityLanguage.en),
              // Literal task copy: this option reads "English Community"
              // under both the Arabic and English renderings of this
              // dialog — the community's proper name, not translated.
              child: const Text('English Community'),
            ),
          ],
        ),
      ),
    ),
  );

  if (chosen != null) {
    await CommunityLanguageController.instance.select(chosen);
  }
  return chosen;
}
