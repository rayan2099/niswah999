import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../test/support/pdf_text.dart';
import 'harness.dart';

/// Helpers for the report/export acceptance personas. A report opens ONLY
/// from the small "Download" button in its Profile row (tapping the title
/// does nothing), and its body is a PdfPreview whose continuous rendering
/// never settles — so these helpers pump fixed durations and never call
/// pumpAndSettle while a report is on screen.
extension ReportHelpers on Harness {
  /// Scrolls Profile to its export section (assumes Profile is showing).
  Future<void> scrollToExports() async {
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -1500),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Finder exportButton(String rowTitle) {
    final row = find.ancestor(
      of: find.text(rowTitle),
      matching: find.byType(Container),
    );
    if (row.evaluate().isEmpty) return find.byWidgetPredicate((_) => false);
    return find.descendant(of: row.first, matching: find.byType(TextButton));
  }

  bool hasExportRow(String rowTitle) =>
      find.text(rowTitle).evaluate().isNotEmpty;

  /// Opens the report behind [rowTitle], returns the text of the PDF its
  /// screen generates (the SAME bytes the on-screen preview is built from),
  /// then returns to Profile. Null when the row/button/preview is missing.
  Future<PdfText?> openReportPdf(String rowTitle) async {
    final button = exportButton(rowTitle);
    if (button.evaluate().isEmpty) {
      note('REPORT $rowTitle: no Download button found');
      return null;
    }
    await tester.ensureVisible(button.first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(button.first, warnIfMissed: false);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final preview = find.byType(PdfPreview);
    PdfText? text;
    if (preview.evaluate().isEmpty) {
      dumpTexts('REPORT $rowTitle (no PdfPreview)');
    } else {
      final bytes = await tester.runAsync(
        () async => await tester
            .widget<PdfPreview>(preview.first)
            .build(PdfPageFormat.a4),
      );
      if (bytes != null && bytes.isNotEmpty) {
        text = PdfText.parse(bytes);
        final all = text.all.replaceAll('\n', ' ');
        note(
          'REPORT $rowTitle: ${bytes.length} bytes, ${text.pageCount} page(s)',
        );
        for (var i = 0; i < all.length; i += 600) {
          note(
            'REPORT $rowTitle TEXT[${i ~/ 600}] '
            '${all.substring(i, (i + 600).clamp(0, all.length))}',
          );
        }
      }
    }
    final nav = find.byType(Navigator);
    if (nav.evaluate().isNotEmpty) {
      Navigator.of(
        tester.element(
          preview.evaluate().isNotEmpty ? preview.first : nav.last,
        ),
      ).maybePop();
    }
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    return text;
  }

  /// Opens a non-PDF export screen (JSON export) and returns its visible
  /// texts (including the SelectableText JSON), then returns to Profile.
  Future<List<String>> openExportScreenTexts(String rowTitle) async {
    final button = exportButton(rowTitle);
    if (button.evaluate().isEmpty) return const [];
    await tester.ensureVisible(button.first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(button.first, warnIfMissed: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final texts = <String>[];
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as Text;
      texts.add(w.data ?? w.textSpan?.toPlainText() ?? '');
    }
    for (final e in find.byType(SelectableText).evaluate()) {
      final w = e.widget as SelectableText;
      texts.add(w.data ?? w.textSpan?.toPlainText() ?? '');
    }
    Navigator.of(tester.element(find.byType(Navigator).last)).maybePop();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    return texts;
  }
}
