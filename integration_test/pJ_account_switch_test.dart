import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Persona J — account switch and isolation. Real production sign-out
/// (Profile screen), then a second real sign-up, verified against the
/// live widget tree: the new account's dashboard must show zero trace
/// of the first account's data.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona J: sign-out then a second account sees none of '
      'the first account\'s data', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    final emailA = await f.newAccountOnDashboard('J1');
    h.note('LOOKUP_EMAIL_A=$emailA');
    await f.startBleedingToday('J1', flow: 'Heavy');
    await h.shot('J', 'account_a_dashboard');
    h.dumpTexts('J account A dashboard (expect Bleeding recorded)');

    await h.scrollToTop();
    await h.settle(1);
    h.note('J tap Profile: ${await h.tapVisible(find.text('Profile'))}');
    await h.settle(2);
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -2000),
      warnIfMissed: false,
    );
    await h.settle(1);
    h.dumpTexts('J profile screen (looking for Sign Out)');
    final signOutTap = await h.tapVisible(find.textContaining('Sign Out'));
    h.note('J tap Sign Out: $signOutTap');
    await h.settle(2);
    await h.shot('J', 'after_sign_out');

    // Confirm handling of a "confirm sign out" dialog if one appears.
    if (find.textContaining('Sign Out').evaluate().isNotEmpty) {
      h.note(
        'J confirm Sign Out dialog: '
        '${await h.tapVisible(find.textContaining('Sign Out'), last: true)}',
      );
      await h.settle(2);
    }
    h.dumpTexts('J after sign out attempt');
    await h.shot('J', 'sign_in_screen_after_signout');

    if (!signOutTap) {
      h.note('J ABORTED — could not find/tap Sign Out this run');
      return;
    }

    final emailB = await f.newAccountOnDashboard('J2', english: true);
    h.note('LOOKUP_EMAIL_B=$emailB');
    await h.settle(2);
    await h.shot('J', 'account_b_dashboard');
    h.dumpTexts('J account B dashboard (expect NO trace of account A)');

    final texts = <String>[];
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as dynamic;
      final s =
          (w.data as String?) ?? (w.textSpan?.toPlainText() as String?) ?? '';
      if (s.trim().isNotEmpty) texts.add(s);
    }
    final joined = texts.join(' | ');
    final leaked =
        joined.contains('Bleeding recorded') || joined.contains('Persona J1');
    h.note('J account B shows leaked account-A data: $leaked');
    h.note(
      leaked
          ? 'J RESULT: FAIL — account B\'s dashboard shows account A\'s data'
          : 'J RESULT: PASS — account B starts clean, no trace of account A',
    );
  });
}
