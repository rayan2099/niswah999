import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// AUTH-08 — email confirmation. Needs a LOCAL backend whose GoTrue has
/// confirmations ENABLED and a reachable mailbox, so it is deliberately NOT
/// a `p*_test.dart` (the main suite's backend auto-confirms; enabling
/// confirmations there would break every other persona). Run it through
/// scripts/run_auth08_confirmations.sh, which toggles the local stack.
///
/// Sign-up must show the "Check your email" pending state and create NO
/// session; signing in before confirming must be refused honestly; opening
/// the real confirmation link from the local mailbox must then allow the
/// sign-in to succeed and reach onboarding.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AUTH-08: email confirmation pending -> confirmed', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('AUTH08')) return;
    final f = Flows(h);

    final supabaseUrl = Uri.parse(dotenv.env['SUPABASE_URL'] ?? '');
    final mailHost = supabaseUrl.host;

    await f.boot();
    final email = await f.signUpWithEmail('V');
    h.note('LOOKUP_EMAIL=$email');
    await h.tapVisible(find.text('Create Account'));
    await tester.pump(const Duration(seconds: 6));
    await h.settle(3);
    final pending = await _texts(h, 'V after sign-up');
    final showsPending =
        pending.contains('Check your email') && pending.contains(email);
    final noSession = NiswahSupabase.clientOrNull?.auth.currentSession == null;
    await h.shot('V', 'check_your_email');
    h.note('V pending=$showsPending noSession=$noSession');

    // Back to Sign In, try to sign in BEFORE confirming.
    await h.tapVisible(find.text('Back to Sign In'));
    await h.settle(2);
    await tester.enterText(
      find.widgetWithText(TextField, 'Email').first,
      email,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password').first,
      'Test-Pass-12345',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await h.tapVisible(find.text('Sign In'), last: true);
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    final refused = await _texts(h, 'V sign-in before confirming');
    final refusedHonestly =
        refused.toLowerCase().contains('not confirmed') &&
        NiswahSupabase.clientOrNull?.auth.currentSession == null;
    h.note('V unconfirmed sign-in refused honestly=$refusedHonestly');

    // Fetch the REAL confirmation email from the local mailbox and open it.
    final http = HttpClient();
    String? link;
    try {
      for (var i = 0; i < 15 && link == null; i++) {
        final search = await _getJson(
          http,
          Uri.parse(
            'http://$mailHost:54324/api/v1/search?query=${Uri.encodeQueryComponent('to:$email')}',
          ),
        );
        final messages = (search['messages'] as List?) ?? const [];
        if (messages.isNotEmpty) {
          final id = messages.first['ID'];
          final msg = await _getJson(
            http,
            Uri.parse('http://$mailHost:54324/api/v1/message/$id'),
          );
          final body = '${msg['HTML']} ${msg['Text']}';
          final m = RegExp(r'https?://[^\s"<>]*/auth/v1/verify\?[^\s"<>]+')
              .firstMatch(body.replaceAll('&amp;', '&'));
          link = m?.group(0);
        }
        if (link == null)
          await Future<void>.delayed(const Duration(seconds: 1));
      }
      h.note('V confirmation email found=${link != null}');
      var confirmStatus = -1;
      if (link != null) {
        final u = Uri.parse(link);
        final local = u.replace(host: mailHost);
        final req = await http.getUrl(local);
        req.followRedirects = false;
        final res = await req.close();
        confirmStatus = res.statusCode;
        await res.drain<void>();
      }
      final confirmed = confirmStatus == 302 || confirmStatus == 303;
      h.note('V confirmation link status=$confirmStatus confirmed=$confirmed');

      // Now sign in through the app.
      await tester.enterText(
        find.widgetWithText(TextField, 'Email').first,
        email,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password').first,
        'Test-Pass-12345',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await h.tapVisible(find.text('Sign In'), last: true);
      await tester.pump(const Duration(seconds: 6));
      await h.settle(3);
      final after = await _texts(h, 'V after confirming and signing in');
      final signedIn = NiswahSupabase.clientOrNull?.auth.currentSession != null;
      final onboarding =
          after.contains('Madhhab') || after.contains('Get Started');
      await h.shot('V', 'after_confirm_sign_in');

      final crashed = tester.takeException() != null;
      final pass =
          !crashed &&
          showsPending &&
          noSession &&
          refusedHonestly &&
          link != null &&
          confirmed &&
          signedIn &&
          onboarding;
      h.reportResult(
        PersonaResult(
          testId: 'AUTH08',
          expectedOutcome: 'AUTH-08: sign-up shows the pending-confirmation state with no session; sign-in before confirming is refused honestly; the real confirmation link then allows sign-in',
          actualOutcome:
              'crashed=$crashed pending=$showsPending noSession=$noSession refusedBeforeConfirm=$refusedHonestly linkFound=${link != null} confirmStatus=$confirmStatus signedInAfter=$signedIn reachedOnboarding=$onboarding',
          status: pass ? PersonaStatus.pass : PersonaStatus.fail,
          screenshotRef: 'V_check_your_email.png',
        ),
      );
    } finally {
      http.close(force: true);
    }
  });
}

Future<String> _texts(Harness h, String label) async {
  await h.settle(1);
  h.dumpTexts(label);
  return h.notes.last;
}

Future<Map<String, dynamic>> _getJson(HttpClient http, Uri uri) async {
  final req = await http.getUrl(uri);
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  return jsonDecode(body) as Map<String, dynamic>;
}
