import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding fixes wave (2026-10-11), Parts 1/2/3/4/8/9: covers the
/// redesigned upbringing-country question (Part 1), the polished
/// searchable modal country picker (Part 4), region refinement (Part 3),
/// Afghanistan's full acceptance path (Part 12), and the completion
/// screen's real feature grid (Part 8/9).
void main() {
  Future<void> pumpToCountryPicker(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await MadhhabController.instance.load();
    AppLocaleController.instance.setArabic(false);
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 2)),
    );

    await tester.ensureVisible(find.text("I don't know"));
    await tester.tap(find.text("I don't know"));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Help me choose'));
    await tester.tap(find.text('Help me choose'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Which country did you grow up in for most of your childhood?',
      ),
      findsOneWidget,
    );
  }

  testWidgets('no country is preselected — the field shows a neutral '
      'placeholder, not a shortlist or a default choice', (tester) async {
    await pumpToCountryPicker(tester);

    expect(find.text('Select country'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    final continueButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('tapping the field opens a searchable modal sheet titled '
      '"Search for a country"', (tester) async {
    await pumpToCountryPicker(tester);

    await tester.tap(find.text('Select country'));
    await tester.pumpAndSettle();

    expect(find.text('Search for a country'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    // The full alphabetical list is shown before any search — not a
    // preselected/recommended shortlist.
    expect(find.text('Afghanistan'), findsOneWidget);
    expect(find.text('Albania'), findsOneWidget);
  });

  testWidgets('English search finds Saudi Arabia', (tester) async {
    await pumpToCountryPicker(tester);
    await tester.tap(find.text('Select country'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Saudi');
    await tester.pump();

    expect(find.widgetWithText(ListTile, 'Saudi Arabia'), findsOneWidget);
  });

  testWidgets('Arabic search ("السعودية") finds the same country', (
    tester,
  ) async {
    await pumpToCountryPicker(tester);
    await tester.tap(find.text('Select country'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'السعودية');
    await tester.pump();

    expect(find.widgetWithText(ListTile, 'Saudi Arabia'), findsOneWidget);
  });

  testWidgets('ISO-code search ("SA") finds the same country', (
    tester,
  ) async {
    await pumpToCountryPicker(tester);
    await tester.tap(find.text('Select country'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'SA');
    await tester.pump();

    // "sa" also substring-matches several alphabetically-earlier names
    // (El Salvador, Samoa, San Marino, ...) — Saudi Arabia is last among
    // them, so it may start outside the lazy ListView's initially-built
    // range; drag the list to bring it into the built range before
    // asserting.
    for (var i = 0; i < 5; i++) {
      if (find.widgetWithText(ListTile, 'Saudi Arabia').evaluate().isNotEmpty) {
        break;
      }
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
    }
    expect(find.widgetWithText(ListTile, 'Saudi Arabia'), findsOneWidget);
  });

  testWidgets('selecting a country closes the sheet and shows it clearly '
      'on the field — tapping again reopens the picker to change it', (
    tester,
  ) async {
    await pumpToCountryPicker(tester);
    await tester.tap(find.text('Select country'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Egypt');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Egypt'));
    await tester.pumpAndSettle();

    expect(find.text('Egypt'), findsOneWidget);
    expect(find.text('Search for a country'), findsNothing);

    // Change it without navigating backward through onboarding.
    await tester.tap(find.text('Egypt'));
    await tester.pumpAndSettle();
    expect(find.text('Search for a country'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Morocco');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Morocco'));
    await tester.pumpAndSettle();

    expect(find.text('Morocco'), findsOneWidget);
    expect(find.text('Egypt'), findsNothing);
  });

  testWidgets(
    'Afghanistan: selectable, onboarding continues, no crash, and (now '
    'that real research has SOURCE_VERIFIED this entry) surfaces the '
    'real Hanafi suggestion rather than any error/blocked state',
    (tester) async {
      await pumpToCountryPicker(tester);
      await tester.tap(find.text('Select country'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Afghanistan');
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'Afghanistan'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Based on the country where you grew up, Hanafi may be '
          'the closest fit.',
        ),
        findsOneWidget,
      );
      expect(find.text('Choose the Madhhab you follow'), findsNothing);
      expect(find.text("We don't have a suggestion for that yet"), findsNothing);
      expect(find.text('Try again'), findsNothing);

      // Onboarding is never stuck — declining the suggestion ("I still
      // don't know") is reachable immediately.
      expect(find.text("I still don't know"), findsOneWidget);
    },
  );

  testWidgets(
    'region refinement only appears for a country whose reviewed mapping '
    'has more than one region (India) — not for an ordinary '
    'single-country mapping (Saudi Arabia)',
    (tester) async {
      await pumpToCountryPicker(tester);
      await tester.tap(find.text('Select country'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'India');
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'India'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        find.text('Which region did you grow up in?'),
        findsOneWidget,
        reason: 'India has a region-level mapping entry (Kerala) — a '
            'follow-up question is expected',
      );
      expect(find.text('Kerala'), findsOneWidget);

      // "My region isn't listed" never blocks her either.
      await tester.tap(find.text('My region isn\'t listed'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Choose the Madhhab you follow'), findsOneWidget);
    },
  );

  testWidgets(
    'Saudi Arabia (an ordinary single-country mapping) never shows a '
    'region question',
    (tester) async {
      await pumpToCountryPicker(tester);
      await tester.tap(find.text('Select country'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Saudi Arabia');
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'Saudi Arabia'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Which region did you grow up in?'), findsNothing);
      expect(
        find.text(
          'Based on the country where you grew up, Hanbali may be '
          'the closest fit.',
        ),
        findsOneWidget,
        reason: 'Saudi Arabia is SOURCE_VERIFIED, so this reaches the '
            'real suggestion step directly, with no region question '
            'in between',
      );
    },
  );

  group('completion screen (Part 8/9: real product features, not generic '
      'placeholders)', () {
    testWidgets(
      'shows real Niswah feature names from the shared registry, and the '
      'primary CTA',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 8),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('You’re ready to get started'), findsOneWidget);
        expect(find.text('This is what Niswah gives you'), findsOneWidget);
        for (final label in [
          'Cycle prediction',
          'Smart doctor',
          'Women community',
          'Dream interpretation',
        ]) {
          expect(
            find.text(label),
            findsOneWidget,
            reason: 'real product feature "$label" must be shown, not a '
                'generic placeholder',
          );
        }
        expect(find.text('Start tracking'), findsOneWidget);
      },
    );

    testWidgets(
      // Manual QA fix (2026-10-11), Part 1B: the completion screen's own
      // feature-grid addition had made it tall enough that the primary
      // CTA could sit below the fold on common device sizes, requiring a
      // scroll she might not realize was needed ("clipped/hidden" per the
      // report). The screen was compacted specifically so this holds
      // without scrolling on a standard-size phone.
      'the primary CTA is actually visible within a standard phone '
      'viewport without needing to scroll',
      (tester) async {
        final originalSize = tester.view.physicalSize;
        final originalRatio = tester.view.devicePixelRatio;
        tester.view.physicalSize = const Size(393, 852) * 3; // iPhone 15 Pro
        tester.view.devicePixelRatio = 3;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalRatio;
        });

        SharedPreferences.setMockInitialValues({});
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 8),
          ),
        );
        await tester.pumpAndSettle();

        final ctaRect = tester.getRect(find.text('Start tracking'));
        final viewportHeight = tester.view.physicalSize.height /
            tester.view.devicePixelRatio;
        expect(
          ctaRect.bottom,
          lessThanOrEqualTo(viewportHeight),
          reason: 'the "Start tracking" CTA must be within the visible '
              'viewport without scrolling, not clipped below the fold',
        );
      },
    );

    testWidgets('renders with no overflow at common simulator sizes', (
      tester,
    ) async {
      for (final size in [
        const Size(375, 667), // iPhone SE
        const Size(393, 852), // iPhone 15 Pro
      ]) {
        final originalSize = tester.view.physicalSize;
        final originalRatio = tester.view.devicePixelRatio;
        tester.view.physicalSize = size * tester.view.devicePixelRatio;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalRatio;
        });

        SharedPreferences.setMockInitialValues({});
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 8),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'completion screen must not overflow at $size',
        );
      }
    });
  });
}
