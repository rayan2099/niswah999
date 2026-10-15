import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/harness.dart';

/// STAGING-ONLY, MANUAL-INVOCATION LIVE ACCEPTANCE TEST — not part of the
/// normal `flutter test` suite or CI; see the matching banner in
/// `live_acceptance_geo_madhhab_test.dart` for the full explanation of why
/// (not discovered by a bare `flutter test`, requires explicit
/// `--dart-define` credentials never embedded in this file, refuses
/// immediately and safely if either is missing or the backend isn't
/// exactly the known staging host).
///
/// One-shot setup step for the onboarding-parity live acceptance test
/// (`live_acceptance_onboarding_parity_test.dart`). Runs as its own
/// `flutter test` process, BEFORE that one, for exactly one reason: the
/// parity test needs a genuinely FRESH app launch that reads
/// `onboarding_completed = false` from the server at startup (that's the
/// only place `AuthController.refreshOnboardingStatus` is read from) --
/// flipping the flag mid-process inside an already-running app would not
/// retroactively route it back to onboarding. This file only flips the
/// flag and exits; it never touches the UI.
///
/// Writes `onboarding_completed = false` through the SAME authenticated
/// Supabase client path `AuthRepositoryImpl.markOnboardingCompleted()`
/// already uses in the opposite direction in production code (direct
/// `.update(...).eq('id', ...)` against the signed-in user's own row,
/// under the same RLS policy that already lets a real user's own client
/// write this column) -- not a raw/service-role bypass, and scoped to
/// exactly the one known staging test account (729d097c-7912-410f-8bf7-
/// 7b4203a0f407 — a dedicated staging-only test account, not a real
/// user; its id is not a secret, and is hardcoded deliberately so this
/// file can refuse to act on any other account).
const _expectedStagingHost = 'ovgvevzrcefloitgcsia.supabase.co';
const _productionHost = 'jkmjobvxfrmuwafczvtw.supabase.co';
const _testUserId = '729d097c-7912-410f-8bf7-7b4203a0f407';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Setup: flip onboarding_completed=false for the live acceptance test account', (
    tester,
  ) async {
    app.main();
    final h = Harness(
      IntegrationTestWidgetsFlutterBinding.instance,
      tester,
    );

    for (var i = 0; i < 80 && !dotenv.isInitialized; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final configuredUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final host = Uri.tryParse(configuredUrl)?.host ?? '<unparseable>';
    h.note('BACKEND HOST: $host');
    if (host == _productionHost) {
      h.note('REFUSING: this is the PRODUCTION host. Aborting immediately.');
      return;
    }
    if (host != _expectedStagingHost) {
      h.note('REFUSING: host "$host" is not the expected staging host. Aborting.');
      return;
    }
    h.note('BACKEND CONFIRMED: staging ($_expectedStagingHost)');

    final client = NiswahSupabase.clientOrNull;
    if (client == null) {
      h.note('REFUSING: no Supabase client available after init.');
      return;
    }

    for (var i = 0; i < 40 && client.auth.currentUser == null; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    if (client.auth.currentUser?.id != _testUserId) {
      const testEmail = String.fromEnvironment('LIVE_TEST_EMAIL');
      const testPassword = String.fromEnvironment('LIVE_TEST_PASSWORD');
      if (testEmail.isEmpty || testPassword.isEmpty) {
        h.note('REFUSING: no session and no --dart-define credentials given.');
        return;
      }
      try {
        await client.auth.signInWithPassword(email: testEmail, password: testPassword);
      } catch (e) {
        h.note('REFUSING: sign-in failed: $e');
        return;
      }
      for (var i = 0; i < 40 && client.auth.currentUser == null; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    if (client.auth.currentUser?.id != _testUserId) {
      h.note('REFUSING: signed-in session does not match the expected staging test account.');
      return;
    }

    final before = await client
        .from('users')
        .select('onboarding_completed')
        .eq('id', _testUserId)
        .maybeSingle();
    h.note('BEFORE: onboarding_completed=${before?['onboarding_completed']}');

    await client
        .from('users')
        .update({'onboarding_completed': false})
        .eq('id', _testUserId);

    final after = await client
        .from('users')
        .select('onboarding_completed')
        .eq('id', _testUserId)
        .maybeSingle();
    h.note('AFTER: onboarding_completed=${after?['onboarding_completed']}');
    h.note(
      'SETUP COMPLETE: run live_acceptance_onboarding_parity_test.dart next '
      '(fresh process) to observe onboarding, then it restores this flag.',
    );
  });
}
