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
    // Production kill switch — before ANY sign-up, fixture or action.
    if (!await h.guardBackend('C')) return;
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
      h.reportResult(
        PersonaResult(
          testId: 'C',
          expectedOutcome:
              'A second same-day observation is added via "Add a missing '
              'day", targeting today\'s own date',
          actualOutcome: 'Could not open the backfill sheet',
          status: PersonaStatus.blocked,
          screenshotRef: 'C_11_dashboard_before_backfill.png',
        ),
      );
      return;
    }

    final openedDatePicker = await h.tapVisible(find.text('Choose a date'));
    h.note('C opened the native date picker: $openedDatePicker');
    await h.settle(1);
    if (!openedDatePicker) {
      h.note('C ABORTED — "Choose a date" did not open the date picker');
      h.reportResult(
        PersonaResult(
          testId: 'C',
          expectedOutcome:
              'A second same-day observation is added via "Add a missing '
              'day", targeting today\'s own date',
          actualOutcome: '"Choose a date" did not open the date picker',
          status: PersonaStatus.blocked,
          screenshotRef: 'C_12_backfill_sheet.png',
        ),
      );
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
      h.reportResult(
        PersonaResult(
          testId: 'C',
          expectedOutcome:
              'A second same-day observation is added via "Add a missing '
              'day", targeting today\'s own date',
          actualOutcome: 'No date TextField after switching to input mode',
          status: PersonaStatus.blocked,
        ),
      );
      return;
    }

    final today = DateTime.now();
    final typed =
        '${today.month.toString().padLeft(2, '0')}/'
        '${today.day.toString().padLeft(2, '0')}/${today.year}';
    await tester.enterText(dateField.first, typed);
    await tester.pump(const Duration(milliseconds: 300));
    final tappedOk = await h.tapVisible(find.text('OK'));
    h.note('C tap OK: $tappedOk');
    await h.settle(1);
    final tappedHeavy = await h.tapVisible(find.text('Heavy'));
    h.note('C tap Heavy: $tappedHeavy');
    final tappedSave = await h.tapVisible(find.text('Save'));
    h.note('C tap Save: $tappedSave');
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    await h.shot('C', 'after_second_save');
    final uiSequenceComplete = tappedOk && tappedHeavy && tappedSave;
    h.note(
      'C RESULT: SEQUENCE ${uiSequenceComplete ? "COMPLETE" : "INCOMPLETE"} '
      '— see host-side SQL check for the real PASS/FAIL verdict on data '
      'correctness (two independent same-day rows)',
    );
    h.reportResult(
      PersonaResult(
        testId: 'C',
        expectedOutcome:
            'A second same-day observation is added via the real "Add a '
            'missing day" action, targeting today\'s own date, producing '
            'two independent same-day observation rows',
        actualOutcome: uiSequenceComplete
            ? 'Full UI sequence completed (date entered, flow selected, '
                  'saved); DB-level row-count correctness verified '
                  'separately via host-side SQL, not from within this '
                  'iOS-sandboxed test'
            : 'UI sequence did not complete: tappedOk=$tappedOk '
                  'tappedHeavy=$tappedHeavy tappedSave=$tappedSave',
        status: uiSequenceComplete ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'C_13_after_second_save.png',
      ),
    );
  });
}
