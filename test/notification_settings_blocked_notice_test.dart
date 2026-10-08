import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/notifications/presentation/screens/notification_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// F-005 — a reminder switch can read ON while the OS will never show anything.
/// Notification settings must say so, and must NOT claim it when the OS allows
/// notifications or cannot say.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
  });

  Future<void> open(WidgetTester tester, Future<bool?> Function() check) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsScreen(notificationsEnabled: check),
      ),
    );
    await tester.pumpAndSettle();
  }

  const notice = Key('notifications-blocked-notice');

  testWidgets('shown when the OS does not allow notifications', (tester) async {
    await open(tester, () async => false);
    expect(find.byKey(notice), findsOneWidget);
    expect(
      find.textContaining('Notifications are not allowed'),
      findsOneWidget,
    );
    // The settings themselves are still there.
    expect(find.text('Daily prayer reminders'), findsOneWidget);
  });

  testWidgets('hidden when the OS allows notifications', (tester) async {
    await open(tester, () async => true);
    expect(find.byKey(notice), findsNothing);
  });

  testWidgets('hidden when the platform cannot say (unknown, not blocked)', (
    tester,
  ) async {
    await open(tester, () async => null);
    expect(find.byKey(notice), findsNothing);
  });

  testWidgets('re-checked when the app resumes (she just allowed them)', (
    tester,
  ) async {
    var allowed = false;
    await open(tester, () async => allowed);
    expect(find.byKey(notice), findsOneWidget);

    allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(notice), findsNothing);
  });
}
