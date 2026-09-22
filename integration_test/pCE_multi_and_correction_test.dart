import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Personas C+E: same-day observations, then detail + correction', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    await f.newAccountOnDashboard('CE');
    await f.startBleedingToday('CE');

    // C: two more observations the same day through the real check-in sheet.
    for (final answer in ['Yes', "I'm not sure"]) {
      await h.tapVisible(find.text('Daily check-in'));
      await h.settle(2);
      final ok = await h.tapVisible(find.text(answer), last: true);
      await tester.pump(const Duration(seconds: 4));
      await h.settle(2);
      h.dumpTexts('C after check-in "$answer" (tapped=$ok)');
      await h.shot('C', 'after_checkin_${answer.replaceAll(RegExp(r"[^A-Za-z]"), '')}');
      // some answers open a follow-up sheet; log it and dismiss with Save if present
      if (find.text('Save').evaluate().isNotEmpty) {
        h.note('C follow-up sheet has Save; pressing it');
        await h.tapVisible(find.text('Save'));
        await tester.pump(const Duration(seconds: 4));
        await h.settle(2);
      }
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2500), warnIfMissed: false);
    await h.settle(1);
    await h.shot('C', 'dashboard_three_observations');
    h.dumpTexts('C dashboard');

    h.note('C open calendar: ${await h.tapVisible(find.bySemanticsLabel('Cycle calendar'))}');
    await h.settle(3);
    await h.shot('C', 'calendar_today_multi');
    // today's cell is the highlighted one — tap by today's day-of-month
    final today = DateTime.now().day.toString();
    final cell = find.text(today);
    h.note('C tap today cell: ${await h.tapVisible(cell, last: true)}');
    await h.settle(3);
    await h.shot('E', 'day_detail_sheet');
    h.dumpTexts('E day detail');
  });
}
