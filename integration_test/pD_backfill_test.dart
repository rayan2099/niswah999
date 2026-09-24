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
      return;
    }

    final openedDatePicker = await h.tapVisible(find.text('Choose a date'));
    h.note('D opened the native date picker: $openedDatePicker');
    await h.settle(1);
    if (!openedDatePicker) {
      h.note('D ABORTED — "Choose a date" did not open the date picker');
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
      return;
    }

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final typed =
        '${yesterday.month.toString().padLeft(2, '0')}/'
        '${yesterday.day.toString().padLeft(2, '0')}/${yesterday.year}';
    await tester.enterText(dateField.first, typed);
    await tester.pump(const Duration(milliseconds: 300));
    h.note('D typed date: $typed');
    h.note('D tap OK: ${await h.tapVisible(find.text('OK'))}');
    await h.settle(1);
    h.note('D tap Medium: ${await h.tapVisible(find.text('Medium'))}');
    h.note('D tap Save: ${await h.tapVisible(find.text('Save'))}');
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    await h.shot('D', 'after_backfill_save');
    h.note(
      'D RESULT: SEQUENCE COMPLETE — see host-side SQL check for the '
      'real PASS/FAIL verdict (a real observation row dated yesterday)',
    );
  });
}
