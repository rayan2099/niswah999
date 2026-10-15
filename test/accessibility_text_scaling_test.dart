import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/auth/presentation/screens/profile_screen.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:niswah/features/onboarding/presentation/screens/onboarding_screen.dart';

/// AU-006 / Phase D: the dashboard's cycle ring and phase-timeline nodes
/// render inside fixed-pixel-diameter containers. This wave wrapped their
/// value/unit/headline text in `FittedBox(fit: BoxFit.scaleDown)` so large
/// OS text-scale settings shrink the text to fit rather than clipping
/// against the circle. These tests render the real dashboard at large
/// scale factors and fail on any layout overflow exception — a stronger
/// check than reading the code, though still not a substitute for a real
/// device's actual Dynamic Type / font-scale setting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDashboardAtScale(
    WidgetTester tester,
    double scale, {
    bool arabic = false,
  }) async {
    AppLocaleController.instance.setArabic(arabic);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const DashboardScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final scale in [1.0, 1.5, 2.0, 3.0]) {
    testWidgets(
      'dashboard renders with no layout overflow at ${scale}x text scale '
      '(English)',
      (tester) async {
        await pumpDashboardAtScale(tester, scale);
        expect(
          tester.takeException(),
          isNull,
          reason:
              'a RenderFlex overflow or other layout exception was thrown '
              'at ${scale}x text scale',
        );
      },
    );

    testWidgets(
      'dashboard renders with no layout overflow at ${scale}x text scale '
      '(Arabic/RTL)',
      (tester) async {
        await pumpDashboardAtScale(tester, scale, arabic: true);
        expect(
          tester.takeException(),
          isNull,
          reason:
              'a RenderFlex overflow or other layout exception was thrown '
              'at ${scale}x text scale in Arabic',
        );
      },
    );
  }

  group('Fiqh Remediation Wave 1 — Pre-E4 Verification (Section 1): Madhhab '
      'onboarding + Settings at 200% text scale and small viewport', () {
    Future<void> pumpOnboardingMadhhabAtScale(
      WidgetTester tester,
      double scale, {
      bool arabic = false,
    }) async {
      AppLocaleController.instance.setArabic(arabic);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: OnboardingScreen(onFinished: () {}, initialStep: 2),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('Madhhab choice grid (5 options) renders with no overflow at '
          '${scale}x text scale (English)', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        await pumpOnboardingMadhhabAtScale(tester, scale);

        for (final label in [
          'Hanafi',
          'Maliki',
          "Shafi'i",
          'Hanbali',
          "I don't know",
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('Madhhab choice grid (5 options) renders with no overflow at '
          '${scale}x text scale (Arabic)', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        await pumpOnboardingMadhhabAtScale(tester, scale, arabic: true);

        for (final label in ['حنفي', 'مالكي', 'شافعي', 'حنبلي', 'لا أعرف']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        AppLocaleController.instance.setArabic(false);
      });

      testWidgets(
        'the full "I don\'t know" sub-flow (explanation, help-me-choose, '
        'suggestion) is usable at ${scale}x text scale, no overflow',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          await MadhhabController.instance.load();
          await pumpOnboardingMadhhabAtScale(tester, scale);

          await tester.ensureVisible(find.text("I don't know"));
          await tester.tap(find.text("I don't know"));
          await tester.pumpAndSettle();
          expect(find.text('No problem'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.ensureVisible(find.text('Help me choose'));
          await tester.tap(find.text('Help me choose'));
          await tester.pumpAndSettle();
          // Current upbringing-country question (Manual QA wave,
          // 2026-10-12) — replaces the old free-text "Which country do
          // you live in?" residence question with a searchable modal
          // picker over the upbringing country.
          expect(
            find.text(
              'Which country did you grow up in for most of your childhood?',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await tester.ensureVisible(find.text('Select country'));
          await tester.tap(find.text('Select country'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Tunisia: a real, researched entry that stays UNVERIFIED (see
          // geographic_madhhab_mapping.json's own review_notes) — lands on
          // the manual-selection fallback, exercising the same "no
          // suggestion available, every control still reachable" layout
          // the original test covered, with current, non-stale copy.
          await tester.enterText(find.byType(TextField), 'Tunisia');
          await tester.pump();
          await tester.tap(find.widgetWithText(ListTile, 'Tunisia'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Continue'));
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();

          expect(find.text('Choose the Madhhab you follow'), findsOneWidget);
          for (final label in [
            'Hanafi',
            'Maliki',
            "Shafi'i",
            'Hanbali',
            "I don't know",
          ]) {
            expect(
              find.text(label),
              findsOneWidget,
              reason: 'every manual-selection control, including the '
                  '"I don\'t know" fallback, must still be reachable at '
                  '${scale}x text scale',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'Madhhab choice grid usable at a small viewport (320x568, iPhone SE)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );
        await tester.pumpAndSettle();

        for (final label in [
          'Hanafi',
          'Maliki',
          "Shafi'i",
          'Hanbali',
          "I don't know",
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Settings\' Madhhab grid (including "I don\'t know") renders with '
      'no overflow at 200% text scale',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: const ProfileScreen(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Fiqh Madhhab'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.text('Fiqh Madhhab'), findsOneWidget);
        expect(find.text("I don't know"), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Settings\' Madhhab grid usable at a small viewport (320x568)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Fiqh Madhhab'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.text('Fiqh Madhhab'), findsOneWidget);
        expect(find.text("I don't know"), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
