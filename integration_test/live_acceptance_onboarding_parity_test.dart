import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
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
/// Live acceptance test, item 5: confirm onboarding's own "Help me choose"
/// Madhhab path behaves identically to Profile/Settings' (tested in
/// `live_acceptance_geo_madhhab_test.dart`) -- same shared
/// `MadhhabResolutionFlow`/`MadhhabSelector` components, no duplicated
/// recommendation logic. Uses the same dedicated staging-only test
/// account (729d097c-7912-410f-8bf7-7b4203a0f407, hardcoded deliberately
/// so this file can refuse to act on any other account — its id is not a
/// secret) as every other file in this acceptance suite.
///
/// REQUIRES `live_acceptance_onboarding_setup_test.dart` to have already
/// run (a separate, prior `flutter test` process) so `onboarding_completed`
/// is `false` on disk BEFORE this app process boots -- that is the only
/// moment `AuthController.refreshOnboardingStatus` is read, so this is the
/// one way to make a fresh launch actually land on `OnboardingScreen`.
///
/// Restores `onboarding_completed = true` (and leaves Madhhab at
/// `unknown`, matching where the Profile/Settings run left the account)
/// in a `finally` block, so the account is left in a safe, reversible
/// state even if an assertion earlier in the test fails.
const _expectedStagingHost = 'ovgvevzrcefloitgcsia.supabase.co';
const _productionHost = 'jkmjobvxfrmuwafczvtw.supabase.co';
const _testUserId = '729d097c-7912-410f-8bf7-7b4203a0f407';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Live acceptance: onboarding Madhhab flow parity', (tester) async {
    app.main();
    final h = Harness(binding, tester);

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
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 40 && client.auth.currentUser == null; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      h.note('Sign-in result: session established=${client.auth.currentUser != null}');
      await h.settle(2);
    }
    final currentUid = client.auth.currentUser?.id;
    h.note('SIGNED-IN SESSION MATCHES EXPECTED TEST ACCOUNT: ${currentUid == _testUserId}');
    if (currentUid != _testUserId) {
      h.note('REFUSING: signed-in session does not match the expected staging test account.');
      return;
    }

    Future<Map<String, dynamic>?> fetchUserRow() async {
      return await client
          .from('users')
          .select('madhhab, madhhab_selection_state, onboarding_completed')
          .eq('id', _testUserId)
          .maybeSingle();
    }

    final startRow = await fetchUserRow();
    h.note('START STATE (expect onboarding_completed=false from the setup run): $startRow');
    if (startRow?['onboarding_completed'] != false) {
      h.note(
        'REFUSING: onboarding_completed is not false -- the setup test '
        '(live_acceptance_onboarding_setup_test.dart) must run first, in '
        'its own flutter test process, immediately before this one.',
      );
      return;
    }

    try {
      // ---- Confirm we actually landed on Onboarding, not the dashboard ----
      await h.settle(3);
      final onSplash = await h.waitFor(find.text('ابدئي'), timeout: const Duration(seconds: 15));
      h.note('LANDED ON ONBOARDING SPLASH (expect true): $onSplash');
      await h.shot('LIVE', 'onboarding_splash');
      if (!onSplash) {
        h.note('ABORTING: did not land on the onboarding splash screen.');
        return;
      }

      await h.tapVisible(find.text('ابدئي')); // Get Started -> step 2 (Madhhab)
      await h.settle(2);
      final onMadhhabStep = find.text('ما مذهبكِ الفقهي؟').evaluate().isNotEmpty;
      h.note('ON MADHHAB STEP (expect true): $onMadhhabStep');
      await h.shot('LIVE', 'onboarding_madhhab_step');

      Future<void> selectCountryByArabicName(String arabicName) async {
        final openedPicker = await h.tapVisible(find.text('اختيار الدولة'));
        await h.settle(1);
        await tester.enterText(find.byType(TextField), arabicName);
        await tester.pump(const Duration(milliseconds: 400));
        final pickedCountry = await h.tapVisible(find.widgetWithText(ListTile, arabicName));
        await h.settle(1);
        final tappedContinue = await h.tapVisible(find.text('متابعة'));
        await h.settle(2);
        h.note(
          'selectCountryByArabicName($arabicName): openedPicker=$openedPicker '
          'pickedCountry=$pickedCountry tappedContinue=$tappedContinue',
        );
      }

      // =================================================================
      // Saudi Arabia: real geographic suggestion, same shared components
      // Profile/Settings uses.
      // =================================================================
      final tappedUnknownTile = await h.tapVisible(find.text('لا أعرف'));
      await h.settle(1);
      h.note('Tapped "I don\'t know" tile (expect true): $tappedUnknownTile');
      final onUnknownExplanation = find.text('لا بأس').evaluate().isNotEmpty;
      h.note('ON UNKNOWN EXPLANATION STEP (expect true): $onUnknownExplanation');
      final helpMeChooseTapped = await h.tapVisible(find.text('ساعديني في الاختيار'));
      await h.settle(1);
      h.note('Tapped "Help me choose" (expect true): $helpMeChooseTapped');

      await selectCountryByArabicName('السعودية');
      await h.shot('LIVE', 'onboarding_saudi_suggestion');
      final saHeadline = find
          .text('بناءً على البلد الذي نشأتِ فيه، قد يكون المذهب الحنبلي هو الأقرب.')
          .evaluate()
          .isNotEmpty;
      final saHasAcceptButton = find.text('استخدام الحنبلي').evaluate().isNotEmpty;
      final saHasChooseAnother = find.text('اختيار مذهب آخر').evaluate().isNotEmpty;
      final saHasStillDontKnow = find.text('ما زلت لا أعرف').evaluate().isNotEmpty;
      h.note(
        'ONBOARDING SAUDI ARABIA: headline=$saHeadline acceptBtn=$saHasAcceptButton '
        'chooseAnother=$saHasChooseAnother stillDontKnow=$saHasStillDontKnow '
        '(expect identical presentation to Profile/Settings\' own Saudi Arabia check)',
      );

      final acceptTapped = await h.tapVisible(find.text('استخدام الحنبلي'));
      await h.settle(2);
      h.note('Tapped accept suggestion (expect true): $acceptTapped');
      final advancedPastMadhhab = find.text('هل أنتِ متزوجة؟').evaluate().isNotEmpty;
      h.note('ADVANCED TO STEP 3 (married question) AFTER ACCEPT (expect true): $advancedPastMadhhab');
      final afterAcceptRow = await fetchUserRow();
      h.note('AFTER ACCEPT: user=$afterAcceptRow (expect madhhab=hanbali, state=selected)');

      // =================================================================
      // Back to the Madhhab step, reset to unknown, then one UNVERIFIED
      // country (Tunisia) -> expect no suggestion, direct manual selector.
      // =================================================================
      // The whole account is in Arabic throughout this account's own
      // sessions (confirmed in every other live-acceptance run), so the
      // back icon's tooltip is 'رجوع', not 'Back' -- try both regardless.
      var backTapped = await h.tapVisible(find.byTooltip('رجوع'));
      if (!backTapped) backTapped = await h.tapVisible(find.byTooltip('Back'));
      await h.settle(2);
      h.note('Tapped Back to return to Madhhab step (expect true): $backTapped');

      // Direct controller call (not a raw DB write) so the already-running
      // app's in-memory state is refreshed too -- the same reversible
      // reset pattern used throughout the Profile/Settings run.
      await MadhhabController.instance.selectUnknown(source: 'test_reset');
      await tester.pump(const Duration(milliseconds: 300));
      await h.settle(1);

      final tappedUnknownTile2 = await h.tapVisible(find.text('لا أعرف'));
      await h.settle(1);
      h.note('Tapped "I don\'t know" tile again (expect true): $tappedUnknownTile2');
      final helpMeChooseTapped2 = await h.tapVisible(find.text('ساعديني في الاختيار'));
      await h.settle(1);
      h.note('Tapped "Help me choose" again (expect true): $helpMeChooseTapped2');

      await selectCountryByArabicName('تونس');
      await h.shot('LIVE', 'onboarding_tunisia_unverified');
      final noSuggestionHeadlinePresent =
          find.textContaining('قد يكون المذهب').evaluate().isEmpty &&
          find.textContaining('قد تكون هذه المذاهب').evaluate().isEmpty;
      final manualGridPresent = find.text('اختاري المذهب الذي تتبعينه').evaluate().isNotEmpty;
      final allFourPresent = ['حنفي', 'مالكي', 'شافعي', 'حنبلي']
          .every((n) => find.text(n).evaluate().isNotEmpty);
      final unknownOptionPresent = find.text('لا أعرف').evaluate().isNotEmpty;
      h.note(
        'ONBOARDING TUNISIA (UNVERIFIED): noSuggestionHeadline=$noSuggestionHeadlinePresent '
        'manualGrid=$manualGridPresent allFourSchools=$allFourPresent '
        'unknownOption=$unknownOptionPresent '
        '(expect identical presentation to Profile/Settings\' own unverified-country check)',
      );

      // Finish cleanly via "I don't know" so onboarding can advance, same
      // as any real user's honest answer here.
      final finishedUnknown = await h.tapVisible(find.text('لا أعرف'));
      await h.settle(2);
      h.note('Tapped "I don\'t know" to finish the Madhhab step (expect true): $finishedUnknown');
      final finalAdvanced = find.text('هل أنتِ متزوجة؟').evaluate().isNotEmpty;
      h.note('ADVANCED TO STEP 3 AFTER "I DON\'T KNOW" (expect true): $finalAdvanced');

      final afterTunisiaRow = await fetchUserRow();
      h.note('AFTER TUNISIA/UNKNOWN: user=$afterTunisiaRow (expect madhhab=null, state=unknown)');

      h.note('ONBOARDING PARITY RUN COMPLETE — see NOTE lines above for each check.');
    } finally {
      // Always restore onboarding_completed=true and leave Madhhab at
      // unknown, whatever happened above -- this is a real, persistent
      // staging test account, not a disposable one.
      await MadhhabController.instance.selectUnknown(source: 'test_restore');
      await client
          .from('users')
          .update({'onboarding_completed': true})
          .eq('id', _testUserId);
      final restoredRow = await fetchUserRow();
      h.note('RESTORED: user=$restoredRow (expect onboarding_completed=true, state=unknown)');
    }
  });
}
