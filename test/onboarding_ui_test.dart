import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('onboarding starts with the branded splash and advances', (
    tester,
  ) async {
    AppLocaleController.instance.setArabic(false);
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onFinished: () {})),
    );

    expect(find.text('Niswah'), findsOneWidget);
    expect(find.text('YOUR CYCLE. YOUR FAITH. YOUR SPACE.'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
  });

  testWidgets('language selection switches onboarding to RTL', (tester) async {
    AppLocaleController.instance.setArabic(false);
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onFinished: () {})),
    );
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Directionality &&
            widget.textDirection == TextDirection.rtl,
      ),
      findsWidgets,
    );
  });

  testWidgets('onboarding asks marital status and stores the answer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    await MaritalStatusController.instance.load();
    await tester.pumpWidget(
      // Start at the madhhab step (4) since login has no skip path.
      MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 4)),
    );

    await tester.tap(find.text('Hanbali'));
    await tester.pump();
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Are you married?'), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.pump();
    expect(MaritalStatusController.instance.isMarried, isTrue);
  });

  testWidgets(
    'a returning user re-routed through onboarding (e.g. after signing '
    'out) does not have their saved "married" answer silently reset',
    (tester) async {
      // Simulate a user who already answered "married: true" in a prior
      // session — the persisted value onboarding must not clobber.
      SharedPreferences.setMockInitialValues({'niswah_is_married': true});
      AppLocaleController.instance.setArabic(false);
      await MaritalStatusController.instance.load();
      expect(MaritalStatusController.instance.isMarried, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onFinished: () {}, initialStep: 5),
        ),
      );

      expect(find.text('Are you married?'), findsOneWidget);
      // Advance without touching Yes/No — Continue must already be
      // enabled because the prior answer was pre-selected. If it weren't
      // (the bug), Continue stays disabled and tapping it is a no-op, so
      // assert real advancement to the next step, not just a lack of crash.
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Are you married?'), findsNothing);
      expect(find.text('Where are you located?'), findsOneWidget);
      expect(MaritalStatusController.instance.isMarried, isTrue);
    },
  );

  testWidgets('picking a madhhab persists it immediately, not just locally', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 4)),
    );

    await tester.tap(find.text('Hanafi'));
    await tester.pump();

    expect(MadhhabController.instance.selected, Madhhab.hanafi);
  });

  testWidgets(
    'finishing onboarding with a reported last period seeds a real cycle '
    'log instead of discarding the answer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onFinished: () {}, initialStep: 7),
        ),
      );

      expect(find.text('When did your last period start?'), findsOneWidget);
      final dayCells = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(InkWell),
      );
      await tester.tap(dayCells.last); // selects today
      await tester.pump();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('How long is your period?'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 9 is now anonymous-mode only — the fake Face ID/PIN chooser
      // must be gone.
      expect(find.text('Face ID / Touch ID'), findsNothing);
      expect(find.text('PIN code'), findsNothing);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Get Started'), findsOneWidget);
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      final logs = await CycleTrackingRepositoryImpl().getCycleLogs();
      expect(logs, isNotEmpty);
      expect(logs.every((log) => log.userId == 'local-user'), isTrue);
      // Default period length (5 days), never touched in this flow.
      expect(logs.length, 5);
      expect(logs.map((log) => log.cycleDay).toSet(), {1, 2, 3, 4, 5});

      // A single reported start is still only one Haid start — onboarding
      // can never fabricate the second one the app genuinely needs.
      final calculation = const CycleCalculationService().calculate(logs);
      expect(calculation.haidStarts, hasLength(1));
      expect(calculation.hasSufficientHistory, isFalse);
    },
  );
}
