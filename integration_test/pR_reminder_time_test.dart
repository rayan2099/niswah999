import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 — REM-02: changing the daily check-in reminder time through the
/// real Material time picker. The new time must appear on the screen and
/// must SURVIVE leaving and reopening Notification settings (i.e. it was
/// persisted, not just repainted).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('REM-02: change reminder time and see it persist', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('R2')) return;
    final f = Flows(h);
    final email = await f.newAccountOnDashboard('R2');
    h.note('LOOKUP_EMAIL=$email');

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    Future<String> openSettings() async {
      await h.scrollToTop();
      await h.tapVisible(find.text('Profile'), last: true);
      await h.settle(2);
      await tester.scrollUntilVisible(
        find.text('Notification settings'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await h.tapVisible(find.text('Notification settings'));
      await h.settle(2);
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -600),
        warnIfMissed: false,
      );
      await h.settle(1);
      return texts('R2 notification settings');
    }

    final before = await openSettings();
    final m0 = RegExp(r'Reminder time: ([^|]+?) \|').firstMatch(before);
    h.note('R2 reminder time before: ${m0?.group(1)}');

    final tappedChange = await h.tapVisible(find.text('Change').first);
    await h.settle(2);
    await h.shot('R2', 'time_picker');
    final dialogTexts = await texts('R2 time picker');
    // Switch the dial to text entry, then type 7:30 PM.
    var typed = false;
    final toggle = find.byIcon(Icons.keyboard_outlined);
    if (toggle.evaluate().isNotEmpty) {
      await h.tapVisible(toggle);
      await h.settle(1);
      final fields = find.byType(TextField);
      if (fields.evaluate().length >= 2) {
        await tester.enterText(fields.at(0), '7');
        await tester.enterText(fields.at(1), '30');
        await tester.pump(const Duration(milliseconds: 300));
        typed = true;
      }
      if (find.text('PM').evaluate().isNotEmpty) {
        await h.tapVisible(find.text('PM'));
      }
    }
    final confirmed = await h.tapVisible(find.text('OK'));
    await h.settle(2);
    final after = await texts('R2 after changing time');
    final shows730 = after.contains('7:30 PM');
    h.note(
      'R2 change tapped=$tappedChange typed=$typed confirmed=$confirmed '
      'shows730=$shows730 dialogHadInputToggle=${toggle.evaluate().isNotEmpty} '
      'dialogTexts=${dialogTexts.length}',
    );

    // Leave and reopen: it must still be 7:30 PM.
    await h.scrollToTop();
    final reopened = await openSettings();
    final persisted = reopened.contains('7:30 PM');
    h.note('R2 persisted after reopening: $persisted');

    final crashed = tester.takeException() != null;
    final pass =
        !crashed && tappedChange && typed && confirmed && shows730 && persisted;
    h.reportResult(
      PersonaResult(
        testId: 'R2',
        expectedOutcome: 'REM-02: the reminder time chosen in the real time picker is shown and is still there after leaving and reopening Notification settings',
        actualOutcome:
            'crashed=$crashed change=$tappedChange typed=$typed confirmed=$confirmed shows730=$shows730 persisted=$persisted',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'R2_time_picker.png',
      ),
    );
  });
}
