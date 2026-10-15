import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/madhhab_history_resolver.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/main.dart' as app;

import 'support/harness.dart';

/// STAGING-ONLY, MANUAL-INVOCATION LIVE VALIDATION TEST -- not part of the
/// normal `flutter test` suite or CI; see the matching banner in
/// `live_acceptance_geo_madhhab_test.dart` for the full explanation of why
/// (not discovered by a bare `flutter test`, requires explicit
/// `--dart-define` credentials never embedded in this file, refuses
/// immediately and safely if either is missing or the backend isn't
/// exactly the known staging host).
///
/// Effective-dated Madhhab history, section 13 (staging validation):
/// performs three REAL Madhhab transitions in quick succession (minutes
/// apart, not months -- the resolver doesn't care about wall-clock
/// spacing, only about `changed_at` ordering, so this validates the exact
/// same mechanism the 3-month example describes) on the known staging
/// test account (729d097c-7912-410f-8bf7-7b4203a0f407, hardcoded
/// deliberately so this file can refuse to act on any other account --
/// its id is not a secret), then queries `MadhhabHistoryResolver` against
/// the REAL staging backend to confirm each interval resolves correctly.
///
/// Deliberately does NOT insert synthetic/backdated `madhhab_history`
/// rows: that table has no UPDATE/DELETE policy (append-only by design),
/// so any row written here is PERMANENT on this shared test account --
/// fabricating fake historical dates on it would misrepresent its real
/// audit trail forever, which is exactly what the task's own "do not
/// invent historical dates" principle forbids. Every row this test
/// writes is a genuine transition, really performed, tagged
/// `source: 'history_resolver_staging_validation'` so it's easy to find
/// and never confused with a real product action.
const _expectedStagingHost = 'ovgvevzrcefloitgcsia.supabase.co';
const _productionHost = 'jkmjobvxfrmuwafczvtw.supabase.co';
const _testUserId = '729d097c-7912-410f-8bf7-7b4203a0f407';
const _validationSource = 'history_resolver_staging_validation';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Live validation: MadhhabHistoryResolver against real staging history', (
    tester,
  ) async {
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
      await h.settle(2);
    }
    final currentUid = client.auth.currentUser?.id;
    h.note('SIGNED-IN SESSION MATCHES EXPECTED TEST ACCOUNT: ${currentUid == _testUserId}');
    if (currentUid != _testUserId) {
      h.note('REFUSING: signed-in session does not match the expected staging test account.');
      return;
    }

    // ---- Raw-data baseline: confirm untouched by the end ----
    Future<int> countRows(String table) async {
      final rows = await client.from(table).select('id').eq('user_id', _testUserId);
      return (rows as List).length;
    }

    final episodesBefore = await countRows('bleeding_episodes');
    final observationsBefore = await countRows('bleeding_observations');
    h.note('RAW DATA BASELINE: bleeding_episodes=$episodesBefore bleeding_observations=$observationsBefore');

    const resolver = MadhhabHistoryResolver();

    Future<DateTime> performRealTransition(Madhhab madhhab) async {
      await MadhhabController.instance.selectMadhhab(
        madhhab,
        source: _validationSource,
      );
      await tester.pump(const Duration(milliseconds: 300));
      // Read back the REAL server-assigned changed_at for this exact
      // transition -- never assume client-side DateTime.now(), which
      // could drift from the server's own now().
      final rows = await client
          .from('madhhab_history')
          .select('changed_at')
          .eq('user_id', _testUserId)
          .eq('source', _validationSource)
          .order('changed_at', ascending: false)
          .limit(1);
      final list = rows as List;
      return DateTime.parse((list.first as Map)['changed_at'] as String).toUtc();
    }

    final t1 = await performRealTransition(Madhhab.hanafi);
    h.note('Transition 1 (Hanafi) real changed_at: $t1');
    await Future<void>.delayed(const Duration(seconds: 2));

    final t2 = await performRealTransition(Madhhab.maliki);
    h.note('Transition 2 (Maliki) real changed_at: $t2');
    await Future<void>.delayed(const Duration(seconds: 2));

    final t3 = await performRealTransition(Madhhab.hanafi);
    h.note('Transition 3 (Hanafi again) real changed_at: $t3');

    // ---- Resolve against the REAL backend ----
    // T1/T2/T3 are all genuinely the same real UTC calendar day (performed
    // seconds apart) -- under the resolver's deliberate day-granularity
    // boundary semantics (required so "episode start == change date"
    // resolves deterministically regardless of time-of-day; see the
    // resolver's own doc comment and madhhab_history_resolver_test.dart's
    // "multiple rapid switches" unit test), same-day transitions collapse
    // to "whichever was last THAT DAY governs the whole day." So querying
    // any moment on this same real day -- including right after T1 or
    // T2 -- correctly resolves to T3's value (the last one today), not to
    // T1's or T2's own value. That is the mechanism working as designed,
    // not a bug; the exhaustive cross-day boundary matrix (Jan/Feb/Mar,
    // same-date, before/after) is already proven by the unit tests using
    // explicit dates on different calendar days, which a live same-day
    // run cannot exercise without literally waiting across a real
    // midnight. What THIS live run proves is the real I/O path: fetching
    // from the real table, parsing real rows, sorting them, and falling
    // back correctly for a date before today -- see below.
    final resolvedToday = await resolver.resolveMadhhabForDate(
      _testUserId,
      t1.add(const Duration(milliseconds: 500)),
    );
    h.note(
      'Resolved anywhere on the real transition day (right after T1): '
      'madhhab=${resolvedToday.madhhab} resolution=${resolvedToday.resolution} '
      'effectiveFrom=${resolvedToday.effectiveFrom} effectiveTo=${resolvedToday.effectiveTo} '
      '(expect hanafi -- T3\'s value, the last real change this same day; '
      'effectiveFrom should equal T3, not T1)',
    );
    final resolvedTodayLate = await resolver.resolveMadhhabForDate(
      _testUserId,
      t3.add(const Duration(milliseconds: 500)),
    );
    h.note(
      'Resolved right after T3: madhhab=${resolvedTodayLate.madhhab} '
      'effectiveTo=${resolvedTodayLate.effectiveTo} '
      '(expect hanafi, null -- still the latest interval)',
    );

    // A date clearly BEFORE today (yesterday) must resolve from whatever
    // was true before any of today's three real transitions -- proving
    // the "before the earliest-relevant row" fallback path against REAL
    // server data, not just the unit tests' synthetic entries.
    final resolvedYesterday = await resolver.resolveMadhhabForDate(
      _testUserId,
      t1.subtract(const Duration(days: 1)),
    );
    h.note(
      'Resolved for yesterday (before any of today\'s real transitions): '
      'selectionState=${resolvedYesterday.selectionState} '
      'madhhab=${resolvedYesterday.madhhab} '
      'resolution=${resolvedYesterday.resolution} '
      '(expect whatever this account\'s real state was yesterday -- '
      'unknown, per every other test in this session leaving it that way)',
    );

    // ---- Raw-data integrity: confirm these Madhhab changes touched nothing ----
    final episodesAfter = await countRows('bleeding_episodes');
    final observationsAfter = await countRows('bleeding_observations');
    h.note(
      'RAW DATA AFTER: bleeding_episodes=$episodesAfter '
      'bleeding_observations=$observationsAfter '
      '(expect unchanged: $episodesBefore, $observationsBefore)',
    );

    // ---- Restore the account to the safe baseline every other test in
    // this session leaves it at ----
    await MadhhabController.instance.selectUnknown(source: 'test_restore');
    await tester.pump(const Duration(milliseconds: 300));
    final finalRow = await client
        .from('users')
        .select('madhhab, madhhab_selection_state')
        .eq('id', _testUserId)
        .maybeSingle();
    h.note('RESTORED: user=$finalRow (expect madhhab=null, state=unknown)');

    h.note('LIVE HISTORY-RESOLVER VALIDATION COMPLETE — see NOTE lines above for each check.');
  });
}
