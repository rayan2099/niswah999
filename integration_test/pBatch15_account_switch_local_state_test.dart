import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/preferences/user_scoped_preferences.dart';
import 'package:niswah/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/flows.dart';
import 'support/flows_ext.dart';
import 'support/harness.dart';

/// Account switch and DEVICE-LOCAL state. Persona J proved a second account
/// sees none of the first account's server data; this covers what lives on the
/// device instead (SharedPreferences: marital status, TTC mode, pregnancy,
/// Madhhab, prayer city, reminder feed, today's mental-state check-in).
/// Account A sets all of them, signs out, and account B
/// (a different person on the same phone, skipping every optional question)
/// must see NONE of A's answers — on the real Profile and Today screens and in
/// the stored preferences themselves.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder switchFor(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(Container)),
    matching: find.byType(Switch),
  );

  testWidgets('Batch 15: a second account does not inherit the first '
      "account's device-local answers", (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch15')) return;
    final f = Flows(h);

    Future<void> openTab(String tab) async {
      await h.scrollToTop();
      await h.tapVisible(find.text(tab), last: true);
      await h.settle(2);
    }

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    bool on(String title) {
      final s = switchFor(title);
      return s.evaluate().isNotEmpty &&
          (s.evaluate().first.widget as Switch).value;
    }

    // ---------------- Account A: Hanafi, married, Riyadh, TTC, pregnant ----
    final emailA = await f.newAccountHanafiStillBleeding('LA');
    h.note('LOOKUP_EMAIL_A=$emailA');
    // A logs today's mental-state check-in, with a private note.
    final logButton = find.widgetWithText(OutlinedButton, 'Log');
    for (var i = 0; i < 12 && logButton.evaluate().isEmpty; i++) {
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -400),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
    await h.tapVisible(logButton);
    await h.settle(2);
    final noteField = find.byType(TextField);
    if (noteField.evaluate().isNotEmpty) {
      await tester.enterText(noteField.last, 'PRIVATE-NOTE-OF-A');
      await tester.pump(const Duration(milliseconds: 300));
    }
    await h.tapVisible(find.text('Save check-in'));
    await h.settle(2);
    final todayA = await texts('LA today after check-in');
    // Today shows the saved values ("Mood 3/5") — the "Log your mental state
    // now" prompt is always there, so it cannot be the marker.
    final aLogged = todayA.contains('/5');
    await openTab('Profile');
    if (!on('TTC Mode')) {
      await h.tapVisible(switchFor('TTC Mode'));
      await h.settle(2);
    }
    final pregSwitch = switchFor('I am currently pregnant');
    if (pregSwitch.evaluate().isNotEmpty) {
      await h.tapVisible(pregSwitch);
      await h.settle(2);
      await h.tapVisible(find.text('Week 12'));
      await h.settle(1);
      await h.tapVisible(find.byKey(const Key('pregnancy-setup-activate')));
      await tester.pump(const Duration(seconds: 3));
      await h.settle(2);
    }
    final profileA = await texts('LA profile');
    final aMarried = on('I am married');
    final aTtc = on('TTC Mode');
    final aPregnant = profileA.contains('Pregnancy tracking is active');
    final prefsA = await SharedPreferences.getInstance();
    final aRiyadh =
        prefsA.getString(
          UserScopedPreferences.key('niswah_prayer_location_label'),
        ) ==
        'Riyadh';
    h.note(
      'LA setup: married=$aMarried ttc=$aTtc pregnant=$aPregnant '
      'riyadh=$aRiyadh checkInLogged=$aLogged keys=${prefsA.getKeys().where((k) => k.startsWith("niswah_")).toList()..sort()}',
    );

    // ---------------- Sign out ----------------
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -2500),
      warnIfMissed: false,
    );
    await h.settle(1);
    final signOutTap = await h.tapVisible(find.textContaining('Sign Out'));
    await h.settle(2);
    if (find.textContaining('Sign Out').evaluate().isNotEmpty) {
      await h.tapVisible(find.textContaining('Sign Out'), last: true);
      await h.settle(2);
    }
    h.note('LA sign out tapped=$signOutTap');

    // ---------------- Account B: skips every optional question ----------
    final emailB = await f.newAccountOnDashboard('LB');
    h.note('LOOKUP_EMAIL_B=$emailB');
    final todayB = await texts('LB today');
    final bPregnancyOverview =
        todayB.contains('Log birth & start Nifas') ||
        todayB.contains('Pregnancy');
    // B has logged nothing today: she must see the empty check-in state, and
    // none of A's private note.
    final bSeesLeakedCheckIn =
        todayB.contains('/5') || todayB.contains('PRIVATE-NOTE-OF-A');
    await openTab('Profile');
    final profileB = await texts('LB profile');
    final bMarried = on('I am married');
    final bTtc = on('TTC Mode');
    final bPregnant = profileB.contains('Pregnancy tracking is active');
    final bRiyadh = profileB.contains('Riyadh');
    final bHanafi = profileB.contains('Hanafi');

    final prefsB = await SharedPreferences.getInstance();
    await prefsB.reload();
    // B's OWN stored values (namespaced) — and no leftover global key that
    // any account could read.
    final stored = <String, Object?>{
      for (final k in [
        'niswah_is_married',
        'niswah_ttc_mode_enabled',
        'niswah_is_pregnant',
        'niswah_prayer_location_label',
      ])
        k: prefsB.get(UserScopedPreferences.key(k)),
    };
    final globalLeftovers = [
      for (final k in [
        'niswah_is_married',
        'niswah_ttc_mode_enabled',
        'niswah_is_pregnant',
        'niswah_prayer_location_label',
        'dashboard_wellbeing_notes',
      ])
        if (prefsB.containsKey(k)) k,
    ];
    h.note(
      'LB after onboarding: married=$bMarried ttc=$bTtc pregnant=$bPregnant '
      'riyadh=$bRiyadh hanafi=$bHanafi todayPregnancyOverview='
      '$bPregnancyOverview seesAsCheckIn=$bSeesLeakedCheckIn stored=$stored '
      'globalLeftovers=$globalLeftovers',
    );

    final crashed = tester.takeException() != null;
    final setupOk = aMarried && aTtc && aRiyadh && aLogged && signOutTap;
    final isolated =
        !bMarried &&
        !bTtc &&
        !bPregnant &&
        !bRiyadh &&
        !bHanafi &&
        !bPregnancyOverview &&
        !bSeesLeakedCheckIn &&
        stored['niswah_is_married'] != true &&
        stored['niswah_ttc_mode_enabled'] != true &&
        stored['niswah_is_pregnant'] != true &&
        stored['niswah_prayer_location_label'] != 'Riyadh' &&
        globalLeftovers.isEmpty;
    h.reportResult(
      PersonaResult(
        testId: 'Batch15',
        expectedOutcome:
            'after account A (Hanafi, married, TTC, Riyadh, pregnant, a logged '
            'mental-state check-in with a note) signs out, account B on the '
            'same device sees none of those answers on Today/Profile or in '
            'the stored preferences, and no global key is left behind',
        actualOutcome:
            'crashed=$crashed setupOk=$setupOk(A married=$aMarried ttc=$aTtc '
            'pregnant=$aPregnant riyadh=$aRiyadh) isolated=$isolated '
            '(B married=$bMarried ttc=$bTtc pregnant=$bPregnant '
            'riyadh=$bRiyadh hanafi=$bHanafi '
            'pregnancyOverview=$bPregnancyOverview '
            'seesAsCheckIn=$bSeesLeakedCheckIn stored=$stored '
            'globalLeftovers=$globalLeftovers)',
        status: (!crashed && setupOk && isolated)
            ? PersonaStatus.pass
            : PersonaStatus.fail,
      ),
    );
  });
}
