import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 batch 2 — onboarding taken with EXPLICIT answers instead of the
/// "skip/I'm not sure" path every earlier persona used: ONB-01 (explicit
/// Madhhab), ONB-03 (explicit marital status), ONB-05 (manual city),
/// ONB-09 (period still going), ONB-11 (anonymous mode explicitly ON).
/// Each is asserted against BOTH what the real screens then show and what
/// the server actually persisted (the signed-in user's own `users` row,
/// which RLS permits), never on a screenshot.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch 2: explicit onboarding answers are honoured and '
      'persisted', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch2')) return;
    final f = Flows(h);

    await f.boot();
    final email = await f.signUpWithEmail('O');
    h.note('LOOKUP_EMAIL=$email');
    await h.tapVisible(find.text('Create Account'));
    await h.waitFor(
      find.text('Get Started'),
      timeout: const Duration(seconds: 25),
    );

    // --- Madhhab: explicit Hanafi ---
    await h.settle(2);
    h.dumpTexts('O madhhab step');
    final pickedMadhhab = await h.tapVisible(find.text('Hanafi'));
    await h.settle(1);
    final continuedMadhhab = await h.tapVisible(find.text('Continue'));
    h.note('O madhhab: picked=$pickedMadhhab continued=$continuedMadhhab');
    await h.settle(2);

    // --- Marital status: explicit Yes ---
    h.dumpTexts('O marital step');
    final pickedMarried = await h.tapVisible(find.text('Yes'));
    await h.settle(1);
    final continuedMarried = await h.tapVisible(find.text('Continue'));
    h.note('O marital: yes=$pickedMarried continued=$continuedMarried');
    await h.settle(2);

    // --- Location: manual city pick ---
    h.dumpTexts('O location step');
    final pickedCity = await h.tapVisible(find.text('Riyadh'));
    h.note('O location: Riyadh picked=$pickedCity');
    await tester.pump(const Duration(seconds: 2));
    await h.settle(2);

    // --- Last period: 3 days ago, and it is still going ---
    h.dumpTexts('O period-start step');
    final openedStart = await h.tapVisible(find.text('Select the date'));
    var pickedStart = false;
    if (openedStart) {
      await h.settle(1);
      await h.tapVisible(find.byTooltip('Switch to input'));
      await h.settle(1);
      final field = find.byType(TextField);
      if (field.evaluate().isNotEmpty) {
        final d = DateTime.now().subtract(const Duration(days: 3));
        final typed =
            '${d.month.toString().padLeft(2, '0')}/'
            '${d.day.toString().padLeft(2, '0')}/${d.year}';
        await tester.enterText(field.first, typed);
        await tester.pump(const Duration(milliseconds: 300));
        pickedStart = await h.tapVisible(find.text('OK'));
        await h.settle(1);
      }
    }
    await h.tapVisible(find.text('Continue'));
    await h.settle(2);
    h.dumpTexts('O still-happening step');
    final stillGoing = await h.tapVisible(find.text('Yes, still going'));
    h.note('O period: startPicked=$pickedStart stillGoing=$stillGoing');
    await h.settle(2);

    // --- usual duration / cycle length ---
    for (final value in ['5', '28']) {
      h.dumpTexts('O number step ($value)');
      final field = find.byType(TextField);
      if (field.evaluate().isNotEmpty) {
        await tester.enterText(field.first, value);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await h.tapVisible(find.text('Continue'));
      await h.settle(2);
    }

    // --- Anonymous Mode: explicitly ON ---
    h.dumpTexts('O anonymous-mode step');
    final anon = find.text('Hide my identity');
    var anonToggled = false;
    if (anon.evaluate().isNotEmpty) {
      anonToggled = await h.tapVisible(anon);
    }
    await h.settle(1);
    await h.shot('O', 'anonymous_step_after_toggle');
    await h.tapVisible(find.text('Continue'));
    await h.settle(2);
    h.note('O anonymous toggled=$anonToggled');

    await h.tapVisible(find.text('Get Started'));
    await h.settle(3);
    await h.scrollToTop();
    await h.settle(1);
    await h.shot('O', 'dashboard_after_explicit_onboarding');
    h.dumpTexts('O dashboard');
    final dash = h.notes.last;
    final openEpisodeShown =
        dash.contains('Bleeding recorded') ||
        dash.contains('Daily check-in') ||
        dash.contains('Day 4');
    h.note('O dashboard shows the open (still-going) episode: $openEpisodeShown');

    // --- Server-side truth: the user's own persisted row ---
    Map<String, dynamic>? userRow;
    final client = NiswahSupabase.clientOrNull;
    final uid = client?.auth.currentUser?.id;
    if (client != null && uid != null) {
      try {
        userRow = await client
            .from('users')
            .select('madhhab, anonymous_mode')
            .eq('id', uid)
            .maybeSingle();
      } catch (e) {
        h.note('O users row read failed: ${e.runtimeType}');
      }
    }
    h.note('O persisted users row: $userRow');
    final madhhabPersisted =
        (userRow?['madhhab'] as String?)?.toUpperCase() == 'HANAFI';
    final anonymousPersisted = userRow?['anonymous_mode'] == true;

    // --- Profile reflects the explicit answers ---
    await h.tapVisible(find.text('Profile'));
    await h.settle(2);
    h.dumpTexts('O profile');
    final profile = h.notes.last;
    final profileShowsRiyadh = profile.contains('Riyadh');
    final marriedSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('I am married'),
        matching: find.byType(Container),
      ),
      matching: find.byType(Switch),
    );
    final marriedOn = marriedSwitch.evaluate().isNotEmpty &&
        (marriedSwitch.evaluate().first.widget as Switch).value;
    h.note(
      'O profile: riyadh=$profileShowsRiyadh marriedSwitchOn=$marriedOn '
      'madhhabPersisted=$madhhabPersisted anonymousPersisted='
      '$anonymousPersisted',
    );
    await h.shot('O', 'profile_after_explicit_onboarding');

    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        pickedMadhhab &&
        pickedMarried &&
        pickedCity &&
        stillGoing &&
        openEpisodeShown &&
        madhhabPersisted &&
        anonymousPersisted &&
        profileShowsRiyadh &&
        marriedOn;
    h.reportResult(
      PersonaResult(
        testId: 'Batch2',
        expectedOutcome:
            'ONB-01/03/05/09/11: explicit Madhhab (Hanafi), marital (Yes), '
            'city (Riyadh), a still-going period and Anonymous Mode ON '
            'are each reflected on the real screens AND persisted',
        actualOutcome:
            'crashed=$crashed madhhab(picked=$pickedMadhhab '
            'persisted=$madhhabPersisted) married(picked=$pickedMarried '
            'switchOn=$marriedOn) city(picked=$pickedCity '
            'profile=$profileShowsRiyadh) stillGoing=$stillGoing '
            'openEpisodeShown=$openEpisodeShown anonymous(toggled='
            '$anonToggled persisted=$anonymousPersisted)',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'O_profile_after_explicit_onboarding.png',
      ),
    );
  });
}
