import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona B: first bleeding episode, one observation', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    await f.newAccountOnDashboard('B');

    await h.tapVisible(find.text('Period Started'));
    await h.settle(2);
    await h.tapVisible(find.text('Today'), last: true);
    await h.tapVisible(find.text('Medium'));
    await h.tapVisible(find.text('Save'));
    await tester.pump(const Duration(seconds: 6));
    await h.settle(2);
    await h.shot('B', 'reminder_consent_prompt');
    h.note('B tap Not now: ${await h.tapVisible(find.text('Not now'))}');
    await h.settle(2);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2500), warnIfMissed: false);
    await h.settle(1);
    await h.shot('B', 'dashboard_top');
    h.dumpTexts('B dashboard top');
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await h.settle(1);
    await h.shot('B', 'dashboard_bottom_prayer_card');
    h.dumpTexts('B dashboard bottom');

    await h.tapVisible(find.text('Calendar'));
    await h.settle(3);
    await h.shot('B', 'calendar_tab_legacy');
    h.dumpTexts('B calendar tab');

    await h.tapVisible(find.text('Today'), last: true);
    await h.settle(2);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2500), warnIfMissed: false);
    await h.settle(1);
    h.note('B open canonical calendar: ${await h.tapVisible(find.bySemanticsLabel('Cycle calendar'))}');
    await h.settle(3);
    await h.shot('B', 'canonical_calendar');
    h.dumpTexts('B canonical calendar');
  });
}
