import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 — PRAY-0X: location permission DENIED -> honest failure, manual city still works
/// The OS permission is set by the host BEFORE launch
/// (scripts/set_location_permission.sh revoke): a native permission dialog
/// cannot be tapped from inside a Flutter integration test.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PRAY-03 denied', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('L2')) return;
    final f = Flows(h);

    await f.boot();
    final email = await f.signUpWithEmail('L');
    h.note('LOOKUP_EMAIL=$email');
    await h.tapVisible(find.text('Create Account'));
    await h.waitFor(
      find.text('Get Started'),
      timeout: const Duration(seconds: 25),
    );
    // Madhhab -> "I don't know" -> later; marital -> Continue.
    await f.walkOnboarding('L', [
      "I don't know my Madhhab",
      "I'll decide later",
      'Continue',
    ], maxSteps: 3);
    await h.settle(2);
    final locationStep = await _texts(h, 'L location step');
    final onLocationStep = locationStep.contains('Where are you located?');

    final tapped = await h.tapVisible(find.text('Use current location'));
    await tester.pump(const Duration(seconds: 6));
    await h.settle(3);
    await h.shot('L', 'L2_after_use_location');
    final after = await _texts(h, 'L after Use current location');
    final honest =
        after.contains('Location permission denied') ||
        after.contains('Location not detected') ||
        after.contains('Turn on location services') ||
        after.contains('Unable to get your location');
    final stayed = after.contains('Where are you located?');
    h.note(
      'L PRAY-03 onLocationStep=$onLocationStep tapped=$tapped honestMessage=$honest stayedOnStep=$stayed',
    );
    // The user must still be able to proceed by picking a city.
    final pickedCity = await h.tapVisible(find.text('Riyadh'));
    await h.settle(1);
    final continued = await h.tapVisible(find.text('Continue'));
    await h.settle(3);
    final next = await _texts(h, 'L after manual city fallback');
    final proceeded = next.contains('When did your last period start?');
    h.note(
      'L PRAY-03 fallback: picked=$pickedCity continued=$continued proceeded=$proceeded',
    );
    final crashed = tester.takeException() != null;
    final pass =
        !crashed && onLocationStep && tapped && honest && stayed && proceeded;
    h.reportResult(
      PersonaResult(
        testId: 'L2',
        expectedOutcome: 'PRAY-03: with location permission denied, "Use current location" fails HONESTLY (clear message, no crash, no silent success) and the user can still continue by picking a city',
        actualOutcome:
            'crashed=$crashed onLocationStep=$onLocationStep tapped=$tapped honestMessage=$honest stayedOnStep=$stayed cityFallbackProceeded=$proceeded',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'L_L2_after_use_location.png',
      ),
    );
  });
}

Future<String> _texts(Harness h, String label) async {
  await h.settle(1);
  h.dumpTexts(label);
  return h.notes.last;
}
