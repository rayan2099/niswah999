import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import '../test/support/pdf_text.dart';
import 'support/flows.dart';
import 'support/flows_ext.dart';
import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('explore reports', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('X')) return;
    final f = Flows(h);
    await f.newAccountHanafiStillBleeding('X');
    h.dumpTexts('X dashboard (Today)');
    // wellbeing check-in
    await h.scrollToTop();
    await tester.pump(const Duration(seconds: 1));
    await h.tapVisible(find.widgetWithText(OutlinedButton, 'Log'));
    await tester.pump(const Duration(seconds: 2));
    await h.tapVisible(find.text('Save check-in'));
    await tester.pump(const Duration(seconds: 3));
    // marry
    await h.tapVisible(find.text('Profile'), last: true);
    await tester.pump(const Duration(seconds: 2));
    final marriedSwitch = find.descendant(
      of: find.ancestor(of: find.text('I am married'), matching: find.byType(Container)),
      matching: find.byType(Switch),
    );
    await h.tapVisible(marriedSwitch);
    await tester.pump(const Duration(seconds: 2));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1500), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));

    Future<void> openReport(String title) async {
      h.note('X step: opening $title');
      final row = find.ancestor(of: find.text(title), matching: find.byType(Container));
      if (row.evaluate().isEmpty) { h.note('X $title: no row'); return; }
      final button = find.descendant(of: row.first, matching: find.byType(TextButton));
      if (button.evaluate().isEmpty) { h.note('X $title: no button'); return; }
      await tester.ensureVisible(button.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(button.first, warnIfMissed: false);
      for (var i = 0; i < 6; i++) { await tester.pump(const Duration(seconds: 1)); }
      final preview = find.byType(PdfPreview);
      h.note('X $title previews=${preview.evaluate().length}');
      if (preview.evaluate().isNotEmpty) {
        final bytes = await tester.runAsync(() async => await tester.widget<PdfPreview>(preview.first).build(PdfPageFormat.a4));
        if (bytes != null) {
          final text = PdfText.parse(bytes);
          h.note('X $title pdfBytes=${bytes.length} pages=${text.pageCount}');
          final all = text.all.replaceAll('\n', ' ');
          for (var i = 0; i < all.length; i += 600) {
            h.note('X $title TEXT[${i ~/ 600}] ${all.substring(i, (i + 600).clamp(0, all.length))}');
          }
        }
        Navigator.of(tester.element(preview.first)).pop();
      } else {
        h.dumpTexts('X $title screen');
        final nav = find.byType(Navigator);
        Navigator.of(tester.element(nav.last)).maybePop();
      }
      for (var i = 0; i < 3; i++) { await tester.pump(const Duration(seconds: 1)); }
      h.note('X step: closed $title');
    }

    for (final t in ['Export Fiqh Log', "Export Doctor's Report", 'Mental state report', 'Husband Report', 'Export My Data (JSON)']) {
      await openReport(t);
    }
    h.reportResult(PersonaResult(testId: 'X', expectedOutcome: 'x', actualOutcome: 'x', status: PersonaStatus.pass));
  });
}
