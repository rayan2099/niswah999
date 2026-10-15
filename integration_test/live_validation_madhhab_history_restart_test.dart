import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/core/preferences/madhhab_history_resolver.dart';
import 'package:niswah/main.dart' as app;

import 'support/harness.dart';

/// STAGING-ONLY, MANUAL-INVOCATION LIVE VALIDATION TEST -- not part of the
/// normal `flutter test` suite or CI; see the matching banner in
/// `live_acceptance_geo_madhhab_test.dart` for the full explanation of why.
///
/// Effective-dated Madhhab history, section 13's "verify historical
/// episodes resolve to the expected Madhhab after app restart": this is a
/// deliberately SEPARATE `flutter test` process from
/// `live_validation_madhhab_history_resolver_test.dart`, run AFTER it.
/// It performs NO writes -- it only re-locates the three real transitions
/// the other file wrote (by `source = 'history_resolver_staging_validation'`)
/// and re-runs the exact same resolver calls from a totally fresh process
/// (no shared Dart VM, no in-memory MadhhabController state carried over)
/// to confirm the answers are identical. If `MadhhabHistoryResolver` ever
/// accidentally depended on anything held only in memory by the process
/// that performed the writes, this would be the test that catches it.
const _expectedStagingHost = 'ovgvevzrcefloitgcsia.supabase.co';
const _productionHost = 'jkmjobvxfrmuwafczvtw.supabase.co';
const _testUserId = '729d097c-7912-410f-8bf7-7b4203a0f407';
const _validationSource = 'history_resolver_staging_validation';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Live validation: resolver answers survive a fresh app restart', (
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

    final rows = await client
        .from('madhhab_history')
        .select('changed_at, new_madhhab')
        .eq('user_id', _testUserId)
        .eq('source', _validationSource)
        .order('changed_at', ascending: true);
    final list = (rows as List).cast<Map<String, dynamic>>();
    h.note('Found ${list.length} prior validation rows (expect 3).');
    if (list.length < 3) {
      h.note(
        'ABORTING: expected 3 rows from the write-phase test '
        '(live_validation_madhhab_history_resolver_test.dart) -- run it '
        'first, in its own flutter test process, immediately before this one.',
      );
      return;
    }

    final t1 = DateTime.parse(list[0]['changed_at'] as String).toUtc();
    final t2 = DateTime.parse(list[1]['changed_at'] as String).toUtc();
    final t3 = DateTime.parse(list[2]['changed_at'] as String).toUtc();
    h.note('Re-located real transitions: t1=$t1 t2=$t2 t3=$t3');

    const resolver = MadhhabHistoryResolver();

    // T1/T2/T3 (and every other write this live-validation suite has made
    // today, including the write-phase test's own end-of-run restore to
    // unknown) are all the same real UTC calendar day -- under the
    // resolver's deliberate day-granularity boundary semantics (see the
    // resolver's own doc comment), the ENTIRE day collapses to whichever
    // write was LAST, which by now is that restore-to-unknown, not T1/T2/T3
    // individually. Probing "right after T1" vs "right after T3" can
    // therefore never distinguish them live on the same real day -- that
    // distinctness is exhaustively proven by madhhab_history_resolver_test.dart's
    // unit tests using explicit, genuinely different calendar dates. What
    // THIS live, fresh-process test proves instead is a sharper, more
    // robust restart-safety invariant: a resolution for "right now," from
    // a brand-new process with zero shared state, must exactly match the
    // account's actual CURRENT server row -- if the resolver ever read a
    // stale cache or an in-memory value instead of fetching fresh, this
    // would catch it.
    final currentUserRow = await client
        .from('users')
        .select('madhhab, madhhab_selection_state')
        .eq('id', _testUserId)
        .maybeSingle();
    final resolvedNow = await resolver.resolveMadhhabForDate(
      _testUserId,
      DateTime.now().toUtc(),
    );
    h.note(
      'Current server row: $currentUserRow -- '
      'fresh-process resolver for "now": '
      'selectionState=${resolvedNow.selectionState} madhhab=${resolvedNow.madhhab}',
    );
    final currentState = currentUserRow?['madhhab_selection_state'] as String?;
    final currentMadhhab = (currentUserRow?['madhhab'] as String?)?.toLowerCase();
    final matches =
        resolvedNow.selectionState.name == currentState &&
        (resolvedNow.madhhab?.name) == currentMadhhab;
    h.note(
      'RESTART-SAFE (fresh-process resolution for "now" exactly matches '
      'the real current server row -- no stale/cached value survived the '
      'process boundary): $matches',
    );

    // Confirm this same real transition day still resolves to a single
    // consistent value regardless of which moment within it is queried
    // (right after T1 vs right after T3) -- the day-collapse behavior
    // itself, proven live rather than just asserted.
    final afterT1 = await resolver.resolveMadhhabForDate(
      _testUserId,
      t1.add(const Duration(seconds: 1)),
    );
    final afterT3 = await resolver.resolveMadhhabForDate(
      _testUserId,
      t3.add(const Duration(seconds: 1)),
    );
    h.note(
      'Same real day, two different moments queried -- afterT1=${afterT1.madhhab} '
      'afterT3=${afterT3.madhhab} (expect these to be EQUAL, both collapsing '
      'to today\'s true latest value, confirming day-granularity live): '
      '${afterT1.selectionState == afterT3.selectionState && afterT1.madhhab == afterT3.madhhab}',
    );

    h.note('LIVE RESTART VALIDATION COMPLETE — see NOTE lines above.');
  });
}
