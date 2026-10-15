import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P0 build identity: real app launches and reports SHA/backend', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    // Production kill switch — before ANY sign-up, fixture or action.
    if (!await h.guardBackend('P0')) return;
    await tester.pump(const Duration(seconds: 5));
    await h.settle();

    // ignore: avoid_print
    print('BANNER => ${h.bannerText()}');
    final hasSha = h.bannerText().contains('SHA:');
    h.reportResult(
      PersonaResult(
        testId: 'P0',
        expectedOutcome:
            'Real app launches and the build-identity banner shows the '
            'tested SHA and backend host',
        actualOutcome: 'Banner text: ${h.bannerText()}',
        status: hasSha ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'P0_01_first_screen.png',
      ),
    );
    await h.shot('P0', 'first_screen');
    expect(hasSha, isTrue, reason: 'Build-identity banner missing SHA:');
  });
}
