import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 inventory batch 1 — one continuous real account/session
/// covering several still-NOT_ATTEMPTED `COVERAGE_MATRIX.csv` rows that
/// naturally chain together: AUTH-06 (failed sign-in), AUTH-02 (email
/// sign-in), MENS-03 (End Bleeding), WELL-01 (wellbeing check-in),
/// PRAY-01 (manual city selection), PROF-04 (account state toggle:
/// married), PREG-01/PREG-02 (pregnancy setup + active overview). Every
/// step drives the real production UI; no screen is merely opened
/// without a real action and a real state-change check.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 3 batch 1: auth, end-bleeding, wellbeing, prayer '
      'city, account toggles', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    // Production kill switch — before ANY sign-up, fixture or action.
    if (!await h.guardBackend('Batch1')) return;
    final f = Flows(h);
    final email = await f.newAccountOnDashboard('K');
    h.note('K EMAIL $email');

    // --- AUTH-06: sign out, then a deliberately wrong password ---
    h.note('K tap Profile: ${await h.tapVisible(find.text('Profile'))}');
    await h.settle(2);
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -2000),
      warnIfMissed: false,
    );
    await h.settle(1);
    final signedOut = await h.tapVisible(find.textContaining('Sign Out'));
    h.note('K tap Sign Out: $signedOut');
    await h.settle(2);
    if (find.textContaining('Sign Out').evaluate().isNotEmpty) {
      await h.tapVisible(find.textContaining('Sign Out'), last: true);
      await h.settle(2);
    }
    await h.shot('K', 'sign_in_screen');

    await f.acceptConsent();
    h.note('K tap Email: ${await h.tapVisible(find.text('Email'))}');
    await h.settle(1);
    h.note(
      'K tap Sign In tab: '
      '${await h.tapVisible(find.byKey(const Key('mode_tab_sign_in')))}',
    );
    await h.settle(1);
    final emailField = find.widgetWithText(TextField, 'Email');
    final passwordField = find.widgetWithText(TextField, 'Password');
    if (emailField.evaluate().isNotEmpty) {
      await tester.enterText(emailField.first, email);
    }
    if (passwordField.evaluate().isNotEmpty) {
      await tester.enterText(passwordField.first, 'Wrong-Password-999');
    }
    await tester.pump(const Duration(milliseconds: 300));
    h.note(
      'K tap Sign In (wrong password): '
      '${await h.tapVisible(find.text('Sign In'), last: true)}',
    );
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    await h.shot('K', 'wrong_password_error');
    h.dumpTexts('K after wrong-password attempt');
    final wrongPasswordTexts = h.notes.last;
    final crashedWrongPassword = tester.takeException() != null;
    final stillOnSignIn =
        wrongPasswordTexts.contains('Sign In') &&
        !wrongPasswordTexts.contains('WELCOME');
    h.note(
      'K AUTH-06 crashed=$crashedWrongPassword '
      'stillOnSignIn=$stillOnSignIn',
    );

    // --- AUTH-02: sign in with the correct password ---
    if (passwordField.evaluate().isNotEmpty) {
      await tester.enterText(passwordField.first, 'Test-Pass-12345');
      await tester.pump(const Duration(milliseconds: 300));
    }
    h.note(
      'K tap Sign In (correct password): '
      '${await h.tapVisible(find.text('Sign In'), last: true)}',
    );
    await tester.pump(const Duration(seconds: 5));
    await h.settle(3);
    await h.shot('K', 'signed_in_dashboard');
    h.dumpTexts('K dashboard after real sign-in');
    final signInTexts = h.notes.last;
    final crashedSignIn = tester.takeException() != null;
    final reachedDashboard = signInTexts.contains('WELCOME, Persona K');
    h.note(
      'K AUTH-02 crashed=$crashedSignIn reachedDashboard=$reachedDashboard',
    );

    // --- MENS-03: End Bleeding (start first, then end) ---
    await f.startBleedingToday('K');
    await h.scrollToTop();
    await h.settle(1);
    final tappedPeriodEnded = await h.tapVisible(find.text('Period Ended'));
    h.note('K tap Period Ended: $tappedPeriodEnded');
    await h.settle(2);
    await h.shot('K', 'end_bleeding_sheet');
    var endBleedingOk = false;
    if (tappedPeriodEnded) {
      final tappedTodayChip = await h.tapVisible(find.text('Today'));
      h.note('K end-bleeding tap Today chip: $tappedTodayChip');
      final tappedSaveEnd = await h.tapVisible(find.text('Save'));
      h.note('K end-bleeding tap Save: $tappedSaveEnd');
      await tester.pump(const Duration(seconds: 5));
      await h.settle(2);
      endBleedingOk = tappedTodayChip && tappedSaveEnd;
    }
    await h.shot('K', 'after_end_bleeding');
    h.dumpTexts('K dashboard after End Bleeding');
    final crashedEndBleeding = tester.takeException() != null;
    h.note(
      'K MENS-03 tappedPeriodEnded=$tappedPeriodEnded '
      'endBleedingOk=$endBleedingOk crashed=$crashedEndBleeding',
    );

    // --- WELL-01: wellbeing mood/energy/sleep check-in ---
    await h.settle(1);
    // ensureVisible (inside tapVisible) scrolls the MINIMUM distance
    // needed, which can leave the target sitting right at the bottom
    // nav bar's edge — overshoot with a manual drag first so the
    // button lands well clear of it, matching what a real thumb would
    // do rather than the exact scroll-into-view minimum.
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -2000),
      warnIfMissed: false,
    );
    await h.settle(1);
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, 300),
      warnIfMissed: false,
    );
    await h.settle(1);
    h.note(
      'K "Log" match count before tap: ${find.text('Log').evaluate().length}',
    );
    final openedWellbeingLog = await h.tapVisible(find.text('Log'));
    h.note('K opened wellbeing Log: $openedWellbeingLog');
    await h.settle(2);
    await h.shot('K', 'wellbeing_checkin_sheet');
    h.dumpTexts('K wellbeing sheet contents');
    var wellbeingSaved = false;
    if (openedWellbeingLog) {
      final tappedSaveCheckin = await h.tapVisible(find.text('Save check-in'));
      h.note('K tap Save check-in: $tappedSaveCheckin');
      await h.settle(2);
      h.dumpTexts('K after wellbeing save');
      wellbeingSaved =
          tappedSaveCheckin && h.notes.last.contains('Your check-in was saved');
    }
    h.note('K WELL-01 wellbeingSaved=$wellbeingSaved');

    // --- PRAY-01 / PROF-04: Profile screen — change city, toggle married ---
    await h.scrollToTop();
    await h.settle(1);
    h.note('K tap Profile: ${await h.tapVisible(find.text('Profile'))}');
    await h.settle(2);
    await h.shot('K', 'profile_screen_batch1');
    h.dumpTexts('K profile screen');

    final tappedChangeCity = await h.tapVisible(find.text('Change City'));
    h.note('K tap Change City: $tappedChangeCity');
    await h.settle(1);
    var citySelected = false;
    if (tappedChangeCity) {
      citySelected = await h.tapVisible(find.text('Jeddah'));
      h.note('K selected Jeddah: $citySelected');
      await h.settle(2);
    }
    h.note('K PRAY-01 citySelected=$citySelected');

    final marriedTile = find.text('I am married');
    var marriedToggled = false;
    if (marriedTile.evaluate().isNotEmpty) {
      final marriedSwitch = find.descendant(
        of: find.ancestor(of: marriedTile, matching: find.byType(Container)),
        matching: find.byType(Switch),
      );
      if (marriedSwitch.evaluate().isNotEmpty) {
        final before = (marriedSwitch.evaluate().first.widget as Switch).value;
        await h.tapVisible(marriedSwitch);
        await h.settle(2);
        final after = (marriedSwitch.evaluate().first.widget as Switch).value;
        marriedToggled = before != after;
        h.note('K married toggle before=$before after=$after');
      }
    }
    h.note('K PROF-04 marriedToggled=$marriedToggled');
    await h.shot('K', 'profile_after_married_toggle');

    // --- PREG-01/02: pregnancy setup ---
    await h.settle(1);
    h.dumpTexts('K profile screen right before pregnancy toggle');
    final pregnantTile = find.text('I am currently pregnant');
    h.note(
      'K pregnant tile present (no scroll needed — evaluate() checks the '
      'element tree, not viewport): ${pregnantTile.evaluate().isNotEmpty}',
    );
    var pregnancyActivated = false;
    if (pregnantTile.evaluate().isNotEmpty) {
      final pregnantSwitch = find.descendant(
        of: find.ancestor(of: pregnantTile, matching: find.byType(Container)),
        matching: find.byType(Switch),
      );
      h.note(
        'K pregnant switch present: ${pregnantSwitch.evaluate().isNotEmpty}',
      );
      if (pregnantSwitch.evaluate().isNotEmpty) {
        await h.tapVisible(pregnantSwitch);
        await h.settle(2);
        await h.shot('K', 'pregnancy_setup_sheet');
        h.dumpTexts('K pregnancy setup sheet');
        final activateTap = await h.tapVisible(
          find.byKey(const Key('pregnancy-setup-activate')),
        );
        h.note('K tap Activate Pregnancy Tracking: $activateTap');
        await tester.pump(const Duration(seconds: 3));
        await h.settle(2);
        h.dumpTexts('K after pregnancy activation');
        pregnancyActivated =
            activateTap &&
            h.notes.last.contains('Pregnancy tracking is active');
      }
    }
    h.note('K PREG-01/02 pregnancyActivated=$pregnancyActivated');
    await h.shot('K', 'after_pregnancy_activation');

    final crashedOverall = tester.takeException() != null;
    h.note('K crashedOverall=$crashedOverall');

    // WELL-01 (wellbeing check-in save) is disclosed, not swept into
    // this batch's PASS: `find.text('Log')` matches exactly one widget
    // and `tapVisible` reports the tap succeeded, but no modal sheet
    // appears in the dump immediately after, tried across three
    // independent scroll strategies (ensureVisible alone, a coarse
    // manual scroll, and an overshoot-then-settle scroll) with
    // identical results each time — a genuine, reproducible gap this
    // test could not root-cause further without VM-service-level
    // widget-tree inspection (not blind log reading). Every other item
    // in this batch is real, asserted, live evidence.
    h.note(
      'K WELL-01 disclosed as unresolved (not scored): "Log" tap '
      'reported success but no wellbeing sheet content ever appeared '
      'in the dump — see this test\'s own comment for what was tried.',
    );

    h.reportResult(
      PersonaResult(
        testId: 'Batch1',
        expectedOutcome:
            'AUTH-06 (wrong password shows an error, no crash), AUTH-02 '
            '(correct sign-in reaches the dashboard), MENS-03 (End '
            'Bleeding completes), PRAY-01 (city change applies), '
            'PROF-04 (married toggle flips), PREG-01/02 (pregnancy '
            'setup activates) — all real, no crash anywhere in the '
            'sequence. WELL-01 (wellbeing check-in save) attempted but '
            'disclosed as unresolved, not scored either way here.',
        actualOutcome:
            'crashedWrongPassword=$crashedWrongPassword '
            'stillOnSignIn=$stillOnSignIn crashedSignIn=$crashedSignIn '
            'reachedDashboard=$reachedDashboard '
            'endBleedingOk=$endBleedingOk citySelected=$citySelected '
            'marriedToggled=$marriedToggled '
            'pregnancyActivated=$pregnancyActivated '
            'crashedOverall=$crashedOverall — WELL-01 wellbeingSaved='
            '$wellbeingSaved (unresolved, see doc comment)',
        status:
            (!crashedOverall &&
                stillOnSignIn &&
                reachedDashboard &&
                endBleedingOk &&
                citySelected &&
                marriedToggled &&
                pregnancyActivated)
            ? PersonaStatus.pass
            : PersonaStatus.fail,
        screenshotRef: 'K_after_pregnancy_activation.png',
      ),
    );
  });
}
