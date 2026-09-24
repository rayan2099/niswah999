import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona G: changing/disabling daily reminders, real screen', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    await f.newAccountOnDashboard('G');
    await f.startBleedingToday('G');

    h.note('G open Profile tab: ${await h.tapVisible(find.text('Profile'))}');
    await h.settle(2);
    await h.shot('G', 'profile_screen');
    h.dumpTexts('G profile');

    await tester.scrollUntilVisible(
      find.text('Notification settings'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    h.note(
      'G open Notification settings: '
      '${await h.tapVisible(find.text('Notification settings'))}',
    );
    await h.settle(2);
    await h.shot('G', 'notification_settings');
    h.dumpTexts('G notification settings');

    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -600),
      warnIfMissed: false,
    );
    await h.settle(1);
    await h.shot('G', 'scrolled_down');
    h.dumpTexts('G scrolled down');

    // Toggle the daily check-in reminder switch specifically (whatever
    // its current value) and confirm the real screen reflects the
    // change.
    final checkinTile = find.text('Daily check-in reminder');
    final tilePresent = checkinTile.evaluate().isNotEmpty;
    h.note('G check-in tile present: $tilePresent');
    var toggled = false;
    String actualOutcome = 'Daily check-in reminder tile not found';
    if (tilePresent) {
      final switchFinder = find.descendant(
        of: find.ancestor(of: checkinTile, matching: find.byType(Card)),
        matching: find.byType(Switch),
      );
      final before = (switchFinder.evaluate().first.widget as Switch).value;
      await h.tapVisible(switchFinder);
      await h.settle(2);
      final after = (switchFinder.evaluate().first.widget as Switch).value;
      h.note('G check-in reminder toggled: $before -> $after');
      toggled = before != after;
      actualOutcome = 'Switch value before=$before after=$after';
    }
    await h.shot('G', 'after_toggle');
    h.reportResult(
      PersonaResult(
        testId: 'G',
        expectedOutcome:
            'The real Notification Settings screen shows the daily '
            'check-in reminder control, and toggling it flips the real '
            'switch state',
        actualOutcome: actualOutcome,
        status: toggled
            ? PersonaStatus.pass
            : (tilePresent ? PersonaStatus.fail : PersonaStatus.blocked),
        screenshotRef: 'G_12_notification_settings.png',
      ),
    );
  });
}
