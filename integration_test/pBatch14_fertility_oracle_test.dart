import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/main.dart' as app;

import '../test/support/pdf_text.dart';
import 'support/flows.dart';
import 'support/harness.dart';
import 'support/reports.dart';

/// TTC-03 — the fertility window shown on the Calendar is checked against an
/// oracle computed INDEPENDENTLY in this test from the documented heuristic
/// (ovulation = next period start - 14 days), from inputs the test itself
/// entered:
///
///   two real cycle starts 32 days apart (onboarding history + "Period
///   Started" today) -> cycle length 32, so with T = today:
///     START OF CYCLE = T, NEXT CYCLE = T + 32, OVULATION = T + 18.
///
/// A second, independent surface is compared too: the Husband report's
/// "NEXT EXPECTED PERIOD" and "FERTILITY WINDOW" tiles (window = ovulation - 5
/// days .. ovulation + 1 day) are read out of the generated PDF text.
///
/// The "Chance of pregnancy" label is then read at controlled clock offsets
/// (AppClock): far from ovulation it must be LOW, and ON the ovulation day it
/// must be HIGH — so a card that merely renders "some" label cannot pass.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder switchFor(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(Container)),
    matching: find.byType(Switch),
  );

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
  String short(DateTime d) => '${d.day} ${months[d.month - 1]}';

  testWidgets('Batch 14: fertility window dates and chance vs an oracle', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch14')) return;
    addTearDown(AppClock.reset);
    final f = Flows(h);

    final email = await f.newAccountWithRealHistory('FT');
    h.note('LOOKUP_EMAIL=$email');
    await f.startBleedingToday('FT');

    Future<void> openTab(String tab) async {
      await h.scrollToTop();
      await h.tapVisible(find.text(tab), last: true);
      await h.settle(2);
    }

    Future<void> ensureOn(String title) async {
      final s = switchFor(title);
      if (s.evaluate().isNotEmpty &&
          !(s.evaluate().first.widget as Switch).value) {
        await h.tapVisible(s);
        await h.settle(2);
      }
    }

    await openTab('Profile');
    await ensureOn('I am married');
    await ensureOn('TTC Mode');

    final today = DateTime.now();
    final oracle = (
      start: short(today),
      ovulation: short(today.add(const Duration(days: 18))),
      next: short(today.add(const Duration(days: 32))),
    );

    /// Value text under a chart label such as 'OVULATION'.
    String? labelled(String label) {
      final col = find.ancestor(
        of: find.text(label),
        matching: find.byType(Column),
      );
      if (col.evaluate().isEmpty) return null;
      final texts = find
          .descendant(of: col.first, matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .toList();
      return texts.length >= 2 ? texts[1] : null;
    }

    String? chance() {
      final row = find.ancestor(
        of: find.text('Chance of pregnancy'),
        matching: find.byType(Row),
      );
      if (row.evaluate().isEmpty) return null;
      final texts = find
          .descendant(of: row.first, matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .toList();
      return texts.length >= 2 ? texts[1] : null;
    }

    Future<void> showCalendarAtDay(int dayOffset) async {
      AppClock.now = () => DateTime.now().add(Duration(days: dayOffset));
      await openTab('Today');
      await openTab('Calendar');
      await tester.scrollUntilVisible(
        find.text('Chance of pregnancy'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await h.settle(1);
    }

    // ---- day 1 of the cycle (today): far before ovulation ----
    await showCalendarAtDay(0);
    final startShown = labelled('START OF CYCLE');
    final ovulationShown = labelled('OVULATION');
    final nextShown = labelled('NEXT CYCLE');
    final chanceDay1 = chance();
    h.note(
      'FT day1: start=$startShown ovulation=$ovulationShown next=$nextShown '
      'chance=$chanceDay1 | oracle start=${oracle.start} '
      'ovulation=${oracle.ovulation} next=${oracle.next}',
    );

    // ---- the Husband report agrees (PDF text, second surface) ----
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December', //
    ];
    String long(DateTime d) => '${monthNames[d.month - 1]} ${d.day}, ${d.year}';
    final ovulationDate = today.add(const Duration(days: 18));
    final expectedNext = long(today.add(const Duration(days: 32)));
    final expectedWindow =
        '${long(ovulationDate.subtract(const Duration(days: 5)))} - '
        '${long(ovulationDate.add(const Duration(days: 1)))}';
    await openTab('Profile');
    await h.scrollToExports();
    final husband = await h.openReportPdf('Husband Report');
    final husbandNext = husband?.contains(expectedNext) ?? false;
    final husbandWindow = husband?.contains(expectedWindow) ?? false;
    h.note(
      'FT husband report: next="$expectedNext" found=$husbandNext '
      'window="$expectedWindow" found=$husbandWindow',
    );

    // ---- Fiqh and Doctor reports state the same average cycle length ----
    await h.scrollToExports();
    final fiqhReport = await h.openReportPdf('Export Fiqh Log');
    await h.scrollToExports();
    final doctorReport = await h.openReportPdf("Export Doctor's Report");
    bool avg32(PdfText? pdf) =>
        pdf != null &&
        pdf.contains('Avg. cycle length') &&
        pdf.contains('32 days');
    final fiqhAvg = avg32(fiqhReport);
    final doctorAvg = avg32(doctorReport);
    h.note('FT reports: fiqhAvg32=$fiqhAvg doctorAvg32=$doctorAvg');

    // ---- ovulation day (cycle day 19): the peak ----
    await showCalendarAtDay(18);
    final ovulationAtPeak = labelled('OVULATION');
    final chancePeak = chance();
    h.note('FT day19 (ovulation): ovulation=$ovulationAtPeak chance=$chancePeak');

    // ---- 5 days before ovulation (cycle day 14): still in the window ----
    await showCalendarAtDay(13);
    final chanceDay14 = chance();
    h.note('FT day14: chance=$chanceDay14');

    AppClock.reset();
    final crashed = tester.takeException() != null;
    final datesOk =
        startShown == oracle.start &&
        ovulationShown == oracle.ovulation &&
        nextShown == oracle.next &&
        ovulationAtPeak == oracle.ovulation &&
        husbandNext &&
        husbandWindow &&
        fiqhAvg &&
        doctorAvg;
    final chanceOk =
        chanceDay1 == 'LOW' && chancePeak == 'HIGH' && chanceDay14 != 'LOW';
    h.reportResult(
      PersonaResult(
        testId: 'Batch14',
        expectedOutcome:
            'TTC-03: with cycle starts 32 days apart the Calendar shows '
            'START=${oracle.start} OVULATION=${oracle.ovulation} '
            'NEXT=${oracle.next}, and the chance is LOW on cycle day 1, '
            'HIGH on the ovulation day and not LOW inside the fertile window; '
            'the Husband report states next period $expectedNext and the '
            'fertility window $expectedWindow; the Fiqh and Doctor reports both '
            'state an average cycle length of 32 days',
        actualOutcome:
            'crashed=$crashed datesOk=$datesOk start=$startShown '
            'ovulation=$ovulationShown next=$nextShown | chanceOk=$chanceOk '
            'day1=$chanceDay1 day14=$chanceDay14 ovulationDay=$chancePeak | '
            'husbandReport(next=$husbandNext window=$husbandWindow) '
            'avgCycleLength32(fiqh=$fiqhAvg doctor=$doctorAvg)',
        status: (!crashed && datesOk && chanceOk)
            ? PersonaStatus.pass
            : PersonaStatus.fail,
      ),
    );
  });
}
