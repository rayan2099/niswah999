import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona D+E: missed check-in backfilled, then corrected', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    await f.newAccountOnDashboard('D');
    await f.startBleedingToday('D');

    h.note(
      'D open Add a missing day: ${await h.tapVisible(find.text('Add a missing day'))}',
    );
    await h.settle(2);
    await h.shot('D', 'backfill_sheet_initial');
    h.dumpTexts('D backfill sheet');

    // Pick "yesterday" (the earliest, most representative missed day) via
    // the real date field, then choose a flow level and save.
    final dateField = find.byIcon(Icons.calendar_today_outlined);
    if (dateField.evaluate().isEmpty) {
      h.note('D no date-field icon found; trying textbutton with date text');
    }
    // The sheet likely shows a tappable date selector; find any button
    // whose text looks like a date/placeholder and tap it.
    for (final label in [
      'Select date',
      'Select a date',
      'Choose a date',
      'Date',
    ]) {
      if (find.textContaining(label).evaluate().isNotEmpty) {
        h.note(
          'D tap date label "$label": ${await h.tapVisible(find.textContaining(label))}',
        );
        break;
      }
    }
    await h.settle(1);
    // real Material date picker: switch to keyboard-entry mode (far more
    // reliable to automate than a PageView calendar grid, which can keep
    // an adjacent month's day cells in the tree during its swipe
    // animation) and type yesterday's date directly.
    h.note(
      'D tap Switch to input: '
      '${await h.tapVisible(find.byTooltip('Switch to input'))}',
    );
    await h.settle(1);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final typed =
        '${yesterday.month.toString().padLeft(2, '0')}/'
        '${yesterday.day.toString().padLeft(2, '0')}/${yesterday.year}';
    final dateInput = find.byType(TextField);
    if (dateInput.evaluate().isNotEmpty) {
      await tester.enterText(dateInput.first, typed);
      h.note('D typed date: $typed');
    } else {
      h.note('D no TextField found for date entry');
    }
    await tester.pump(const Duration(milliseconds: 300));
    h.note('D tap OK: ${await h.tapVisible(find.text('OK'))}');
    await h.settle(1);
    await h.tapVisible(find.text('Medium'));
    await h.shot('D', 'backfill_filled');
    h.note('D tap Save: ${await h.tapVisible(find.text('Save'))}');
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    await h.shot('D', 'after_backfill_save');
    h.dumpTexts('D after backfill save');

    // Open the canonical calendar and inspect yesterday's day-detail.
    // (must scroll back to the top first — the header icon is off-screen
    // after the earlier bottom-scroll.)
    await h.scrollToTop();
    await h.settle(1);
    h.note(
      'D calendar-icon finder count: ${find.bySemanticsLabel('Cycle calendar').evaluate().length}',
    );
    final calIcon = find.bySemanticsLabel('Cycle calendar');
    h.note('D calIcon center: ${tester.getCenter(calIcon)}');
    await tester.tapAt(tester.getCenter(calIcon));
    await tester.pumpAndSettle();
    h.note(
      'D route after tap: ${ModalRoute.of(tester.element(find.byType(Scaffold).first))?.settings.name}',
    );
    await h.shot('D', 'calendar_after_backfill');
    h.note(
      'D tap day 21 cell: ${await h.tapVisible(find.text('21'), last: true)}',
    );
    await h.settle(2);
    await h.shot('D', 'day21_detail');
    h.dumpTexts('D day21 detail');

    // Persona E: correct that same entry from the detail sheet.
    h.note(
      'E tap Correct this entry: ${await h.tapVisible(find.text('Correct this entry'))}',
    );
    await h.settle(2);
    await h.shot('E', 'correction_sheet');
    h.dumpTexts('E correction sheet');
  });
}
