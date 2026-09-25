import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 batch 3 — TTC, pregnancy and Nifas, all through the real
/// Profile toggles and the real screens they change, with the behavior
/// each is documented to have (read from the code, not guessed):
///  * TTC-01: TTC on + NOT married -> Calendar explains what is missing
///    ("Turn on "I am married"...") and shows NO pregnancy chance.
///  * TTC-02/03: TTC on + married + >= 2 cycle starts -> Calendar shows
///    "Chance of pregnancy" and stops showing the requirements notice.
///  * PREG-02/03: pregnancy setup at a chosen week -> the Today overview.
///  * PREG-04: "Log birth & start Nifas" -> the Nifas status card.
///  * NIFAS-01/02/04: Postpartum toggle starts/ends Nifas and the card
///    appears/disappears.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder switchFor(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(Container)),
    matching: find.byType(Switch),
  );

  testWidgets('Batch 3: TTC gating, pregnancy overview, birth -> Nifas, '
      'Nifas end', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch3')) return;
    final f = Flows(h);

    // Real history: a completed period ~32 days ago + a start today, so
    // the account genuinely has two cycle starts (TTC needs them).
    final email = await f.newAccountWithRealHistory('T');
    h.note('LOOKUP_EMAIL=$email');
    await f.startBleedingToday('T');

    Future<bool> toggle(String title) async {
      final s = switchFor(title);
      if (s.evaluate().isEmpty) return false;
      final before = (s.evaluate().first.widget as Switch).value;
      await h.tapVisible(s);
      await h.settle(2);
      final after = (switchFor(title).evaluate().first.widget as Switch).value;
      return before != after;
    }

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    Future<void> openTab(String tab) async {
      await h.scrollToTop();
      await h.tapVisible(find.text(tab), last: true);
      await h.settle(2);
    }

    // ---------------- TTC-01: on while NOT married ----------------
    await openTab('Profile');
    final ttcOn1 = await toggle('TTC Mode');
    await openTab('Calendar');
    final calUnmarried = await texts('T calendar: TTC on, unmarried');
    final ttc01 =
        ttcOn1 &&
        calUnmarried.contains('Turn on "I am married"') &&
        !calUnmarried.contains('Chance of pregnancy');
    h.note('T TTC-01 pass=$ttc01 (toggled=$ttcOn1)');
    await h.shot('T', 'calendar_ttc_unmarried');

    // ---------------- TTC-02/03: married + TTC + history ----------------
    await openTab('Profile');
    final marriedOn = await toggle('I am married');
    await openTab('Calendar');
    final calMarried = await texts('T calendar: TTC on, married');
    final ttc02 =
        marriedOn &&
        calMarried.contains('Chance of pregnancy') &&
        !calMarried.contains('Turn on "I am married"');
    h.note('T TTC-02/03 pass=$ttc02 (marriedToggled=$marriedOn)');
    await h.shot('T', 'calendar_ttc_married');

    // TTC off again — the card must go away with it.
    await openTab('Profile');
    final ttcOff = await toggle('TTC Mode');
    await openTab('Calendar');
    final calTtcOff = await texts('T calendar: TTC off');
    final ttcOffOk = ttcOff && !calTtcOff.contains('Chance of pregnancy');
    h.note('T TTC off removes the card: $ttcOffOk');

    // ---------------- PREG-02/03: pregnancy at week 12 ----------------
    await openTab('Profile');
    final pregSwitch = switchFor('I am currently pregnant');
    var pregnancyActive = false;
    if (pregSwitch.evaluate().isNotEmpty) {
      await h.tapVisible(pregSwitch);
      await h.settle(2);
      await h.tapVisible(find.text('Week 12'));
      await h.settle(1);
      await h.shot('T', 'pregnancy_setup_week12');
      await h.tapVisible(find.byKey(const Key('pregnancy-setup-activate')));
      await tester.pump(const Duration(seconds: 3));
      await h.settle(2);
      pregnancyActive = (await texts('T profile after pregnancy')).contains(
        'Pregnancy tracking is active',
      );
    }
    await openTab('Today');
    final todayPregnant = await texts('T Today while pregnant');
    final overviewShowsWeek =
        todayPregnant.contains('12') &&
        todayPregnant.contains('Log birth & start Nifas');
    h.note(
      'T PREG-02/03 active=$pregnancyActive overviewWeek12=$overviewShowsWeek',
    );
    await h.shot('T', 'today_pregnancy_overview');

    // ---------------- PREG-04: log birth -> Nifas ----------------
    final tappedBirth = await h.tapVisible(
      find.text('Log birth & start Nifas'),
    );
    await h.settle(2);
    h.dumpTexts('T after tapping Log birth');
    // A confirmation dialog may appear.
    for (final label in ['Confirm', 'Yes', 'Start Nifas', 'Save', 'OK']) {
      if (find.text(label).evaluate().isNotEmpty) {
        await h.tapVisible(find.text(label), last: true);
        await h.settle(2);
        break;
      }
    }
    await tester.pump(const Duration(seconds: 3));
    await h.settle(2);
    await h.scrollToTop();
    final todayNifas = await texts('T Today after birth');
    final nifasStarted =
        todayNifas.contains('NIFAS') &&
        todayNifas.contains('Nifas tracking started') &&
        todayNifas.contains('salah is lifted while bleeding continues') &&
        !todayNifas.contains('Log birth & start Nifas');
    h.note('T PREG-04/NIFAS-01/02 tappedBirth=$tappedBirth nifas=$nifasStarted');
    await h.shot('T', 'today_nifas');

    // ---------------- NIFAS-04: end Nifas ----------------
    await openTab('Profile');
    final nifasOff = await toggle('Postpartum Mode (Nifas)');
    await openTab('Today');
    final todayAfter = await texts('T Today after Nifas ended');
    final nifasEnded = nifasOff && !todayAfter.contains('Nifas tracking started');
    h.note('T NIFAS-04 ended=$nifasEnded (toggled=$nifasOff)');

    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        ttc01 &&
        ttc02 &&
        ttcOffOk &&
        pregnancyActive &&
        overviewShowsWeek &&
        nifasStarted &&
        nifasEnded;
    h.reportResult(
      PersonaResult(
        testId: 'Batch3',
        expectedOutcome:
            'TTC-01/02/03 gating, PREG-02/03/04 overview + birth, '
            'NIFAS-01/02/04 start/end — each changes the real screens as '
            'documented',
        actualOutcome:
            'crashed=$crashed ttc01_unmarriedRestriction=$ttc01 '
            'ttc02_marriedChance=$ttc02 ttcOffRemoves=$ttcOffOk '
            'pregnancyActive=$pregnancyActive overviewWeek12='
            '$overviewShowsWeek nifasStartedAfterBirth=$nifasStarted '
            'nifasEnded=$nifasEnded',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'T_today_nifas.png',
      ),
    );
  });
}
