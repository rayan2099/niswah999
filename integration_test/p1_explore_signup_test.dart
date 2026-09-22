import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('explore: sign up and walk onboarding', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);
    await f.boot();
    final email = await f.signUpWithEmail('explore');
    h.note('EMAIL $email');
    await h.tapVisible(find.text('Create Account'));
    await h.waitFor(find.text('Get Started'), timeout: const Duration(seconds: 25));
    await f.walkOnboarding('X4', [
      'Get Started',
      "I don't know my Madhhab",
      "I'll decide later",
      'Skip for now',
      'I’m not sure',
      'Continue',
      'Next',
    ]);
  });
}
