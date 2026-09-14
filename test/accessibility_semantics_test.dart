import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/widgets/floating_nav_bar.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import 'package:niswah/features/auth/presentation/screens/profile_screen.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:niswah/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:niswah/features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart';
import 'package:niswah/features/legal/presentation/screens/data_export_screen.dart';
import 'package:niswah/features/legal/presentation/screens/privacy_policy_screen.dart';
import 'package:niswah/features/prayer_tracking/presentation/screens/prayer_tracking_screen.dart';

/// Accessibility & UX remediation wave — Phase L required test suite.
/// Uses Flutter's real semantics tree (`tester.ensureSemantics()` +
/// `tester.getSemantics()`), not just widget presence, so these assert what
/// a screen reader would actually receive — stronger evidence than static
/// code reading, though still not a substitute for live device/AT testing
/// (AU-009, still open — see the wave report).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
  });

  group('1. Signup form semantics', () {
    testWidgets('email and password fields expose accessible labels', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
      await tester.pumpAndSettle();

      final checkbox = find.byKey(const Key('consent_checkbox'));
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Email'),
        findsWidgets,
        reason: 'the email field must expose "Email" as its accessible name',
      );
      expect(
        find.bySemanticsLabel('Password'),
        findsWidgets,
        reason:
            'the password field must expose "Password" as its accessible name',
      );

      handle.dispose();
    });
  });

  group('2. Consent checkbox semantics', () {
    testWidgets('consent checkbox is exposed as a checkable control', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
      await tester.pumpAndSettle();

      final checkboxKey = find.byKey(const Key('consent_checkbox'));
      await tester.ensureVisible(checkboxKey);
      await tester.pumpAndSettle();

      // The Key lives on the enclosing InkWell (a distinct, merely-
      // focusable semantics node); the checkbox's own checked-state lives
      // on the dedicated Semantics(checked:) node this wave added around
      // just the visual checkbox — found by its accessible label, verified
      // against a live semantics-tree dump to actually be its own isolated
      // node, not merged with the adjacent Privacy Policy/Terms links.
      final checkbox = find.bySemanticsLabel(
        'Agree to the Privacy Policy and Terms of Use',
      );
      expect(checkbox, findsOneWidget);
      final data = tester.getSemantics(checkbox);
      expect(
        data.hasFlag(SemanticsFlag.hasCheckedState),
        isTrue,
        reason: 'a screen reader must announce this as a checkbox control',
      );
      expect(
        data.hasFlag(SemanticsFlag.isChecked),
        isFalse,
        reason: 'must start unchecked, matching its actual default state',
      );

      handle.dispose();
    });
  });

  group('3. Password visibility control', () {
    testWidgets(
      'the show/hide password toggle has a state-reflecting accessible name',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
        await tester.pumpAndSettle();

        final checkbox = find.byKey(const Key('consent_checkbox'));
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Email'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Email'));
        await tester.pumpAndSettle();

        // Password hidden by default — the control's name must say what
        // tapping it does next ("Show password"), not just describe the
        // icon shape. IconButton's tooltip: populates the semantics
        // `tooltip` field, not `label` — `find.byTooltip` is the matching
        // finder (verified against a live semantics-tree dump).
        expect(find.byTooltip('Show password'), findsOneWidget);

        final toggle = find.byIcon(Icons.visibility_off_outlined);
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(
          find.byTooltip('Hide password'),
          findsOneWidget,
          reason: 'the accessible name must update once the state flips',
        );

        handle.dispose();
      },
    );
  });

  group('4. Account-deletion dialog', () {
    testWidgets(
      'Cancel and Delete actions are both real, named, actionable controls',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
        await tester.pumpAndSettle();

        // The buttons row is well down a long CustomScrollView — scroll
        // until it's actually built and visible rather than assuming a
        // fixed pump settles far enough.
        await tester.scrollUntilVisible(
          find.text('Delete Account'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete Account'));
        await tester.pumpAndSettle();

        expect(
          find.text('Delete your account?'),
          findsOneWidget,
          reason: 'the real confirmation dialog must actually open',
        );

        final cancel = find.widgetWithText(TextButton, 'Cancel');
        final delete = find.widgetWithText(TextButton, 'Delete');
        expect(cancel, findsOneWidget);
        expect(delete, findsOneWidget);

        final cancelData = tester.getSemantics(cancel);
        final deleteData = tester.getSemantics(delete);
        expect(cancelData.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(deleteData.hasFlag(SemanticsFlag.isButton), isTrue);

        handle.dispose();
      },
    );
  });

  group('5. Cycle-tracking: log-entry sheet semantics', () {
    testWidgets(
      'the close control and a symptom-severity chip both have accessible '
      'names, and the severity chip announces its current level',
      (tester) async {
        final handle = tester.ensureSemantics();
        final viewModel = CycleTrackingViewModel(
          repository: CycleTrackingRepositoryImpl(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () =>
                      showCycleLogSheet(context, viewModel: viewModel),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel('Close'),
          findsOneWidget,
          reason: 'the sheet close control must have an accessible name',
        );

        // The symptoms card is further down the sheet's ListView, outside
        // the default test viewport — scroll to it rather than assuming a
        // settle brings it into the built subtree.
        await tester.scrollUntilVisible(
          find.text('Cramps'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        final crampsChip = find.text('Cramps');
        expect(crampsChip, findsOneWidget);
        var data = tester.getSemantics(crampsChip);
        expect(
          data.label,
          'Cramps',
          reason: 'unselected: no severity is announced',
        );

        await tester.tap(crampsChip);
        await tester.pumpAndSettle();
        data = tester.getSemantics(crampsChip);
        expect(
          data.label,
          contains('mild'),
          reason: 'first tap must announce the mild severity level',
        );

        handle.dispose();
      },
    );

    testWidgets(
      'symptom-severity chip touch target measures at least 44dp tall '
      '(AU-004, AU-009 Phase B — previously claimed from code reading only, '
      'now actually measured against the real rendered widget tree)',
      (tester) async {
        final viewModel = CycleTrackingViewModel(
          repository: CycleTrackingRepositoryImpl(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () =>
                      showCycleLogSheet(context, viewModel: viewModel),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Cramps'),
          200,
          scrollable: find.byType(Scrollable).first,
        );

        final chipInkWell = find.ancestor(
          of: find.text('Cramps'),
          matching: find.byType(InkWell),
        );
        expect(chipInkWell, findsOneWidget);

        final size = tester.getSize(chipInkWell);
        expect(
          size.height,
          greaterThanOrEqualTo(44.0),
          reason:
              'the symptom chip is the actual tappable region a screen-reader '
              'or low-motor-control user activates — its real rendered height '
              'must clear the 44dp minimum, not merely the Container\'s '
              'declared minHeight constraint in source',
        );
      },
    );
  });

  group('6. Prayer-tracking screen semantics', () {
    testWidgets('renders with a real accessible app title', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: PrayerTrackingScreen()));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Prayer Times'), findsOneWidget);

      handle.dispose();
    });
  });

  group('7. Dr. Niswah chat header controls', () {
    testWidgets('close control has an accessible name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: DrNiswahChatScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // IconButton's tooltip: populates the semantics `tooltip` field —
      // `find.byTooltip` is the correct finder (see test 3's note).
      expect(find.byTooltip('Close'), findsOneWidget);

      handle.dispose();
    });
  });

  group('8. Privacy policy entry point', () {
    testWidgets('privacy policy screen renders real, non-empty content', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Privacy'), findsWidgets);

      handle.dispose();
    });
  });

  group('9. Data export control', () {
    testWidgets(
      'without a session, the screen still gives an accessible explanation '
      'rather than an empty or unlabeled state',
      (tester) async {
        // DataExportScreen requires an authenticated user to fetch and
        // export anything — no real Supabase session exists in this test
        // environment, so it correctly shows an explanatory message rather
        // than the export button. That message itself must be a real,
        // accessible piece of text, not a silent blank screen.
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(const MaterialApp(home: DataExportScreen()));
        await tester.pumpAndSettle();

        final message = find.bySemanticsLabel(
          'You must be signed in to export your data.',
        );
        expect(message, findsOneWidget);

        handle.dispose();
      },
    );

    // Note: DataExportScreen's own loading frame can't be captured directly
    // in this test environment — without a real Supabase session,
    // _load()'s client==null branch runs synchronously with no `await`
    // reached first, so `_loading` flips to false before the very first
    // frame ever paints (confirmed by direct code read of
    // data_export_screen.dart's _load()). The label/localization/
    // disappearance contract that file's real spinner relies on is instead
    // verified below against a minimal harness reproducing the exact same
    // pattern applied to every remediated file this wave (a boolean-gated
    // CircularProgressIndicator with an AppLocaleController-backed
    // semanticsLabel).
    testWidgets(
      'AU-014 contract: a boolean-gated loading spinner exposes a real '
      'accessible label in English, switches to Arabic when the app locale '
      'is Arabic, and the label disappears the instant loading finishes — '
      'the exact pattern applied to every remediated file in this wave',
      (tester) async {
        final handle = tester.ensureSemantics();
        AppLocaleController.instance.setArabic(false);
        addTearDown(() => AppLocaleController.instance.setArabic(false));

        bool loading = true;
        late StateSetter setLocalState;

        Widget buildHarness() => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setLocalState = setState;
                return Center(
                  child: loading
                      ? CircularProgressIndicator(
                          semanticsLabel: AppLocaleController.instance.text(
                            'Preparing your data',
                            'جارٍ تجهيز بياناتك',
                          ),
                        )
                      : const Text('Done'),
                );
              },
            ),
          ),
        );

        // 1. English, loading -> real accessible label present.
        await tester.pumpWidget(buildHarness());
        expect(find.bySemanticsLabel('Preparing your data'), findsOneWidget);

        // 2. Switch to Arabic mid-loading -> label re-renders in Arabic,
        //    English label is gone (not both present at once).
        AppLocaleController.instance.setArabic(true);
        setLocalState(() {});
        await tester.pump();
        expect(find.bySemanticsLabel('جارٍ تجهيز بياناتك'), findsOneWidget);
        expect(find.bySemanticsLabel('Preparing your data'), findsNothing);

        // 3. Loading finishes -> label disappears entirely, no stale node.
        setLocalState(() => loading = false);
        await tester.pump();
        expect(find.bySemanticsLabel('جارٍ تجهيز بياناتك'), findsNothing);
        expect(find.bySemanticsLabel('Preparing your data'), findsNothing);
        expect(find.text('Done'), findsOneWidget);

        handle.dispose();
      },
    );
  });

  group(
    '11. Loading-state semantics do not duplicate adjacent status text',
    () {
      testWidgets(
        'AU-014: a bare CircularProgressIndicator (no semanticsLabel) placed '
        'next to a status Text contributes zero semantics nodes of its own — '
        'confirming the _TypingIndicator-style pattern used in '
        'dr_niswah_chat_screen.dart and dream_interpreter_screen.dart does not '
        'produce a duplicate/redundant announcement',
        (tester) async {
          final handle = tester.ensureSemantics();

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    ),
                    SizedBox(width: 8),
                    Text('Niswah is thinking…'),
                  ],
                ),
              ),
            ),
          );
          await tester.pump();

          expect(
            find.bySemanticsLabel('Niswah is thinking…'),
            findsOneWidget,
            reason: 'the status text itself must be announced',
          );

          // The bare spinner's own semantics (if Flutter created any node for
          // it at all) must carry no label of its own — confirmed directly
          // against its own render object, not inferred.
          final spinnerSemantics = tester.getSemantics(
            find.byType(CircularProgressIndicator),
          );
          expect(
            spinnerSemantics.label,
            isEmpty,
            reason:
                'the bare spinner (no semanticsLabel set) must not '
                'announce anything of its own — a screen reader must reach '
                'only the adjacent status text',
          );

          handle.dispose();
        },
      );
    },
  );

  group('10. Bottom navigation controls', () {
    testWidgets(
      'each nav tab is announced as selected/unselected with a real label',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: FloatingNavBar(
                selectedIndex: 0,
                onItemTapped: (_) {},
                showFab: false,
                items: const [
                  FloatingNavItem(
                    targetIndex: 0,
                    icon: Icons.home,
                    label: 'Home',
                  ),
                  FloatingNavItem(
                    targetIndex: 1,
                    icon: Icons.calendar_month,
                    label: 'Calendar',
                  ),
                  FloatingNavItem(
                    targetIndex: 2,
                    icon: Icons.insights,
                    label: 'Insights',
                  ),
                  FloatingNavItem(
                    targetIndex: 3,
                    icon: Icons.people,
                    label: 'Community',
                  ),
                  FloatingNavItem(
                    targetIndex: 4,
                    icon: Icons.person,
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final home = find.bySemanticsLabel('Home');
        expect(home, findsOneWidget);
        final data = tester.getSemantics(home);
        expect(
          data.hasFlag(SemanticsFlag.isSelected),
          isTrue,
          reason: 'the active tab (index 0) must announce as selected',
        );

        final calendarData = tester.getSemantics(
          find.bySemanticsLabel('Calendar'),
        );
        expect(calendarData.hasFlag(SemanticsFlag.isSelected), isFalse);

        handle.dispose();
      },
    );
  });

  group('Fiqh Remediation Wave 1 — Pre-E4 Verification (Section 2): Madhhab '
      'onboarding + Settings semantics', () {
    // The Madhhab grid tiles combine title + subtitle into one semantics
    // label (e.g. "Hanafi, 3-day min · 10-day max") — `bySemanticsLabel`
    // does exact string equality for a plain String, so a prefix RegExp
    // is required to match by title alone while still proving the
    // subtitle detail is present in the same, single, unambiguous node.
    Finder bySemanticsLabelStartingWith(String prefix) =>
        find.bySemanticsLabel(RegExp('^${RegExp.escape(prefix)}'));

    testWidgets(
      'the 5-option Madhhab grid exposes a meaningful label and correct '
      'selected state per option, with no duplicate/ambiguous label',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        final handle = tester.ensureSemantics();

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
          "I don't know my Madhhab",
        ]) {
          final finder = bySemanticsLabelStartingWith(label);
          expect(
            finder,
            findsOneWidget,
            reason:
                '"$label" must have exactly one meaningful, unambiguous '
                'semantics node — not zero (missing label) or more than '
                'one (a duplicate/merged announcement)',
          );
          final data = tester.getSemantics(finder);
          expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
          expect(
            data.hasFlag(SemanticsFlag.isSelected),
            isFalse,
            reason: 'nothing is selected yet on a fresh onboarding step',
          );
        }

        // Select Hanafi — its own node (and only its own) must now
        // announce as selected.
        await tester.ensureVisible(find.text('Hanafi'));
        await tester.tap(find.text('Hanafi'));
        await tester.pumpAndSettle();

        final hanafiData = tester.getSemantics(
          bySemanticsLabelStartingWith('Hanafi'),
        );
        expect(hanafiData.hasFlag(SemanticsFlag.isSelected), isTrue);
        final malikiData = tester.getSemantics(
          bySemanticsLabelStartingWith('Maliki'),
        );
        expect(malikiData.hasFlag(SemanticsFlag.isSelected), isFalse);

        handle.dispose();
      },
    );

    testWidgets(
      'the full "I don\'t know" sub-flow exposes meaningful, actionable '
      'controls at every step: explanation, help-me-choose, country '
      'input, suggestion confirmation, and decline',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(false);
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text("I don't know my Madhhab"));
        await tester.tap(find.text("I don't know my Madhhab"));
        await tester.pumpAndSettle();

        // Explanation step: both real actions are labeled, actionable
        // controls, not silent/generic tappable areas.
        for (final label in ['Help me choose', "I'll decide later"]) {
          final finder = find.bySemanticsLabel(label);
          expect(finder, findsOneWidget, reason: '"$label" must be announced');
          expect(
            tester.getSemantics(finder).hasFlag(SemanticsFlag.isButton),
            isTrue,
          );
        }

        await tester.ensureVisible(find.text('Help me choose'));
        await tester.tap(find.text('Help me choose'));
        await tester.pumpAndSettle();

        // Country input step: the text field has a real accessible hint
        // (not silence) — its own placeholder question is rendered as
        // real, findable text, not a purely visual-only cue.
        expect(find.text('Which country do you live in?'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Saudi Arabia');
        await tester.pump();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Suggestion step: the confirmation control and the decline
        // control are both real, distinct, labeled, actionable controls
        // — never a bare "button" with no context.
        final confirmFinder = find.bySemanticsLabel(
          'Yes, Hanbali is my Madhhab',
        );
        expect(confirmFinder, findsOneWidget);
        expect(
          tester.getSemantics(confirmFinder).hasFlag(SemanticsFlag.isButton),
          isTrue,
        );

        final declineFinder = find.bySemanticsLabel(
          "None of these — I'll decide later",
        );
        expect(declineFinder, findsOneWidget);
        expect(
          tester.getSemantics(declineFinder).hasFlag(SemanticsFlag.isButton),
          isTrue,
        );

        handle.dispose();
      },
    );

    testWidgets(
      'Arabic: the 5-option Madhhab grid still exposes one meaningful '
      'label per option — RTL does not corrupt or merge the semantics',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        AppLocaleController.instance.setArabic(true);
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingScreen(onFinished: () {}, initialStep: 2),
          ),
        );
        await tester.pumpAndSettle();

        for (final label in [
          'حنفي',
          'مالكي',
          'شافعي',
          'حنبلي',
          'لا أعرف مذهبي',
        ]) {
          final finder = bySemanticsLabelStartingWith(label);
          expect(
            finder,
            findsOneWidget,
            reason: '"$label" must have exactly one semantics node in RTL too',
          );
          expect(
            tester.getSemantics(finder).hasFlag(SemanticsFlag.isButton),
            isTrue,
          );
        }

        handle.dispose();
        AppLocaleController.instance.setArabic(false);
      },
    );

    testWidgets("Settings' Madhhab grid (including \"I don't know\") exposes "
        'meaningful labels and correct selected state, changeable later', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await MadhhabController.instance.load();
      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
      AppLocaleController.instance.setArabic(false);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Fiqh Madhhab'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final hanafiFinder = bySemanticsLabelStartingWith('Hanafi');
      expect(hanafiFinder, findsOneWidget);
      expect(
        tester.getSemantics(hanafiFinder).hasFlag(SemanticsFlag.isSelected),
        isTrue,
        reason: 'Hanafi was explicitly selected above',
      );

      final unknownFinder = find.bySemanticsLabel("I don't know");
      expect(unknownFinder, findsOneWidget);
      expect(
        tester.getSemantics(unknownFinder).hasFlag(SemanticsFlag.isSelected),
        isFalse,
      );

      // Change the selection to "I don't know" — the selected flag
      // must move with it, never stay stuck on the old choice.
      await tester.tap(unknownFinder);
      await tester.pumpAndSettle();

      expect(
        tester
            .getSemantics(find.bySemanticsLabel("I don't know"))
            .hasFlag(SemanticsFlag.isSelected),
        isTrue,
      );
      expect(
        tester
            .getSemantics(bySemanticsLabelStartingWith('Hanafi'))
            .hasFlag(SemanticsFlag.isSelected),
        isFalse,
      );

      handle.dispose();
    });
  });
}
