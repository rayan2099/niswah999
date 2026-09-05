import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/widgets/floating_nav_bar.dart';
import 'package:niswah/features/auth/presentation/screens/profile_screen.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';
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
    testWidgets(
      'email and password fields expose accessible labels',
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
      },
    );
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
  });

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
}
