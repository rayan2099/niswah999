import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Persona I — genuinely degraded evidence, live and fully in-schema.
///
/// A prior wave's design relied on a host-side SQL insert of a
/// malformed `bleeding_observations.source` value, on the assumption
/// that column carried no CHECK constraint. Confirmed THIS session,
/// directly against a live Postgres instance, that assumption is false:
/// `bleeding_observations_source_check` now rejects any value outside
/// `('user_observed', 'user_reported_historical')` — the malformed-row
/// approach is provably impossible without weakening a real database
/// constraint, which the charter explicitly forbids.
///
/// The real, product-supported "degraded evidence" seam is
/// `ObservationFlow.uncertain` — a fully valid, CHECK-constrained enum
/// value reachable ONLY through the genuine daily check-in flow
/// (`daily_checkin_sheet.dart`): "Daily check-in" -> "Yes" (still
/// bleeding) -> "How is it right now?" -> "I'm not sure". No database
/// access, no injected row: every step is a real tap through real
/// production widgets. `dashboard_screen.dart`'s own
/// `_hasMaterialUnresolvedEvidence` treats exactly this (an excluded
/// uncertain-flow day on/after the open episode's own start) as
/// evidence a Fiqh ruling must not be drawn from.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Persona I: a real "I\'m not sure" flow answer produces an honest '
    '"cannot confirm" Fiqh state, never a crash, never a fabricated '
    'ruling',
    (tester) async {
      app.main();
      final h = Harness(binding, tester);
      // Production kill switch — before ANY sign-up, fixture or action.
      if (!await h.guardBackend('I')) return;
      final f = Flows(h);
      final email = await f.newAccountOnDashboard('I');
      h.note('LOOKUP_EMAIL=$email');
      await f.startBleedingToday('I');
      await h.shot('I', 'dashboard_before_checkin');

      final openedCheckin = await h.tapVisible(
        find.textContaining('Daily check-in'),
      );
      h.note('I opened Daily check-in: $openedCheckin');
      await h.settle(2);
      if (!openedCheckin) {
        h.note('I ABORTED — could not open the Daily check-in sheet');
        h.reportResult(
          PersonaResult(
            testId: 'I',
            expectedOutcome:
                'A real "I\'m not sure" flow answer produces an honest '
                '"cannot confirm" Fiqh state, never a crash, never a '
                'fabricated ruling',
            actualOutcome: 'Could not open the Daily check-in sheet',
            status: PersonaStatus.blocked,
            screenshotRef: 'I_dashboard_before_checkin.png',
          ),
        );
        return;
      }
      await h.shot('I', 'checkin_question');

      final tappedYes = await h.tapVisible(find.text('Yes'));
      h.note('I tapped Yes (still bleeding): $tappedYes');
      await h.settle(1);
      await h.shot('I', 'checkin_flow_options');

      final tappedUnsure = await h.tapVisible(find.text("I'm not sure"));
      h.note('I tapped flow "I\'m not sure": $tappedUnsure');
      await h.settle(1);

      final tappedSave = await h.tapVisible(find.text('Save'));
      h.note('I tapped Save: $tappedSave');
      await tester.pump(const Duration(seconds: 5));
      await h.settle(2);
      await h.shot('I', 'after_uncertain_checkin');

      final uiSequenceComplete = tappedYes && tappedUnsure && tappedSave;
      if (!uiSequenceComplete) {
        h.note(
          'I ABORTED — UI sequence incomplete: tappedYes=$tappedYes '
          'tappedUnsure=$tappedUnsure tappedSave=$tappedSave',
        );
        h.reportResult(
          PersonaResult(
            testId: 'I',
            expectedOutcome:
                'A real "I\'m not sure" flow answer produces an honest '
                '"cannot confirm" Fiqh state, never a crash, never a '
                'fabricated ruling',
            actualOutcome:
                'UI sequence incomplete: tappedYes=$tappedYes '
                'tappedUnsure=$tappedUnsure tappedSave=$tappedSave',
            status: PersonaStatus.blocked,
          ),
        );
        return;
      }

      h.dumpTexts('I after uncertain check-in');
      final joined = h.notes.last;

      final crashed = tester.takeException() != null;
      final showsHonestState =
          joined.contains("can't be confirmed right now") ||
          joined.contains('لا يمكن تأكيد') ||
          joined.contains("couldn't verify") ||
          joined.contains('تعذر التحقق');
      final claimsObligatory =
          joined.contains('Salah is obligatory') ||
          joined.contains('الصلاة واجبة');
      final pass = !crashed && showsHonestState && !claimsObligatory;
      h.note(
        'I crashed=$crashed showsHonestState=$showsHonestState '
        'claimsObligatory=$claimsObligatory',
      );
      h.note(
        pass
            ? 'I RESULT: PASS — a real "I\'m not sure" flow answer (live '
                  'UI, no DB injection) produced an honest "cannot '
                  'confirm" state, never a crash, never a fabricated '
                  'ruling'
            : 'I RESULT: FAIL — crashed=$crashed showsHonestState='
                  '$showsHonestState claimsObligatory=$claimsObligatory',
      );
      h.reportResult(
        PersonaResult(
          testId: 'I',
          expectedOutcome:
              'A real "I\'m not sure" flow answer produces an honest '
              '"cannot confirm" Fiqh state, never a crash, never a '
              'fabricated ruling',
          actualOutcome:
              'crashed=$crashed showsHonestState=$showsHonestState '
              'claimsObligatory=$claimsObligatory',
          status: pass ? PersonaStatus.pass : PersonaStatus.fail,
          screenshotRef: 'I_after_uncertain_checkin.png',
        ),
      );
    },
  );
}
