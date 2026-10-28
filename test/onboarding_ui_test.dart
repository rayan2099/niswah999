import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart' show Placemark;
import 'package:geolocator/geolocator.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/madhhab_resolution/presentation/widgets/madhhab_resolution_flow.dart';
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

  group('Menstrual Data Integrity charter — truthful Last-Period step '
      '(Commit C)', () {
    testWidgets(
      'reporting a real last-period start and "still happening" never '
      'fabricates a single cycle_entries row — the exact behavior the '
      'charter\'s central doctrine forbids',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 5),
          ),
        );

        expect(find.text('When did your last period start?'), findsOneWidget);
        await tester.tap(find.text('Select the date'));
        await tester.pumpAndSettle();
        // The Material date picker's initial date is already "today" —
        // confirming it as-is is enough to select a real calendar date.
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.text('Is it still happening?'), findsOneWidget);
        await tester.tap(find.text('Yes, still going'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Would you like to add some information to improve predictions?',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Skip for now'));
        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        expect(find.text('Anonymous Mode'), findsOneWidget);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.text('Start tracking'), findsOneWidget);
        await tester.ensureVisible(find.text('Start tracking'));
        await tester.tap(find.text('Start tracking'));
        // Not pumpAndSettle: completion now shows a perpetually-animating
        // busy indicator while in flight (double-tap guard, hostile
        // self-review fix), which never itself "settles"; `onFinished` is
        // a no-op in this test (nothing unmounts the screen), so a couple
        // of bounded pumps — enough for the fast, session-less completion
        // path to resolve — is correct here, not a full settle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // The old defect: onboarding used to write one cycle_entries row
        // per day of an assumed period length, none of which were ever
        // actually reported. It must now write nothing at all through
        // this local-fallback path (no Supabase session in this test), and
        // in production a real session writes only to bleeding_episodes /
        // cycle_baselines instead — never a fabricated flow-level log.
        final logs = await CycleTrackingRepositoryImpl().getCycleLogs();
        expect(
          logs,
          isEmpty,
          reason:
              'no cycle_entries row may ever be fabricated from onboarding '
              'answers again',
        );
      },
    );

    testWidgets(
      'double-tapping "Get Started" completes onboarding exactly once — '
      'a rapid second tap while completion is already in flight must be a '
      'no-op, not a second write',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        AppLocaleController.instance.setArabic(false);
        var finishedCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(
              onFinished: () => finishedCount++,
              initialStep: 8,
            ),
          ),
        );

        expect(find.text('Start tracking'), findsOneWidget);
        await tester.ensureVisible(find.text('Start tracking'));
        // Both taps land before any pump processes the first one's
        // setState — the closest a widget test can get to a genuine
        // simultaneous double-tap.
        await tester.tap(find.text('Start tracking'));
        await tester.tap(find.text('Start tracking'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          finishedCount,
          1,
          reason:
              'a rapid double-tap must complete onboarding exactly once, '
              'never twice',
        );
      },
    );

    testWidgets(
      'the still-happening question offers Yes / No / not sure, and No '
      'asks for a real end date rather than assuming one',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 5),
          ),
        );

        await tester.tap(find.text('Select the date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.text('Is it still happening?'), findsOneWidget);
        await tester.tap(find.text('No, it has stopped'));
        await tester.pumpAndSettle();

        expect(find.text('When did it stop?'), findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);
        // Continue must start disabled — no end date has been chosen yet,
        // so nothing may be assumed.
        final continueButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Continue'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(continueButton.onPressed, isNull);
      },
    );

    testWidgets(
      'tapping "I\'m not sure" on the start date skips straight past the '
      'still-happening question — no episode is implied from an unknown '
      'start',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 5),
          ),
        );

        await tester.ensureVisible(find.text('I’m not sure'));
        await tester.tap(find.text('I’m not sure'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Would you like to add some information to improve predictions?',
          ),
          findsOneWidget,
        );
      },
    );
  });

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
  // removed the redundant language step; the onboarding redesign folded
  // the two estimate questions behind one optional "predictions" gate at
  // step 6 (Part 3) — the state machine now has 8 steps, with no login
  // and no language screen anywhere in it.
  group('all-onboarding-step state machine (no step may render empty)', () {
    final stepContent = <int, String>{
      1: 'Niswah',
      2: 'What is your Fiqh Madhhab?',
      3: 'Are you married?',
      4: 'Where are you located?',
      5: 'When did your last period start?',
      6: 'Would you like to add some information to improve predictions?',
      7: 'Anonymous Mode',
      8: 'You’re ready to get started',
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
      6: 'هل ترغبين في إضافة معلومات لتحسين التوقعات؟',
      7: 'الوضع المجهول',
      8: 'أصبحتِ جاهزة للبدء',
    };
    final englishMarkerForStep = <int, String>{
      1: 'YOUR CYCLE. YOUR FAITH. YOUR SPACE.',
      2: 'What is your Fiqh Madhhab?',
      3: 'Are you married?',
      4: 'Where are you located?',
      5: 'When did your last period start?',
      6: 'Would you like to add some information to improve predictions?',
      7: 'Anonymous Mode',
      8: 'You’re ready to get started',
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

        // Step 6: the optional predictions gate (Part 3) — decline. Both
        // estimate questions share this same step index when accepted, so
        // declining or walking through them never changes which literal
        // step number is visited here.
        expect(find.byType(SignInScreen), findsNothing);
        expect(
          find.text(
            'Would you like to add some information to improve predictions?',
          ),
          findsOneWidget,
        );
        visited.add(6);
        await tester.ensureVisible(find.text('Skip for now'));
        await tester.tap(find.text('Skip for now'));
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
        expect(find.text('You’re ready to get started'), findsOneWidget);
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
          "I don't know",
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

        for (final label in ['حنفي', 'مالكي', 'شافعي', 'حنبلي', 'لا أعرف']) {
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

        await tester.ensureVisible(find.text("I don't know"));
        await tester.tap(find.text("I don't know"));
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

        await tester.ensureVisible(find.text("I don't know"));
        await tester.tap(find.text("I don't know"));
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
      // Manual QA fix (2026-10-11), Part 1A root cause: Continue used to
      // gate on `MadhhabController.isSelected`, which is deliberately
      // `false` for MadhhabSelectionState.unknown (that narrowness is
      // correct for *other* call sites that need a real madhhab to apply
      // Fiqh rules with). A returning visitor who already chose "I don't
      // know" and navigated back to this grid saw her choice correctly
      // highlighted but Continue stuck disabled, as if "I don't know"
      // weren't a complete answer.
      'returning to the Madhhab grid after already choosing "I don\'t '
      'know" shows that tile active AND Continue clearly enabled — "I '
      'don\'t know" is a complete, valid answer, not an unanswered state',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know"));
        await tester.tap(find.text("I don't know"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text("I'll decide later"));
        await tester.tap(find.text("I'll decide later"));
        await tester.pumpAndSettle();
        expect(find.text('Are you married?'), findsOneWidget);

        // Navigate back to the Madhhab grid.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
        expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);

        final continueButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Continue'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(
          continueButton.onPressed,
          isNotNull,
          reason:
              '"I don\'t know" must be treated as a complete answer — '
              'Continue must not be stuck disabled',
        );
      },
    );

    testWidgets('picking a real Madhhab also clearly enables Continue', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await MadhhabController.instance.load();
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 2)),
      );

      var continueButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(continueButton.onPressed, isNull);

      await tester.tap(find.text('Hanafi'));
      await tester.pump();

      continueButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(continueButton.onPressed, isNotNull);
    });

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

        await tester.ensureVisible(find.text("I don't know"));
        await tester.tap(find.text("I don't know"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Back to choices'));
        await tester.tap(find.text('Back to choices'));
        await tester.pumpAndSettle();

        expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
      },
    );

    testWidgets(
      // Adversarial review, 2026-10-07: Saudi Arabia used to produce a
      // confident Hanbali suggestion here. It is now gated behind
      // reviewer_status == 'APPROVED' (no entry in the dataset has
      // this), so even a dataset-covered country now lands on the same
      // "we don't have a suggestion" state as an unmapped one — applied
      // uniformly when nothing is verified. Onboarding never gets stuck
      // either way: declining a suggestion (or an unreviewed match)
      // persists an honest UNKNOWN and advances.
      //
      // Knowledge-Base Source-Verification wave (2026-10-14): Saudi
      // Arabia's entry is now genuinely SOURCE_VERIFIED (a real,
      // directly-fetched US State Dept report), so this test's premise
      // changed — it now covers "a country WITH a verified suggestion ->
      // she declines it anyway -> UNKNOWN persists and onboarding still
      // advances," not "no suggestion is shown at all." The no-dead-end
      // guarantee itself is unchanged.
      '"Help me choose" -> a country with a SOURCE_VERIFIED suggestion '
      '-> she declines it anyway -> "I still don\'t know" persists '
      'UNKNOWN and advances, never a guess',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
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
        await tester.tap(find.text('Select country'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Saudi Arabia');
        await tester.pump();
        // Part 10/4: a searchable ISO modal, not free text — she must tap
        // the matching country, which closes the sheet and flips Continue
        // from disabled to enabled.
        await tester.tap(find.widgetWithText(ListTile, 'Saudi Arabia'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Saudi Arabia's entry is SOURCE_VERIFIED, so the real suggestion
        // step is reached, not the manual-selection fallback.
        expect(
          find.text(
            'Based on the country where you grew up, Hanbali may be '
            'the closest fit.',
          ),
          findsOneWidget,
          reason: 'a verified entry must reach the real suggestion step',
        );
        expect(find.text('Choose the Madhhab you follow'), findsNothing);
        expect(
          MadhhabController.instance.state,
          isNot(MadhhabSelectionState.selected),
          reason:
              'a suggestion is shown, but nothing is persisted until '
              'she explicitly confirms it',
        );

        await tester.ensureVisible(find.text("I still don't know"));
        await tester.tap(find.text("I still don't know"));
        await tester.pumpAndSettle();

        expect(
          MadhhabController.instance.state,
          MadhhabSelectionState.unknown,
          reason:
              'never silently guessed — declining a real suggestion '
              'degrades to exactly the same explicit-UNKNOWN outcome as '
              'no match at all, and onboarding still advances, never stuck',
        );
        expect(find.text('Are you married?'), findsOneWidget);
      },
    );

    testWidgets(
      // Resolution-flow unification defect fix (2026-10-14): the
      // post-onboarding resolution screen now routes its final selection
      // through `setMadhhabWithConfirmation`, which can show a light
      // "first interpretation" notice for an unknown -> selected pick.
      // Onboarding's OWN use of the shared `MadhhabResolutionFlow` must
      // keep calling `MadhhabController` directly and never gain that
      // notice — there is no prior Fiqh interpretation to reinterpret
      // this early (Last Period is a later step), so showing it here
      // would be a false alarm, not a safeguard.
      'accepting a real geographic suggestion during onboarding persists '
      'it immediately with no light notice or warning dialog -- there is '
      'no prior Fiqh interpretation to reinterpret this early',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know"));
        await tester.tap(find.text("I don't know"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Help me choose'));
        await tester.tap(find.text('Help me choose'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Select country'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Saudi Arabia');
        await tester.pump();
        await tester.tap(find.widgetWithText(ListTile, 'Saudi Arabia'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Use Hanbali'));
        await tester.tap(find.text('Use Hanbali'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Niswah will now interpret your previous records according '
            'to the Madhhab you selected. Your original entries will '
            'not be changed.',
          ),
          findsNothing,
          reason:
              'onboarding runs before any bleeding history can exist '
              '-- the light first-interpretation notice would be a false '
              'alarm here',
        );
        expect(find.text('Confirm change'), findsNothing);
        expect(
          MadhhabController.instance.state,
          MadhhabSelectionState.selected,
        );
        expect(MadhhabController.instance.selectedOrNull, Madhhab.hanbali);
        expect(
          find.text('Are you married?'),
          findsOneWidget,
          reason: 'persisted immediately and advanced -- nothing blocked it',
        );
      },
    );

    testWidgets(
      // Madhhab unification (2026-10-12): onboarding's "Help me choose" '
      // sub-step must literally render the same MadhhabResolutionFlow
      // widget the in-app Profile/Settings change screen renders — not
      // a lookalike copy. This is the structural half of acceptance
      // item 1 ("onboarding uses shared resolution flow"); the
      // behavioral half is covered by the Saudi Arabia/Afghanistan/
      // Egypt/Japan tests above and below.
      '"Help me choose" renders the shared MadhhabResolutionFlow widget, '
      'not a separate onboarding-only implementation',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know"));
        await tester.tap(find.text("I don't know"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Help me choose'));
        await tester.tap(find.text('Help me choose'));
        await tester.pumpAndSettle();

        expect(
          find.byType(MadhhabResolutionFlow),
          findsOneWidget,
          reason:
              'onboarding must delegate to the shared MadhhabResolutionFlow '
              'component rather than maintaining its own duplicate '
              'inference/UX path',
        );
      },
    );

    testWidgets(
      // Onboarding fixes wave (2026-10-11), Part 4: the previous free-text
      // country field let her type a fictional/unrecognized country,
      // which always degraded to "no suggestion" anyway. The searchable
      // ISO modal replacing it eliminates that dead-end structurally —
      // there is no way to submit something unresolvable, since Continue
      // only enables once a real country from the list has been tapped.
      'searching for a country not in the list shows no results and '
      'leaves Continue disabled — dismissing the sheet and Back both '
      'escape cleanly',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know"));
        await tester.tap(find.text("I don't know"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Help me choose'));
        await tester.tap(find.text('Help me choose'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select country'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Nowhereland');
        await tester.pump();

        expect(find.byType(ListTile), findsNothing);
        expect(find.text('No countries found'), findsOneWidget);

        // Dismiss the sheet (tap the scrim, well outside its bounds) —
        // no selection was made, so the field stays unset.
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        final continueButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Continue'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(
          continueButton.onPressed,
          isNull,
          reason: 'no selection has been made yet — nothing to submit',
        );

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text('No problem'), findsOneWidget);
      },
    );

    testWidgets(
      // Adversarial review, 2026-10-07; onboarding fixes wave, Part 2;
      // re-verified after the Knowledge-Base Source-Verification wave
      // (2026-10-14): Tunisia is in the draft mapping (Maliki) but real
      // research this pass found a widely-repeated secondary citation
      // chain was actually inaccurate and no qualifying top-tier source —
      // it stays UNVERIFIED (see its review_notes in
      // geographic_madhhab_mapping.json), so this still lands directly on
      // manual selection rather than any kind of suggestion screen.
      // Declining (choosing "I don't know" from that manual grid) must
      // never persist Tunisia's draft-mapped Maliki.
      'declining on a country the draft mapping covers but stays '
      'UNVERIFIED (Tunisia) never persists that country\'s madhhab, even '
      'though no suggestion is actually shown',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );

        await tester.ensureVisible(find.text("I don't know"));
        await tester.tap(find.text("I don't know"));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Help me choose'));
        await tester.tap(find.text('Help me choose'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select country'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Tunisia');
        await tester.pump();
        await tester.tap(find.widgetWithText(ListTile, 'Tunisia'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(
          find.text('Choose the Madhhab you follow'),
          findsOneWidget,
          reason:
              'Tunisia is in the draft mapping (Maliki) but UNVERIFIED '
              '— gated exactly like any unmapped country, landing on '
              'manual selection rather than any suggestion/error screen',
        );
        await tester.ensureVisible(find.text("I don't know"));
        await tester.tap(find.text("I don't know"));
        await tester.pumpAndSettle();

        expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
        expect(
          MadhhabController.instance.selectedOrNull,
          isNot(Madhhab.maliki),
          reason:
              'Tunisia\'s draft mapping is Maliki — confirming it was '
              'never silently adopted just because the country happened '
              'to be in the dataset',
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
        final originalLookup = PrayerLocationController.placemarkLookup;
        final originalZone = PrayerLocationController.deviceTimezone;
        addTearDown(() {
          PrayerLocationController.placemarkLookup = originalLookup;
          PrayerLocationController.deviceTimezone = originalZone;
        });
        PrayerLocationController.placemarkLookup = (lat, lng, locale) async => [
          Placemark(
            locality: locale.languageCode == 'ar' ? 'الخبر' : 'Al Khobar',
          ),
        ];
        PrayerLocationController.deviceTimezone = () async => 'Asia/Riyadh';
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
          find.text('Location confirmed: Al Khobar'),
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
