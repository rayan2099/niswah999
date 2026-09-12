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

  // RR-009 (expanded) / onboarding language->login transition regression
  // suite, 2026-09-12. Root cause: step 3 (SignInScreen) is a full nested
  // Scaffold rendered as one step inside this screen's shared shell, which
  // wrapped every step in SingleChildScrollView -> AnimatedSwitcher ->
  // FadeTransition. A nested Scaffold (and AnimatedSwitcher's own internal
  // Stack) cannot be laid out inside a scroll view's inherently unbounded
  // child slot — Flutter throws "RenderAnimatedOpacity object was given an
  // infinite size during layout" the instant the switcher tries to
  // transition into step 3, leaving a blank body with only the progress
  // bar/back button (which live outside the switcher) visible. None of the
  // existing tests above ever exercised this transition — every one of
  // them jumps past step 3 via `initialStep`. Fixed by capturing the real,
  // already-bounded viewport height via LayoutBuilder (placed outside the
  // scroll view) and re-imposing it as a genuine max-height ceiling on the
  // switched content.
  group('language -> login step transition (RR-009 root cause)', () {
    testWidgets(
      'English: selecting language and continuing reaches real sign-in '
      'content, not a blank body',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {})),
        );
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('English').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'the language -> login transition must not throw a layout '
              'exception',
        );
        expect(
          find.text('Understand your cycle, with peace of mind'),
          findsOneWidget,
          reason: 'step 3 must show real sign-in content, not a blank body',
        );
        expect(find.text('Choose your language'), findsNothing);
      },
    );

    testWidgets(
      'Arabic: selecting language and continuing reaches real sign-in '
      'content, not a blank body',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {})),
        );
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('العربية'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('متابعة'));
        await tester.tap(find.text('متابعة'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'the language -> login transition must not throw a layout '
              'exception',
        );
        expect(
          find.text('افهمي دورتكِ واطمنّي'),
          findsOneWidget,
          reason: 'step 3 must show real sign-in content, not a blank body',
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Directionality &&
                widget.textDirection == TextDirection.rtl,
          ),
          findsWidgets,
          reason: 'step 3 must still render RTL after the transition',
        );
      },
    );

    testWidgets(
      'a locale change mid-onboarding does not desynchronize the step '
      'index or lose onboarding state',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {})),
        );
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();
        expect(find.text('Choose your language'), findsOneWidget);

        // Toggling the selection back and forth before continuing must
        // not corrupt the step machine.
        await tester.tap(find.text('العربية'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('English').first);
        await tester.pumpAndSettle();
        expect(find.text('Choose your language'), findsOneWidget);

        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Understand your cycle, with peace of mind'),
          findsOneWidget,
        );
      },
    );

    testWidgets('back navigation from step 3 returns to the language step', (
      tester,
    ) async {
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onFinished: () {})),
      );
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.text('Understand your cycle, with peace of mind'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Choose your language'), findsOneWidget);
    });

    testWidgets(
      'continue navigation still works after going back once',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {})),
        );
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('English').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Understand your cycle, with peace of mind'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the language -> login transition renders with no layout exception '
      'on a small viewport',
      (tester) async {
        final originalSize = tester.view.physicalSize;
        final originalRatio = tester.view.devicePixelRatio;
        tester.view.physicalSize = const Size(320, 568); // small phone
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalRatio;
        });

        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {})),
        );
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('English').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'a small viewport must not reintroduce the infinite-size '
              'layout exception',
        );
        expect(
          find.text('Understand your cycle, with peace of mind'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the language -> login transition renders with no layout exception '
      'at 200% text scale',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: OnboardingScreen(onFinished: () {}),
          ),
        );
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('English').first);
        await tester.tap(find.text('English').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '200% text scale must not reintroduce the infinite-size '
              'layout exception',
        );
        expect(
          find.text('Understand your cycle, with peace of mind'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the language -> login transition renders with no layout exception '
      'with semantics enabled',
      (tester) async {
        final handle = tester.ensureSemantics();

        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {})),
        );
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('English').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Understand your cycle, with peace of mind'),
          findsOneWidget,
        );
        handle.dispose();
      },
    );
  });

  // Section L: every reachable onboarding step must resolve to real
  // content — never just the shared shell (progress bar/back button) with
  // an empty body. Iterates the full state machine directly via
  // initialStep, the same mechanism the existing tests above already use
  // to reach steps 4+, extended here to cover every step including the
  // one (3) no prior test ever exercised.
  group('all-onboarding-step state machine (no step may render empty)', () {
    final stepContent = <int, String>{
      1: 'Niswah',
      2: 'Choose your language',
      3: 'Understand your cycle, with peace of mind',
      4: 'What is your Fiqh Madhhab?',
      5: 'Are you married?',
      6: 'Where are you located?',
      7: 'When did your last period start?',
      8: 'How long is your period?',
      9: 'Anonymous Mode',
      10: 'You’re all set!',
    };

    for (final entry in stepContent.entries) {
      testWidgets(
        'step ${entry.key} renders its real content, not just the shell',
        (tester) async {
          AppLocaleController.instance.setArabic(false);
          await tester.pumpWidget(
            MaterialApp(
              home: OnboardingScreen(
                onFinished: () {},
                initialStep: entry.key,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'step ${entry.key} must not throw a layout exception',
          );
          expect(
            find.text(entry.value),
            findsOneWidget,
            reason:
                'step ${entry.key} must show its real content — a step '
                'rendering only the shared progress bar/back button shell '
                'with an empty body must fail this assertion',
          );
        },
      );
    }
  });
}
