import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 batch 4 — Profile privacy controls and the irreversible
/// account-deletion journey, disposable account only:
///  * PROF-01 Anonymous Mode: toggling ON changes the profile identity and
///    is PERSISTED server-side (`users.anonymous_mode`); OFF restores it.
///  * PROF-03 Privacy Policy: the real policy screen opens with real text.
///  * AUTH-11 / PROF-05 Account deletion: confirm dialog -> real deletion
///    -> the app returns to signed-out, the session is gone, and the same
///    credentials are REJECTED by the server (the account truly no
///    longer exists). The host-side follow-up
///    (scripts/check_account_deletion_cascade.sh + the run's
///    LOOKUP_EMAIL) verifies no row survives in any table.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch 4: anonymous mode, privacy policy, account deletion', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch4')) return;
    final f = Flows(h);

    final email = await f.newAccountOnDashboard('P');
    h.note('LOOKUP_EMAIL=$email');
    await f.startBleedingToday('P'); // real data that deletion must remove

    final client = NiswahSupabase.clientOrNull;
    final uid = client?.auth.currentUser?.id;
    Future<bool?> anonymousPersisted() async {
      if (client == null || uid == null) return null;
      try {
        final row = await client
            .from('users')
            .select('anonymous_mode')
            .eq('id', uid)
            .maybeSingle();
        return row?['anonymous_mode'] as bool?;
      } catch (_) {
        return null;
      }
    }

    Finder switchFor(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Container)),
      matching: find.byType(Switch),
    );

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    await h.scrollToTop();
    await h.tapVisible(find.text('Profile'), last: true);
    await h.settle(2);
    final profileBefore = await texts('P profile (anonymous off)');

    // ---------------- PROF-01: Anonymous Mode ----------------
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await h.settle(1);
    final anonBefore = await anonymousPersisted();
    var anonOnToggled = false;
    if (switchFor('Anonymous Mode').evaluate().isNotEmpty) {
      await h.tapVisible(switchFor('Anonymous Mode'));
      await h.settle(3);
      anonOnToggled = true;
    }
    final anonAfterOn = await anonymousPersisted();
    await h.scrollToTop();
    final profileAnon = await texts('P profile header (anonymous ON)');
    final identityChanged = !profileAnon.contains('Persona P');
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await h.settle(1);
    if (switchFor('Anonymous Mode').evaluate().isNotEmpty) {
      await h.tapVisible(switchFor('Anonymous Mode'));
      await h.settle(3);
    }
    final anonAfterOff = await anonymousPersisted();
    await h.scrollToTop();
    final profileRestored = await texts('P profile header (anonymous OFF again)');
    final restored = profileRestored.contains('Persona P');
    final prof01 =
        anonOnToggled &&
        identityChanged &&
        anonBefore == false &&
        anonAfterOn == true &&
        anonAfterOff == false &&
        restored;
    h.note(
      'P PROF-01 pass=$prof01 persisted before=$anonBefore on=$anonAfterOn '
      'off=$anonAfterOff identityChanged=$identityChanged restored=$restored',
    );

    // ---------------- PROF-03: Privacy Policy ----------------
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await h.settle(1);
    final openedPolicy = await h.tapVisible(find.text('Privacy Policy'));
    await h.settle(2);
    await h.shot('P', 'privacy_policy');
    final policyTexts = await texts('P privacy policy screen');
    final policyHasContent = policyTexts.length > 400;
    h.note('P PROF-03 opened=$openedPolicy contentChars=${policyTexts.length}');
    // Leave the policy screen the way a user would.
    if (find.byType(BackButton).evaluate().isNotEmpty) {
      await h.tapVisible(find.byType(BackButton));
    } else if (find.byType(CloseButton).evaluate().isNotEmpty) {
      await h.tapVisible(find.byType(CloseButton));
    } else if (find.byIcon(Icons.arrow_back).evaluate().isNotEmpty) {
      await h.tapVisible(find.byIcon(Icons.arrow_back));
    } else if (find.byIcon(Icons.arrow_back_ios_new).evaluate().isNotEmpty) {
      await h.tapVisible(find.byIcon(Icons.arrow_back_ios_new));
    }
    await h.settle(2);
    final prof03 = openedPolicy && policyHasContent;

    // ---------------- AUTH-11 / PROF-05: delete the account ----------------
    await h.scrollToTop();
    await h.tapVisible(find.text('Profile'), last: true);
    await h.settle(2);
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -3000),
      warnIfMissed: false,
    );
    await h.settle(1);
    final tappedDelete = await h.tapVisible(find.text('Delete Account'));
    await h.settle(2);
    final dialogTexts = await texts('P delete dialog');
    final dialogShown = dialogTexts.contains('Delete your account?');
    await h.shot('P', 'delete_confirmation');
    // The dialog's destructive button is labelled exactly "Delete".
    final tappedConfirm = await h.tapVisible(find.text('Delete'), last: true);
    await tester.pump(const Duration(seconds: 6));
    await h.settle(3);
    await h.shot('P', 'after_delete');
    final afterDelete = await texts('P after deletion');
    final backToSignedOut =
        afterDelete.contains('Understand your cycle') ||
        afterDelete.contains('Sign In') ||
        afterDelete.contains('Email');
    final sessionGone = NiswahSupabase.clientOrNull?.auth.currentSession == null;

    // The server must now REJECT the same credentials: the user is gone.
    var serverRejectsCredentials = false;
    try {
      await NiswahSupabase.clientOrNull?.auth.signInWithPassword(
        email: email,
        password: 'Test-Pass-12345',
      );
    } catch (e) {
      serverRejectsCredentials = e.toString().contains('Invalid login');
    }
    final auth11 =
        tappedDelete &&
        dialogShown &&
        tappedConfirm &&
        backToSignedOut &&
        sessionGone &&
        serverRejectsCredentials;
    h.note(
      'P AUTH-11/PROF-05 pass=$auth11 dialog=$dialogShown confirmed='
      '$tappedConfirm signedOut=$backToSignedOut sessionGone=$sessionGone '
      'serverRejects=$serverRejectsCredentials',
    );
    // Sanity that the profile page really showed the pre-state.
    h.note('P profile before had Persona P: ${profileBefore.contains('Persona P')}');

    final crashed = tester.takeException() != null;
    final pass = !crashed && prof01 && prof03 && auth11;
    h.reportResult(
      PersonaResult(
        testId: 'Batch4',
        expectedOutcome:
            'PROF-01 Anonymous Mode changes identity and persists; PROF-03 '
            'Privacy Policy opens with real text; AUTH-11/PROF-05 account '
            'deletion signs out and the server rejects the credentials',
        actualOutcome:
            'crashed=$crashed prof01=$prof01 prof03=$prof03 '
            'auth11_prof05=$auth11 (delete: dialog=$dialogShown '
            'signedOut=$backToSignedOut sessionGone=$sessionGone '
            'serverRejects=$serverRejectsCredentials)',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'P_after_delete.png',
      ),
    );
  });
}
