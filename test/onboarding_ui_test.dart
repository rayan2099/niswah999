import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live Onboarding Contradiction Investigation (Section 13): a fake
/// [GeolocatorPlatform] so the real GPS-success and permission/service
/// failure paths can be exercised without a device or emulator, per the
/// charter's own explicit allowance ("still verify the callback/state
/// machine with a mocked location service").
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
  });

  bool serviceEnabled;
  LocationPermission permission;

  static final _defaultPosition = Position(
    latitude: 24.7136,
    longitude: 46.6753,
    timestamp: DateTime.utc(2026, 1, 1),
    accuracy: 0,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => _defaultPosition;
}

void main() {
  testWidgets(
    'onboarding starts with the branded splash and advances directly to '
    'Madhhab — no redundant language step (AUTH-009)',
    (tester) async {
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onFinished: () {})),
      );

      expect(find.text('Niswah'), findsOneWidget);
      expect(find.text('YOUR CYCLE. YOUR FAITH. YOUR SPACE.'), findsOneWidget);

      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(
        find.text('What is your Fiqh Madhhab?'),
        findsOneWidget,
        reason:
            'AUTH-009: language is already established (pre-auth toggle or '
            'AppLocaleController default) — onboarding must never ask for '
            'it again, so the very next screen after splash is Madhhab.',
      );
      expect(find.text('Choose your language'), findsNothing);
    },
  );

  testWidgets('onboarding asks marital status and stores the answer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    await MaritalStatusController.instance.load();
    await tester.pumpWidget(
      // Start at the madhhab step (2 — AUTH-008 removed the old embedded
      // login step, AUTH-009 removed the redundant language step).
      MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 2)),
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
        MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 3)),
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
      MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 2)),
    );

    await tester.tap(find.text('Hanafi'));
    await tester.pump();

    expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
    expect(MadhhabController.instance.state, MadhhabSelectionState.selected);
  });

  testWidgets(
    'finishing onboarding with a reported last period seeds a real cycle '
    'log instead of discarding the answer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 5)),
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

      // Step 7 is now anonymous-mode only — the fake Face ID/PIN chooser
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

  // AUTH-009: onboarding's own Language step was removed — pre-auth
  // language selection (the toggle already on SignInScreen, or
  // AppLocaleController's own default) is now the sole language moment.
  // These tests preserve the transition-safety coverage the earlier
  // RR-009/AUTH-008 suites established (small viewport, text scale,
  // semantics) against the new splash -> Madhhab transition directly.
  group('splash -> Madhhab step transition (AUTH-009)', () {
    testWidgets(
      'English: splash continues directly to real Madhhab content, no '
      'language screen in between',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {})),
        );
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
        expect(find.text('Choose your language'), findsNothing);
      },
    );

    testWidgets('Arabic: splash continues directly to real Madhhab content in '
        'Arabic, no language screen in between', (tester) async {
      AppLocaleController.instance.setArabic(true);
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onFinished: () {})),
      );
      await tester.tap(find.text('ابدئي'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ما مذهبكِ الفقهي؟'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Directionality &&
              widget.textDirection == TextDirection.rtl,
        ),
        findsWidgets,
        reason:
            'Madhhab must render RTL immediately, not after a second '
            'language choice',
      );
    });

    testWidgets(
      'the Madhhab step (now the first real step) has no back button — '
      'there is nothing before it to go back to, and no path to '
      'accidentally expose auth',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing);
        expect(find.byType(SignInScreen), findsNothing);
      },
    );

    testWidgets(
      'the splash -> Madhhab transition renders with no layout exception '
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

        expect(tester.takeException(), isNull);
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
      },
    );

    testWidgets(
      'the splash -> Madhhab transition renders with no layout exception '
      'at 200% text scale',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: OnboardingScreen(onFinished: () {}),
          ),
        );
        await tester.ensureVisible(find.text('Get Started'));
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
      },
    );

    testWidgets(
      'the splash -> Madhhab transition renders with no layout exception '
      'with semantics enabled',
      (tester) async {
        final handle = tester.ensureSemantics();

        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {})),
        );
        await tester.tap(find.text('Get Started'));
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
  // initialStep. AUTH-008 removed the old embedded login step; AUTH-009
  // removed the redundant language step — the state machine now has 8
  // steps, with no login and no language screen anywhere in it.
  group('all-onboarding-step state machine (no step may render empty)', () {
    final stepContent = <int, String>{
      1: 'Niswah',
      2: 'What is your Fiqh Madhhab?',
      3: 'Are you married?',
      4: 'Where are you located?',
      5: 'When did your last period start?',
      6: 'How long is your period?',
      7: 'Anonymous Mode',
      8: 'You’re all set!',
    };

    for (final entry in stepContent.entries) {
      testWidgets(
        'step ${entry.key} renders its real content, not just the shell',
        (tester) async {
          AppLocaleController.instance.setArabic(false);
          await tester.pumpWidget(
            MaterialApp(
              home: OnboardingScreen(onFinished: () {}, initialStep: entry.key),
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
          expect(
            find.text('Choose your language'),
            findsNothing,
            reason:
                'AUTH-009: no onboarding step may re-ask for language — '
                'AppLocaleController is already the sole authority.',
          );
        },
      );
    }
  });

  // AUTH-007 root cause: `_OnboardingScreenState` used to keep its own
  // `_arabic` field, initialized to a hardcoded `false`, completely
  // disconnected from `AppLocaleController.instance.isArabic` (the real,
  // SharedPreferences-persisted source of truth already used by
  // `SignInScreen`'s own language toggle). Any time a fresh
  // `OnboardingScreen`/`_OnboardingScreenState` was created after the user
  // had already picked Arabic in an earlier attempt (e.g. the app process
  // being recreated while the user leaves to confirm their email), every
  // step driven by that local field silently fell back to English — this
  // is exactly what the owner saw at the Madhhab step. The tests below
  // construct `OnboardingScreen` fresh with `AppLocaleController` already
  // set, exactly reproducing that scenario.
  group('AUTH-007 — Arabic locale propagates to a freshly-created '
      'OnboardingScreen (no fallback to English)', () {
    final arabicStepContent = <int, String>{
      1: 'دورتكِ. دينكِ. مساحتكِ.',
      2: 'ما مذهبكِ الفقهي؟',
      3: 'هل أنتِ متزوجة؟',
      4: 'أين تسكنين؟',
      5: 'متى بدأ آخر حيض لديكِ؟',
      6: 'كم تستمر مدة الحيض؟',
      7: 'الوضع المجهول',
      8: 'كل شيء جاهز!',
    };
    final englishMarkerForStep = <int, String>{
      1: 'YOUR CYCLE. YOUR FAITH. YOUR SPACE.',
      2: 'What is your Fiqh Madhhab?',
      3: 'Are you married?',
      4: 'Where are you located?',
      5: 'When did your last period start?',
      6: 'How long is your period?',
      7: 'Anonymous Mode',
      8: 'You’re all set!',
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
              home: OnboardingScreen(onFinished: () {}, initialStep: entry.key),
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
        MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 2)),
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
      'directions (not a fixed physical left arrow), at the first step '
      'that actually has one (Married, step 3)',
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

  // AUTH-008/AUTH-009 items I/L/O: a full forward walk through every step,
  // followed by a full backward walk, for an authenticated user —
  // SignInScreen and the old Language step must never appear at any
  // point, and no step transition may form a cycle back to an earlier
  // step other than via the real Back button.
  group('AUTH-008/AUTH-009 — full state-machine sweep, forward and '
      'backward', () {
    testWidgets(
      'walking every step forward from 1 to 8 never shows SignInScreen or '
      'a language screen, and step order strictly increases (no cycle)',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 1),
          ),
        );
        await tester.pumpAndSettle();

        final visited = <int>[];
        // Step 1: splash.
        expect(find.byType(SignInScreen), findsNothing);
        visited.add(1);
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();

        // Step 2: Madhhab (directly — no language step in between).
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Choose your language'), findsNothing);
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
        visited.add(2);
        await tester.tap(find.text('Hanbali'));
        await tester.pump();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 3: married.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Are you married?'), findsOneWidget);
        visited.add(3);
        await tester.tap(find.text('No'));
        await tester.pump();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 4: location — skip.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Where are you located?'), findsOneWidget);
        visited.add(4);
        await tester.ensureVisible(find.text('Skip for now'));
        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        // Step 5: last period — "I'm not sure".
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('When did your last period start?'), findsOneWidget);
        visited.add(5);
        await tester.ensureVisible(find.text('I’m not sure'));
        await tester.tap(find.text('I’m not sure'));
        await tester.pumpAndSettle();

        // Step 6: period length.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('How long is your period?'), findsOneWidget);
        visited.add(6);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 7: privacy/anonymous.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Anonymous Mode'), findsOneWidget);
        visited.add(7);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 8: welcome.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('You’re all set!'), findsOneWidget);
        visited.add(8);

        expect(
          visited,
          List<int>.generate(8, (i) => i + 1),
          reason:
              'every step must be visited exactly once, in strictly '
              'increasing order — a repeated or out-of-order entry would '
              'mean a cycle back to an earlier step',
        );
      },
    );

    testWidgets('walking backward from the last question step all the way to '
        'Madhhab never shows SignInScreen or a language screen, and Madhhab '
        'itself has no further Back', (tester) async {
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 7)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Anonymous Mode'), findsOneWidget);

      // Step 7 -> 2: repeatedly tap Back (walks 7 -> 6 -> 5 -> 4 -> 3),
      // asserting no SignInScreen and no language screen at any point.
      for (var i = 0; i < 4; i++) {
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Choose your language'), findsNothing);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.text('Choose your language'), findsNothing);
      }

      expect(find.text('Are you married?'), findsOneWidget);

      // One more Back reaches Madhhab (step 2) — the correct floor.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);

      // Madhhab itself has no Back button at all — nothing before it to
      // return to, and no way to accidentally expose auth.
      expect(find.byTooltip('Back'), findsNothing);
    });
  });

  group('Fiqh Remediation Wave 1 — Madhhab step 5-option grid and unknown-Madhhab flow (Sections G/H/I/J/R)', () {
    testWidgets(
      'English: all 5 choices are visible, including "I don\'t know my Madhhab"',
      (tester) async {
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        for (final label in [
          'Hanafi',
          'Maliki',
          "Shafi'i",
          'Hanbali',
          "I don't know my Madhhab",
        ]) {
          expect(
            find.text(label),
            findsOneWidget,
            reason: '"$label" must be visible',
          );
        }
      },
    );

    testWidgets(
      'Arabic: all 5 choices are visible with the correct RTL labels',
      (tester) async {
        AppLocaleController.instance.setArabic(true);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        for (final label in [
          'حنفي',
          'مالكي',
          'شافعي',
          'حنبلي',
          'لا أعرف مذهبي',
        ]) {
          expect(
            find.text(label),
            findsOneWidget,
            reason: '"$label" must be visible',
          );
        }
        AppLocaleController.instance.setArabic(false);
      },
    );

    testWidgets(
      'tapping "I don\'t know my Madhhab" shows the calm explanation, not an immediate selection',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know my Madhhab"));
        await tester.tap(find.text("I don't know my Madhhab"));
        await tester.pumpAndSettle();

        expect(find.text('No problem'), findsOneWidget);
        expect(find.text('What is your Fiqh Madhhab?'), findsNothing);
        expect(
          MadhhabController.instance.state,
          isNot(MadhhabSelectionState.selected),
          reason: 'tapping the option itself must never persist anything',
        );
      },
    );

    testWidgets(
      '"I\'ll decide later" persists UNKNOWN (never a guessed madhhab) and advances',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know my Madhhab"));
        await tester.tap(find.text("I don't know my Madhhab"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text("I'll decide later"));
        await tester.tap(find.text("I'll decide later"));
        await tester.pumpAndSettle();

        expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
        expect(MadhhabController.instance.selectedOrNull, isNull);
        expect(find.text('Are you married?'), findsOneWidget);
      },
    );

    testWidgets(
      '"Back to choices" from the explanation returns to the 5-option grid',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know my Madhhab"));
        await tester.tap(find.text("I don't know my Madhhab"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Back to choices'));
        await tester.tap(find.text('Back to choices'));
        await tester.pumpAndSettle();

        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
      },
    );

    testWidgets(
      '"Help me choose" -> a recognized country -> confirming the suggestion persists SELECTED, never silently',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know my Madhhab"));
        await tester.tap(find.text("I don't know my Madhhab"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Help me choose'));
        await tester.tap(find.text('Help me choose'));
        await tester.pumpAndSettle();

        expect(find.text('Which country do you live in?'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Saudi Arabia');
        // Required frame: onChanged's setState (which flips the Continue
        // button from disabled to enabled) has not been processed until
        // this pump — without it, ensureVisible/tap below would act on
        // the still-disabled button from the pre-input frame.
        await tester.pump();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.text('A suggestion for you'), findsOneWidget);
        expect(
          MadhhabController.instance.state,
          isNot(MadhhabSelectionState.selected),
          reason:
              'a displayed suggestion must never itself persist a selection',
        );

        await tester.ensureVisible(
          find.textContaining('Hanbali is my Madhhab'),
        );
        await tester.tap(find.textContaining('Hanbali is my Madhhab'));
        await tester.pumpAndSettle();

        expect(
          MadhhabController.instance.state,
          MadhhabSelectionState.selected,
        );
        expect(MadhhabController.instance.selectedOrNull, Madhhab.hanbali);
        expect(find.text('Are you married?'), findsOneWidget);
      },
    );

    testWidgets(
      '"Help me choose" -> an unrecognized country -> "I\'ll decide later" persists UNKNOWN, not a guess',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know my Madhhab"));
        await tester.tap(find.text("I don't know my Madhhab"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Help me choose'));
        await tester.tap(find.text('Help me choose'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Nowhereland');
        await tester.pump();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(
          find.text("We don't have a suggestion for that yet"),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text("I'll decide later"));
        await tester.tap(find.text("I'll decide later"));
        await tester.pumpAndSettle();

        expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
        expect(find.text('Are you married?'), findsOneWidget);
      },
    );

    testWidgets(
      '"None of these" on a resolved suggestion persists UNKNOWN, not the suggested madhhab',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know my Madhhab"));
        await tester.tap(find.text("I don't know my Madhhab"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Help me choose'));
        await tester.tap(find.text('Help me choose'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Turkey');
        await tester.pump();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.text('A suggestion for you'), findsOneWidget);
        await tester.ensureVisible(find.textContaining("None of these"));
        await tester.tap(find.textContaining("None of these"));
        await tester.pumpAndSettle();

        expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
        expect(
          MadhhabController.instance.selectedOrNull,
          isNot(Madhhab.hanafi),
          reason: 'Turkey suggests Hanafi — declining it must never persist it anyway',
        );
      },
    );
  });

  group('Live Onboarding Contradiction Investigation — Location UX state '
      'machine (Sections 6/9/10/11/13)', () {
    late GeolocatorPlatform originalPlatform;

    setUp(() {
      originalPlatform = GeolocatorPlatform.instance;
      SharedPreferences.setMockInitialValues({});
      AppLocaleController.instance.setArabic(false);
    });

    tearDown(() {
      GeolocatorPlatform.instance = originalPlatform;
    });

    testWidgets(
      'idle: arriving at the Location step shows no confirmation banner',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 4),
          ),
        );

        expect(find.text('Where are you located?'), findsOneWidget);
        expect(find.textContaining('Location confirmed'), findsNothing);
        expect(find.text('Detecting your location…'), findsNothing);
      },
    );

    testWidgets(
      '"Use current location" success: shows detecting, then a visible '
      'confirmation, before advancing — never a silent skip',
      (tester) async {
        final completer = Completer<Position>();
        GeolocatorPlatform.instance = _HangingGeolocatorPlatform(completer);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 4),
          ),
        );

        await tester.tap(find.text('Use current location'));
        await tester.pump();
        expect(
          find.text('Detecting your location…'),
          findsOneWidget,
          reason: 'a slow GPS fix must not look like a dead tap',
        );
        expect(find.text('When did your last period start?'), findsNothing);

        completer.complete(_FakeGeolocatorPlatform._defaultPosition);
        await tester.pump();
        expect(
          find.text('Location confirmed: Current location'),
          findsOneWidget,
          reason:
              'success must be visibly confirmed, not just silently '
              'advance to the next step',
        );
        expect(find.text('When did your last period start?'), findsNothing);

        await tester.pump(const Duration(milliseconds: 700));
        expect(
          find.text('When did your last period start?'),
          findsOneWidget,
          reason: 'a confirmed location must still advance onward',
        );
      },
    );

    testWidgets('"Use current location" — location services disabled shows a '
        'real, visible error, not a silent no-op', (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        serviceEnabled: false,
      );
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 4)),
      );

      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();

      expect(
        find.text('Turn on location services to use your current location.'),
        findsWidgets,
      );
      expect(find.text('When did your last period start?'), findsNothing);
    });

    testWidgets(
      '"Use current location" — permission denied shows a real, visible '
      'error, not a silent no-op',
      (tester) async {
        GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
          permission: LocationPermission.denied,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 4),
          ),
        );

        await tester.tap(find.text('Use current location'));
        await tester.pumpAndSettle();

        expect(
          find.text('Location permission denied — pick a city instead.'),
          findsWidgets,
        );
        expect(find.text('When did your last period start?'), findsNothing);
      },
    );

    testWidgets('tapping a popular-city chip persists it and shows a visible '
        'confirmation before advancing — no city button is decorative-only', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 4)),
      );

      await tester.tap(find.text('Riyadh'));
      await tester.pump();
      expect(find.text('Location confirmed: Riyadh'), findsOneWidget);
      expect(
        PrayerLocationController.instance.selectedOrNull,
        PrayerLocationController.presets.firstWhere((p) => p.label == 'Riyadh'),
        reason:
            'the tapped city must actually be persisted, not just '
            'displayed',
      );

      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('When did your last period start?'), findsOneWidget);
    });

    testWidgets(
      'Arabic: a popular-city chip shows its Arabic confirmation label',
      (tester) async {
        AppLocaleController.instance.setArabic(true);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 4),
          ),
        );

        await tester.tap(find.text('دبي'));
        await tester.pump();
        expect(find.text('تم تحديد موقعكِ: دبي'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 700));
        AppLocaleController.instance.setArabic(false);
      },
    );

    testWidgets(
      'Skip is the only deliberate skip path: it advances immediately '
      'and never fakes a detected/selected location',
      (tester) async {
        await PrayerLocationController.instance.select(
          PrayerLocationController.presets.firstWhere(
            (p) => p.label == 'Jeddah',
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 4),
          ),
        );

        expect(find.textContaining('Location confirmed'), findsNothing);
        await tester.tap(find.text('Skip for now'));
        await tester.pump();

        expect(find.text('When did your last period start?'), findsOneWidget);
        expect(
          PrayerLocationController.instance.selectedOrNull?.label,
          'Jeddah',
          reason: 'Skip must never overwrite or fake a location selection',
        );
      },
    );

    testWidgets(
      'while detecting, city chips and Skip are disabled — no competing '
      'action can race the in-flight detection',
      (tester) async {
        final completer = Completer<Position>();
        GeolocatorPlatform.instance = _HangingGeolocatorPlatform(completer);

        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 4),
          ),
        );

        await tester.tap(find.text('Use current location'));
        await tester.pump();
        expect(find.text('Detecting your location…'), findsOneWidget);

        await tester.tap(find.text('Skip for now'));
        await tester.pump();
        expect(
          find.text('Where are you located?'),
          findsOneWidget,
          reason: 'Skip must be inert while a detection is in flight',
        );

        completer.complete(_FakeGeolocatorPlatform._defaultPosition);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
      },
    );
  });
}

/// A [GeolocatorPlatform] whose [getCurrentPosition] stays pending until the
/// test explicitly completes it — used to prove the Location step's controls
/// are truly disabled during an in-flight detection, not just slow.
class _HangingGeolocatorPlatform extends GeolocatorPlatform {
  _HangingGeolocatorPlatform(this._completer);
  final Completer<Position> _completer;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      _completer.future;
}
