import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 — PRAY-0X: location permission GRANTED -> device location used for prayer times
/// The OS permission is set by the host BEFORE launch
/// (scripts/set_location_permission.sh grant): a native permission dialog
/// cannot be tapped from inside a Flutter integration test.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PRAY-02 granted', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('L1')) return;
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
    await h.shot('L', 'L1_after_use_location');
    final after = await _texts(h, 'L after Use current location');
    final advanced = after.contains('When did your last period start?');
    h.note(
      'L PRAY-02 onLocationStep=$onLocationStep tapped=$tapped advanced=$advanced',
    );
    // Finish onboarding and confirm the prayer location is the device fix.
    await f.walkOnboarding('L', [
      'I’m not sure',
      'Continue',
      'Get Started',
    ], maxSteps: 8);
    await h.scrollToTop();
    await h.tapVisible(find.text('Profile'), last: true);
    await h.settle(2);
    final profile = await _texts(h, 'L profile after device location');
    final showsDeviceLocation = profile.contains('Current location');
    h.note('L PRAY-02 profile shows device location: $showsDeviceLocation');
    final crashed = tester.takeException() != null;
    final pass =
        !crashed && onLocationStep && tapped && advanced && showsDeviceLocation;
    h.reportResult(
      PersonaResult(
        testId: 'L1',
        expectedOutcome: 'PRAY-02: with location permission granted, "Use current location" gets a real fix, advances onboarding and the Profile shows the device location for prayer times',
        actualOutcome:
            'crashed=$crashed onLocationStep=$onLocationStep tapped=$tapped advanced=$advanced profileShowsDeviceLocation=$showsDeviceLocation',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'L_L1_after_use_location.png',
      ),
    );
  });
}

Future<String> _texts(Harness h, String label) async {
  await h.settle(1);
  h.dumpTexts(label);
  return h.notes.last;
}
