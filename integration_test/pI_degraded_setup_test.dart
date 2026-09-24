import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Persona I, phase 1 of 2 — signs up and starts a real episode, then
/// stops. Run WITHOUT uninstalling the app afterward: the session
/// persists in the simulator's own Keychain, which phase 2
/// (pI_degraded_verify_test.dart) relies on after a host-side SQL
/// insert of one genuinely malformed row (see that file's own note on
/// why `docker exec` cannot run from inside the iOS app itself).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona I phase 1: sign up and start a real episode', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    final email = await f.newAccountOnDashboard('I');
    h.note('LOOKUP_EMAIL=$email');
    await f.startBleedingToday('I');
    await h.shot('I', 'phase1_dashboard');
    h.note('I PHASE 1 COMPLETE — session left signed in on purpose');
  });
}
