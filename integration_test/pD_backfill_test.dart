import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Persona D — missed check-in, later backfill, via the real Material
/// date picker's keyboard-entry mode (far more reliable to automate
/// than tapping a specific day cell in the calendar grid, which can
/// keep an adjacent month's cells in the tree during its own swipe
/// animation).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona D: a missed day, backfilled via the real date '
      'picker', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    final email = await f.newAccountOnDashboard('D');
    h.note('LOOKUP_EMAIL=$email');
    await f.startBleedingToday('D');
    await h.shot('D', 'dashboard_before_backfill');

    final openedBackfill = await h.tapVisible(find.text('Add a missing day'));
    h.note('D opened "Add a missing day": $openedBackfill');
    await h.settle(2);
    await h.shot('D', 'backfill_sheet');
    if (!openedBackfill) {
      h.note('D ABORTED — could not open the backfill sheet');
      h.reportResult(
        PersonaResult(
          testId: 'D',
          expectedOutcome:
              'A missed day is backfilled via the real date picker',
          actualOutcome: 'Could not open the backfill sheet',
          status: PersonaStatus.blocked,
          screenshotRef: 'D_11_backfill_sheet_initial.png',
        ),
      );
      return;
    }

    final openedDatePicker = await h.tapVisible(find.text('Choose a date'));
    h.note('D opened the native date picker: $openedDatePicker');
    await h.settle(1);
    if (!openedDatePicker) {
      h.note('D ABORTED — "Choose a date" did not open the date picker');
      h.reportResult(
        PersonaResult(
          testId: 'D',
          expectedOutcome:
              'A missed day is backfilled via the real date picker',
          actualOutcome: '"Choose a date" did not open the date picker',
          status: PersonaStatus.blocked,
        ),
      );
      return;
    }

    final switchedToInput = await h.tapVisible(
      find.byTooltip('Switch to input'),
    );
    h.note('D switched to input mode: $switchedToInput');
    await h.settle(1);

    final dateField = find.byType(TextField);
    if (dateField.evaluate().isEmpty) {
      h.note('D ABORTED — no date TextField after switching to input mode');
      h.reportResult(
        PersonaResult(
          testId: 'D',
          expectedOutcome:
              'A missed day is backfilled via the real date picker',
          actualOutcome: 'No date TextField after switching to input mode',
          status: PersonaStatus.blocked,
        ),
      );
      return;
    }

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final typed =
        '${yesterday.month.toString().padLeft(2, '0')}/'
        '${yesterday.day.toString().padLeft(2, '0')}/${yesterday.year}';
    await tester.enterText(dateField.first, typed);
    await tester.pump(const Duration(milliseconds: 300));
    h.note('D typed date: $typed');
    final tappedOk = await h.tapVisible(find.text('OK'));
    h.note('D tap OK: $tappedOk');
    await h.settle(1);
    final tappedMedium = await h.tapVisible(find.text('Medium'));
    h.note('D tap Medium: $tappedMedium');
    final tappedSave = await h.tapVisible(find.text('Save'));
    h.note('D tap Save: $tappedSave');
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    await h.shot('D', 'after_backfill_save');
    final uiSequenceComplete = tappedOk && tappedMedium && tappedSave;
    h.note(
      'D RESULT: SEQUENCE ${uiSequenceComplete ? "COMPLETE" : "INCOMPLETE"} '
      '— see host-side SQL check for the real PASS/FAIL verdict on data '
      'correctness (a real observation row dated yesterday)',
    );
    h.reportResult(
      PersonaResult(
        testId: 'D',
        expectedOutcome: 'A missed day is backfilled via the real date picker',
        actualOutcome: uiSequenceComplete
            ? 'Full UI sequence completed (date entered, flow selected, '
                  'saved); DB-level correctness verified separately via '
                  'host-side SQL'
            : 'UI sequence did not complete: tappedOk=$tappedOk '
                  'tappedMedium=$tappedMedium tappedSave=$tappedSave',
        status: uiSequenceComplete ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'D_11_backfill_sheet_initial.png',
      ),
    );
  });
}
