import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';
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
      // Start at the madhhab step (3 — AUTH-008 removed the old embedded
      // login step that used to occupy step 3).
      MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 3)),
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
          home: OnboardingScreen(onFinished: () {}, initialStep: 4),
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
      MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 3)),
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
          home: OnboardingScreen(onFinished: () {}, initialStep: 6),
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

      // Step 8 is now anonymous-mode only — the fake Face ID/PIN chooser
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

  // AUTH-008 removed onboarding's old embedded login step (formerly step
  // 3, a full nested SignInScreen — the exact widget RR-009 root-caused a
  // layout crash in). It is gone from the state machine entirely — the
  // transition tested below is now language(2) -> Madhhab(3) directly.
  // These tests preserve the general transition-safety coverage the old
  // RR-009 suite established (small viewport, text scale, semantics, back
  // navigation) against whatever now occupies that position, even though
  // the original crash mechanism (a nested Scaffold inside this screen's
  // unbounded scroll slot) can no longer occur — no step is a nested
  // Scaffold any more.
  group('language -> Madhhab step transition (AUTH-008)', () {
    testWidgets(
      'English: selecting language and continuing reaches real Madhhab '
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

        expect(tester.takeException(), isNull);
        expect(
          find.text('What is your Fiqh Madhhab?'),
          findsOneWidget,
          reason: 'step 3 must show real Madhhab content, not a blank body',
        );
        expect(find.text('Choose your language'), findsNothing);
      },
    );

    testWidgets(
      'Arabic: selecting language and continuing reaches real Madhhab '
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

        expect(tester.takeException(), isNull);
        expect(
          find.text('ما مذهبكِ الفقهي؟'),
          findsOneWidget,
          reason: 'step 3 must show real Madhhab content, not a blank body',
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
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
      },
    );

    testWidgets(
      'back navigation from step 3 returns to the language step, never '
      'to a Sign In screen',
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
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Choose your language'), findsOneWidget);
        expect(find.text('Email'), findsNothing);
        expect(find.text('Mobile'), findsNothing);
      },
    );

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
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
      },
    );

    testWidgets(
      'the language -> Madhhab transition renders with no layout exception '
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

        expect(tester.takeException(), isNull);
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
      },
    );

    testWidgets(
      'the language -> Madhhab transition renders with no layout exception '
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

        expect(tester.takeException(), isNull);
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
      },
    );

    testWidgets(
      'the language -> Madhhab transition renders with no layout exception '
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
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
        handle.dispose();
      },
    );
  });

  // Section L/O: every reachable onboarding step must resolve to real
  // content — never just the shared shell (progress bar/back button) with
  // an empty body. Iterates the full state machine directly via
  // initialStep. AUTH-008 removed the old step 3 (embedded login) — the
  // state machine now has 9 steps, not 10; there is no longer a login/
  // signup step anywhere in this sequence.
  group('all-onboarding-step state machine (no step may render empty)', () {
    final stepContent = <int, String>{
      1: 'Niswah',
      2: 'Choose your language',
      3: 'What is your Fiqh Madhhab?',
      4: 'Are you married?',
      5: 'Where are you located?',
      6: 'When did your last period start?',
      7: 'How long is your period?',
      8: 'Anonymous Mode',
      9: 'You’re all set!',
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
          expect(
            find.byType(SignInScreen),
            findsNothing,
            reason:
                'AUTH-008: no onboarding step may show a Sign In/Sign Up '
                'screen — this screen is only ever reached already '
                'authenticated.',
          );
        },
      );
    }
  });

  // AUTH-007 root cause: `_OnboardingScreenState` used to keep its own
  // `_arabic` field, initialized to a hardcoded `false`, completely
  // disconnected from `AppLocaleController.instance.isArabic` (the real,
  // SharedPreferences-persisted source of truth already used by the
  // language-selection step itself, and by `SignInScreen`). Any time a
  // fresh `OnboardingScreen`/`_OnboardingScreenState` was created after the
  // user had already picked Arabic in an earlier attempt (e.g. the app
  // process being recreated while the user leaves to confirm their email),
  // every step driven by that local field silently fell back to English —
  // this is exactly what the owner saw at the Madhhab step. The tests
  // below construct `OnboardingScreen` fresh with `AppLocaleController`
  // already set, exactly reproducing that scenario — unlike every test
  // above, which always resets `AppLocaleController` to English first and
  // therefore could never have caught this.
  group('AUTH-007 — Arabic locale propagates to a freshly-created '
      'OnboardingScreen (no fallback to English)', () {
    final arabicStepContent = <int, String>{
      1: 'دورتكِ. دينكِ. مساحتكِ.',
      2: 'اختاري لغتكِ',
      3: 'ما مذهبكِ الفقهي؟',
      4: 'هل أنتِ متزوجة؟',
      5: 'أين تسكنين؟',
      6: 'متى بدأ آخر حيض لديكِ؟',
      7: 'كم تستمر مدة الحيض؟',
      8: 'الوضع المجهول',
      9: 'كل شيء جاهز!',
    };
    final englishMarkerForStep = <int, String>{
      1: 'YOUR CYCLE. YOUR FAITH. YOUR SPACE.',
      2: 'Choose your language',
      3: 'What is your Fiqh Madhhab?',
      4: 'Are you married?',
      5: 'Where are you located?',
      6: 'When did your last period start?',
      7: 'How long is your period?',
      8: 'Anonymous Mode',
      9: 'You’re all set!',
    };

    for (final entry in arabicStepContent.entries) {
      testWidgets(
        'step ${entry.key} renders Arabic immediately on a freshly-created '
        'OnboardingScreen when Arabic was already selected',
        (tester) async {
          // The already-persisted choice from an earlier attempt/process —
          // set BEFORE the widget is ever built, exactly like a real app
          // restart with `AppLocaleController.instance.load()` already
          // having read `niswah_arabic=true` from SharedPreferences.
          AppLocaleController.instance.setArabic(true);
          await tester.pumpWidget(
            MaterialApp(
              home: OnboardingScreen(
                onFinished: () {},
                initialStep: entry.key,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            find.text(entry.value),
            findsOneWidget,
            reason:
                'step ${entry.key} must render its Arabic content on a '
                'fresh OnboardingScreen instance when Arabic was already '
                'the persisted choice — falling back to English here is '
                'the exact AUTH-007 defect.',
          );
          expect(
            find.text(englishMarkerForStep[entry.key]!),
            findsNothing,
            reason:
                'step ${entry.key} must not show its English marker text '
                'while Arabic is the active locale.',
          );
        },
      );
    }

    testWidgets('Madhhab step shows the correct Arabic madhhab names', (
      tester,
    ) async {
      AppLocaleController.instance.setArabic(true);
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onFinished: () {}, initialStep: 3),
        ),
      );
      await tester.pumpAndSettle();

      for (final name in ['حنفي', 'مالكي', 'شافعي', 'حنبلي']) {
        expect(
          find.text(name),
          findsOneWidget,
          reason: 'Madhhab step must show "$name" under Arabic',
        );
      }
      expect(find.text('Hanafi'), findsNothing);
      expect(find.text('Maliki'), findsNothing);
      expect(find.text('Shafii'), findsNothing);
      expect(find.text('Hanbali'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Directionality &&
              widget.textDirection == TextDirection.rtl,
        ),
        findsWidgets,
        reason: 'the Madhhab step must render RTL when Arabic is active',
      );
    });

    testWidgets(
      'the back-navigation chevron points toward reading-start in both '
      'directions (not a fixed physical left arrow)',
      (tester) async {
        AppLocaleController.instance.setArabic(true);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 3),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
        expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);

        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 3),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      },
    );
  });

  // AUTH-008 items I/L/O: a full forward walk through every step, followed
  // by a full backward walk, for an authenticated user — SignInScreen must
  // never appear at any point in either direction, and no step transition
  // may form a cycle back to an earlier step other than via the real Back
  // button (which is asserted separately not to reach step 3/lower than
  // expected).
  group('AUTH-008 — full state-machine sweep, forward and backward', () {
    testWidgets(
      'walking every step forward from 1 to 9 never shows SignInScreen, '
      'and step order strictly increases (no cycle)',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 1)),
        );
        await tester.pumpAndSettle();

        final visited = <int>[];
        // Step 1: splash.
        expect(find.byType(SignInScreen), findsNothing);
        visited.add(1);
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();

        // Step 2: language.
        expect(find.byType(SignInScreen), findsNothing);
        visited.add(2);
        await tester.tap(find.text('English').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 3: Madhhab.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
        visited.add(3);
        await tester.tap(find.text('Hanbali'));
        await tester.pump();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 4: married.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Are you married?'), findsOneWidget);
        visited.add(4);
        await tester.tap(find.text('No'));
        await tester.pump();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 5: location — skip.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Where are you located?'), findsOneWidget);
        visited.add(5);
        await tester.ensureVisible(find.text('Skip for now'));
        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        // Step 6: last period — "I'm not sure".
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('When did your last period start?'), findsOneWidget);
        visited.add(6);
        await tester.ensureVisible(find.text('I’m not sure'));
        await tester.tap(find.text('I’m not sure'));
        await tester.pumpAndSettle();

        // Step 7: period length.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('How long is your period?'), findsOneWidget);
        visited.add(7);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 8: privacy/anonymous.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Anonymous Mode'), findsOneWidget);
        visited.add(8);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 9: welcome.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('You’re all set!'), findsOneWidget);
        visited.add(9);

        expect(
          visited,
          List<int>.generate(9, (i) => i + 1),
          reason:
              'every step must be visited exactly once, in strictly '
              'increasing order — a repeated or out-of-order entry would '
              'mean a cycle back to an earlier step',
        );
      },
    );

    testWidgets(
      'walking backward from the last question step to step 1 never shows '
      'SignInScreen at any point',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 8)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Anonymous Mode'), findsOneWidget);

        // Step 8 -> 3: repeatedly tap Back, asserting no SignInScreen at
        // any intermediate step (the back button is hidden below step 3
        // and at the final step, so this walks 8 -> 7 -> 6 -> 5 -> 4 -> 3).
        for (var i = 0; i < 5; i++) {
          expect(find.byType(SignInScreen), findsNothing);
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
          expect(find.byType(SignInScreen), findsNothing);
        }

        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);

        // One more Back reaches the language step (2) — the correct floor,
        // never a Sign In screen.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Choose your language'), findsOneWidget);
      },
    );
  });
}
