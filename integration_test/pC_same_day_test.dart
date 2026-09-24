import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Persona C — genuine same-day multiple observations. The real
/// cross-check against the database happens on the HOST side, after this
/// run completes (`Process.run` cannot spawn `docker` from inside the
/// iOS app itself — confirmed: "ProcessException: Starting new processes
/// is not supported on iOS" — so this test logs its email as the lookup
/// key instead of querying the database directly).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona C: a second same-day observation via the real '
      '"Add a missing day" action, targeting today\'s own date', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    final email = await f.newAccountOnDashboard('C');
    h.note('LOOKUP_EMAIL=$email');
    await f.startBleedingToday('C'); // observation #1: Medium
    await h.shot('C', 'dashboard_before_backfill');

    // Persona C, option A: the SAME production "Add a missing day"
    // action, picking TODAY's own date, is the real user-facing path to
    // a second same-day observation (confirmed structurally: no
    // uniqueness constraint on (episode_id, observed_date) in
    // bleeding_observations, and _BackfillObservationSheet's own date
    // picker allows lastDate: now, i.e. today included).
    final openedBackfill = await h.tapVisible(find.text('Add a missing day'));
    h.note('C opened "Add a missing day": $openedBackfill');
    await h.settle(2);
    await h.shot('C', 'backfill_sheet');

    if (!openedBackfill) {
      h.note('C ABORTED — could not open the backfill sheet this run');
      return;
    }

    final openedDatePicker = await h.tapVisible(find.text('Choose a date'));
    h.note('C opened the native date picker: $openedDatePicker');
    await h.settle(1);
    if (!openedDatePicker) {
      h.note('C ABORTED — "Choose a date" did not open the date picker');
      return;
    }

    final switchedToInput = await h.tapVisible(
      find.byTooltip('Switch to input'),
    );
    h.note('C switched to input mode: $switchedToInput');
    await h.settle(1);

    final dateField = find.byType(TextField);
    if (dateField.evaluate().isEmpty) {
      h.note('C ABORTED — no date TextField after switching to input mode');
      await h.shot('C', 'no_date_field');
      return;
    }

    final today = DateTime.now();
    final typed =
        '${today.month.toString().padLeft(2, '0')}/'
        '${today.day.toString().padLeft(2, '0')}/${today.year}';
    await tester.enterText(dateField.first, typed);
    await tester.pump(const Duration(milliseconds: 300));
    h.note('C tap OK: ${await h.tapVisible(find.text('OK'))}');
    await h.settle(1);
    h.note('C tap Heavy: ${await h.tapVisible(find.text('Heavy'))}');
    h.note('C tap Save: ${await h.tapVisible(find.text('Save'))}');
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    await h.shot('C', 'after_second_save');
    h.note(
      'C RESULT: SEQUENCE COMPLETE — see host-side SQL check for '
      'the real PASS/FAIL verdict (two independent same-day rows)',
    );
  });
}
