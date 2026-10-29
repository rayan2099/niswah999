import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/config/launch_features.dart';
import 'package:niswah/core/data/app_features.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/widgets/floating_nav_bar.dart';
import 'package:niswah/features/auth/presentation/screens/profile_screen.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';

/// Community is hidden from release builds until block and report exist
/// (NJ-183, NJ-184, NJ-190). These tests run with community off, the way a
/// release build without `--dart-define=NISWAH_COMMUNITY=true` does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    LaunchFeatures.debugCommunityOverride = false;
  });

  tearDown(() => LaunchFeatures.debugCommunityOverride = true);

  test('release default leaves community out', () {
    LaunchFeatures.debugCommunityOverride = null;
    expect(LaunchFeatures.community, isFalse);
  });

  test('feature cards do not advertise community while it is hidden', () {
    expect(launchAppFeatures.any((f) => f.isCommunity), isFalse);
    expect(launchAppFeatures.length, kAppFeatures.length - 1);
    LaunchFeatures.debugCommunityOverride = true;
    expect(launchAppFeatures.length, kAppFeatures.length);
  });

  testWidgets('four-tab bar keeps each tab tappable at its own index', (
    tester,
  ) async {
    final tapped = <int>[];
    for (final rtl in [false, true]) {
      tapped.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              bottomNavigationBar: FloatingNavBar(
                selectedIndex: 0,
                onItemTapped: tapped.add,
                onFABPressed: () {},
                items: const [
                  FloatingNavItem(
                    targetIndex: 0,
                    icon: Icons.home_outlined,
                    label: 'Today',
                  ),
                  FloatingNavItem(
                    targetIndex: 1,
                    icon: Icons.calendar_month_outlined,
                    label: 'Calendar',
                  ),
                  FloatingNavItem(
                    targetIndex: 2,
                    icon: Icons.bar_chart_outlined,
                    label: 'Insights',
                  ),
                  FloatingNavItem(
                    targetIndex: 4,
                    icon: Icons.person_outline_rounded,
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final label in ['Today', 'Calendar', 'Insights', 'Profile']) {
        await tester.tap(find.text(label));
      }
      expect(tapped, [0, 1, 2, 4], reason: 'rtl=$rtl');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('profile shows no messages or community language rows', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Messages'), findsNothing);
    expect(find.text('Invite a Friend'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Delete Account'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Community language'), findsNothing);
  });

  testWidgets('sign-in showcase does not advertise community', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Women community'), findsNothing);
    expect(find.text('PDF reports'), findsOneWidget);
  });
}
