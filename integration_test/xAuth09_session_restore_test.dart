import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/flows_ext.dart';
import 'support/harness.dart';

/// AUTH-09 — a signed-in session is restored after the app process is
/// really relaunched. One test file, two launches, driven by
/// scripts/run_session_restore.sh (deliberately NOT a `p*_test.dart`: it needs
/// two `flutter drive` runs that share one app container, which the hosted
/// single-run catalogue does not do):
///
///  * PHASE 1 (fresh install, no session): sign up, complete onboarding with a
///    still-going period, land on Today. Its result is written as FAIL
///    ("relaunch required") so that a run which never reaches phase 2 can
///    never be mistaken for a pass.
///  * PHASE 2 (the SAME install, the app process killed and started again, app
///    data kept): a session must already exist before any tap, the app must
///    open straight on Today with the account's open episode (loaded from the
///    server as the restored user), and the account must be the one created
///    by phase 1 (matching persona prefix, created well before this launch).
///    The result written here is the one that counts.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AUTH-09: session restore across a real app relaunch', (
    tester,
  ) async {
    final launchedAt = DateTime.now().toUtc();
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('AUTH09')) return;
    final f = Flows(h);

    // Let the app read its persisted session (if any) before deciding.
    await tester.pump(const Duration(seconds: 6));
    await h.settle(2);
    final client = NiswahSupabase.clientOrNull;
    final restored = client?.auth.currentSession != null;

    if (!restored) {
      // ---------------- PHASE 1 ----------------
      final email = await f.newAccountHanafiStillBleeding('S9');
      h.note('LOOKUP_EMAIL=$email');
      h.dumpTexts('S9 phase1 dashboard');
      final onToday =
          h.notes.last.contains('Daily check-in') ||
          h.notes.last.contains('Bleeding recorded') ||
          h.notes.last.contains('Day ');
      final uid = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
      h.note('S9 phase1: uid=$uid onToday=$onToday');
      h.reportResult(
        PersonaResult(
          testId: 'AUTH09',
          expectedOutcome:
              'a session created before the relaunch is restored after it',
          actualOutcome:
              'PHASE 1 ONLY (signedUp=${uid != null} onToday=$onToday): the '
              'app must now be relaunched with its data kept — this result '
              'is replaced by phase 2 and never counts as a pass',
          status: PersonaStatus.fail,
        ),
      );
      return;
    }

    // ---------------- PHASE 2 ----------------
    final user = client!.auth.currentUser!;
    final email = user.email ?? '';
    final createdAt = DateTime.tryParse(user.createdAt)?.toUtc();
    final ageSeconds = createdAt == null
        ? -1
        : launchedAt.difference(createdAt).inSeconds;
    h.note('LOOKUP_EMAIL=$email');
    h.note(
      'S9 phase2: restored session for $email, account age ${ageSeconds}s',
    );

    // The app must be showing Today, not the auth screens or onboarding.
    await tester.pump(const Duration(seconds: 3));
    await h.settle(2);
    h.dumpTexts('S9 phase2 first screen');
    final first = h.notes.last;
    final onToday =
        first.contains('Daily check-in') ||
        first.contains('Bleeding recorded') ||
        first.contains('Day ');
    final onAuthScreen =
        first.contains('Sign In') && first.contains('Password') ||
        first.contains('Create Account') ||
        first.contains('Get Started');

    // Server state loads as the restored user (RLS: only their own rows).
    List<dynamic> openEpisodes = const [];
    String? readError;
    try {
      openEpisodes = await client
          .from('bleeding_episodes')
          .select('id')
          .eq('user_id', user.id)
          .eq('lifecycle_status', 'open');
    } catch (e) {
      readError = e.runtimeType.toString();
    }

    // GoTrue stores emails lower-cased.
    final fromPhase1 =
        email.toLowerCase().startsWith('s9.') && ageSeconds >= 30;
    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        restored &&
        fromPhase1 &&
        onToday &&
        !onAuthScreen &&
        openEpisodes.length == 1 &&
        readError == null;
    h.reportResult(
      PersonaResult(
        testId: 'AUTH09',
        expectedOutcome:
            'after the app process is killed and relaunched with its data '
            'kept, the session exists before any tap, the app opens on Today '
            '(not sign-in/onboarding) and the account\'s open episode loads',
        actualOutcome:
            'crashed=$crashed restoredBeforeTap=$restored '
            'accountFromPhase1=$fromPhase1(age=${ageSeconds}s) onToday=$onToday '
            'authScreenShown=$onAuthScreen openEpisodes=${openEpisodes.length} '
            'readError=$readError',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
      ),
    );
  });
}
