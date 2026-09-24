import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/harness.dart';

/// Persona I, phase 2 of 2 — the app relaunches with the SAME persisted
/// session phase 1 left signed in. Between the two phases, a genuinely
/// malformed row is inserted directly via host-side SQL: 'source'
/// carries no CHECK constraint at the DB layer (only 'flow'/'precision'
/// do), so this is a real, live-database-accepted row that the Dart
/// client's own BleedingObservation.fromJson cannot parse
/// (ObservationSource.classify throws BleedingEpisodeParseException for
/// an unrecognized value) — the exact "quarantined row" scenario
/// F5(C)'s own widget-level tests already cover; this proves it live,
/// against a real Postgres read.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona I phase 2: the dashboard shows honest '
      'degraded-evidence state for a real malformed row, never a crash, '
      'never a fabricated ruling', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    await tester.pump(const Duration(seconds: 3));
    await h.settle(3);
    await h.scrollToTop();
    await h.settle(1);
    h.dumpTexts('I phase2 dashboard top');
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await h.settle(2);
    h.dumpTexts('I phase2 dashboard with malformed row');
    await h.shot('I', 'phase2_degraded_evidence');

    final texts = <String>[];
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as Text;
      final s = w.data ?? w.textSpan?.toPlainText() ?? '';
      if (s.trim().isNotEmpty) texts.add(s);
    }
    final joined = texts.join(' | ');
    h.note('I full text dump: $joined');

    final crashed = tester.takeException() != null;
    final showsHonestState =
        joined.contains("couldn't verify") ||
        joined.contains('Unable to verify') ||
        joined.contains('تعذر التحقق');
    final claimsObligatory = joined.contains('Salah is obligatory');
    final pass = !crashed && showsHonestState && !claimsObligatory;
    h.note(
      'I crashed=$crashed showsHonestState=$showsHonestState '
      'claimsObligatory=$claimsObligatory',
    );
    h.note(
      pass
          ? 'I RESULT: PASS — a genuinely malformed row (real Postgres '
                'insert, unparseable "source" value) produced an honest '
                '"cannot verify" state, never a crash, never a '
                'fabricated ruling'
          : 'I RESULT: FAIL — crashed=$crashed showsHonestState='
                '$showsHonestState claimsObligatory=$claimsObligatory',
    );
    h.reportResult(
      PersonaResult(
        testId: 'I-phase2',
        expectedOutcome:
            'A genuinely malformed row (real Postgres insert, an '
            'unparseable "source" value that no CHECK constraint blocks) '
            'shows an honest "cannot verify" state — never a crash, never '
            'a fabricated Fiqh ruling',
        actualOutcome:
            'crashed=$crashed showsHonestState=$showsHonestState '
            'claimsObligatory=$claimsObligatory',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'I_phase2_degraded_evidence.png',
      ),
    );
  });
}
