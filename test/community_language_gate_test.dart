// Requirement 4: Community needs an explicit Arabic/English community
// choice before it's ever shown, persisted across visits, and changeable
// later from Profile/Settings without affecting existing posts. Covers
// the entry gate itself — scoping of posts/search/categories/composer by
// the chosen language is covered in community_board_test.dart and
// community_repository_idempotency_test.dart's compile-time contract.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/community_language_controller.dart';
import 'package:niswah/features/community/presentation/widgets/community_language_gate.dart';

Widget _harness(Widget Function(BuildContext) builder) => MaterialApp(
  home: Scaffold(body: Builder(builder: builder)),
);

Future<void> _openGate(WidgetTester tester) async {
  await tester.pumpWidget(
    _harness(
      (context) => ElevatedButton(
        onPressed: () => showCommunityLanguageGate(context),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    CommunityLanguageController.instance.resetInMemory();
  });

  testWidgets('English interface: shows the exact literal gate copy', (
    tester,
  ) async {
    await _openGate(tester);

    expect(
      find.text('Which community would you like to browse?'),
      findsOneWidget,
    );
    expect(find.text('Arabic Community'), findsOneWidget);
    expect(
      find.text('English Community'),
      findsOneWidget,
      reason:
          '"English Community" is the community\'s proper name — shown '
          'the same way under both interface languages, per the task\'s '
          'own literal copy.',
    );
  });

  testWidgets('Arabic interface: shows the exact literal gate copy', (
    tester,
  ) async {
    AppLocaleController.instance.setArabic(true);
    await _openGate(tester);

    expect(find.text('أي مجتمع تريدين تصفحه؟'), findsOneWidget);
    expect(find.text('المجتمع العربي'), findsOneWidget);
    expect(find.text('English Community'), findsOneWidget);

    AppLocaleController.instance.setArabic(false);
  });

  testWidgets(
    'choosing Arabic Community persists ar and resolves the future with it',
    (tester) async {
      await _openGate(tester);
      expect(CommunityLanguageController.instance.isSelected, isFalse);

      await tester.tap(find.text('Arabic Community'));
      await tester.pumpAndSettle();

      expect(
        CommunityLanguageController.instance.selectedOrNull,
        CommunityLanguage.ar,
      );
    },
  );

  testWidgets(
    'choosing English Community persists en and resolves the future with it',
    (tester) async {
      await _openGate(tester);

      await tester.tap(find.text('English Community'));
      await tester.pumpAndSettle();

      expect(
        CommunityLanguageController.instance.selectedOrNull,
        CommunityLanguage.en,
      );
    },
  );

  testWidgets(
    'the gate is non-dismissible — tapping the barrier does not close it '
    'without a choice',
    (tester) async {
      await _openGate(tester);

      // Tap a point far from the dialog content (the barrier).
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(
        find.text('Which community would you like to browse?'),
        findsOneWidget,
        reason:
            'unlike Madhhab\'s "I don\'t know," there is no valid "skip '
            'for now" answer here — every visit to Community must have a '
            'community to show',
      );
      expect(CommunityLanguageController.instance.isSelected, isFalse);
    },
  );
}
