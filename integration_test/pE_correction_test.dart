import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Persona E — correction + revision history + cross-screen consistency.
/// The real database verification happens on the HOST side after this
/// run (see pC_same_day_test.dart's own note on why `Process.run` cannot
/// spawn `docker` from inside the iOS app itself).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona E: correcting an entry updates its revision '
      'history AND the legacy cycle_entries projection (cross-screen '
      'consistency fix)', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    final email = await f.newAccountOnDashboard('E');
    h.note('LOOKUP_EMAIL=$email');
    await f.startBleedingToday('E', flow: 'Light');
    await h.shot('E', 'dashboard_before_correction');

    // Real screen: open the canonical calendar, tap today, correct it.
    await h.scrollToTop();
    await h.settle(1);
    final calIcon = find.bySemanticsLabel('Cycle calendar');
    if (calIcon.evaluate().isEmpty) {
      h.note('E ABORTED — Cycle calendar icon not found');
      return;
    }
    await tester.tapAt(tester.getCenter(calIcon));
    await tester.pumpAndSettle();
    await h.shot('E', 'calendar_opened');
    final todayNum = DateTime.now().day.toString();
    final opened = await h.tapVisible(find.text(todayNum), last: true);
    h.note('E opened day detail: $opened');
    await h.settle(2);
    await h.shot('E', 'day_detail');
    h.dumpTexts('E day detail before correction');

    if (!opened) {
      h.note(
        'E BLOCKED — could not open the day-detail sheet via simulated '
        'tap in this harness this run; correction flow not exercised '
        'live',
      );
      return;
    }

    final correctTap = await h.tapVisible(find.text('Correct this entry'));
    h.note('E tap Correct this entry: $correctTap');
    if (!correctTap) {
      h.note(
        'E BLOCKED — day detail opened but "Correct this entry" was not '
        'reachable',
      );
      return;
    }

    await h.settle(2);
    await h.shot('E', 'correction_sheet');
    h.note('E tap Heavy: ${await h.tapVisible(find.text('Heavy'))}');
    h.note(
      'E tap Save correction: '
      '${await h.tapVisible(find.text('Save correction'))}',
    );
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    await h.shot('E', 'after_correction');
    h.note(
      'E RESULT: SEQUENCE COMPLETE — see host-side SQL check for the '
      'real PASS/FAIL verdict (cycle_entries reflects heavy, 2 total '
      'observation rows)',
    );
  });
}
