import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 — REAL backend outages (the host stops/starts the local backend
/// on the "OUTAGE START/END n" marker lines; see
/// scripts/run_persona_outage.sh):
///  ONB-12  onboarding save failure + retry: with the backend down the
///          final onboarding save fails HONESTLY (answers kept, "Try
///          again"), and after reconnect the SAME answers save on retry,
///          producing exactly one episode.
///  COMM-10 community backend failure: with the backend down, publishing
///          fails honestly (no crash/raw exception, nothing shown as
///          posted), and after reconnect a retry publishes exactly one post.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Outage honesty: onboarding save retry + community failure', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('O')) return;
    final f = Flows(h);
    final health = Uri.parse('${dotenv.env['SUPABASE_URL']}/auth/v1/health');

    Future<bool> reachable() async {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      try {
        final r = await (await c.getUrl(health)).close();
        await r.drain<void>();
        return r.statusCode == 200;
      } catch (_) {
        return false;
      } finally {
        c.close(force: true);
      }
    }

    Future<bool> waitReachable(bool wantUp) async {
      for (var i = 0; i < 60; i++) {
        if (await reachable() == wantUp) return true;
        await tester.pump(const Duration(seconds: 1));
      }
      return false;
    }

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    bool leaksRaw(String s) =>
        s.contains('SocketException') ||
        s.contains('Connection refused') ||
        s.contains('ClientException') ||
        s.contains('PostgrestException') ||
        s.contains('AuthRetryableFetchException');

    // ---------------- ONB-12: onboarding save failure + retry ----------------
    var wentDownForOnboarding = false;
    var failedTexts = '';
    final email = await f.newAccountWithRealHistory(
      'O',
      beforeFinish: () async {
        h.note('OUTAGE START 1');
        wentDownForOnboarding = await waitReachable(false);
      },
    );
    h.note('LOOKUP_EMAIL=$email');
    await tester.pump(const Duration(seconds: 6));
    await h.settle(2);
    failedTexts = await texts('O onboarding after save attempt (backend down)');
    final onbHonest = failedTexts.contains("couldn't save the information");
    final onbRetryOffered = failedTexts.contains('Try again');
    final onbLeak = leaksRaw(failedTexts);
    await h.shot('O', 'onboarding_save_failed');
    h.note(
      'O ONB-12 down=$wentDownForOnboarding honest=$onbHonest '
      'retryOffered=$onbRetryOffered rawLeak=$onbLeak',
    );

    h.note('OUTAGE END 1');
    final backUp1 = await waitReachable(true);
    await tester.pump(const Duration(seconds: 8)); // let auth/rest settle
    await h.tapVisible(find.text('Try again'));
    await tester.pump(const Duration(seconds: 8));
    await h.settle(3);
    final afterRetry = await texts('O onboarding after retry');
    final reachedDashboard =
        afterRetry.contains('WELCOME') || afterRetry.contains('Niswah');
    final client = NiswahSupabase.clientOrNull;
    var episodes = -1;
    if (client != null) {
      episodes = (await client.from('bleeding_episodes').select('id')).length;
    }
    final onb12 =
        wentDownForOnboarding &&
        onbHonest &&
        onbRetryOffered &&
        !onbLeak &&
        backUp1 &&
        reachedDashboard &&
        episodes == 1;
    h.note(
      'O ONB-12 pass=$onb12 backUp=$backUp1 dashboard=$reachedDashboard '
      'episodesAfterRetry=$episodes',
    );

    // ---------------- COMM-10: community publish during outage ----------------
    final tag = DateTime.now().millisecondsSinceEpoch;
    final body = 'Synthetic outage post $tag';
    await h.scrollToTop();
    await h.tapVisible(find.text('Community'), last: true);
    await h.settle(3);
    await h.tapVisible(find.bySemanticsLabel('Create post'));
    await h.settle(2);
    await tester.enterText(find.byType(TextField).last, body);
    await tester.pump(const Duration(milliseconds: 300));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 800));

    h.note('OUTAGE START 2');
    final wentDown2 = await waitReachable(false);
    await h.tapVisible(find.text('Publish post'));
    await tester.pump(const Duration(seconds: 8));
    await h.settle(2);
    final offlinePublish = await texts('O community publish (backend down)');
    final commLeak = leaksRaw(offlinePublish);
    // Nothing may be presented as successfully posted while down.
    final shownAsPosted =
        offlinePublish.contains('Just now') && offlinePublish.contains(body);
    await h.shot('O', 'community_publish_backend_down');
    final crashed1 = tester.takeException() != null;
    h.note(
      'O COMM-10 down=$wentDown2 rawLeak=$commLeak shownAsPosted=$shownAsPosted '
      'crashed=$crashed1',
    );

    h.note('OUTAGE END 2');
    final backUp2 = await waitReachable(true);
    await tester.pump(const Duration(seconds: 8));
    // Retry from whatever state the composer is in.
    if (find.text('Publish post').evaluate().isEmpty) {
      await h.tapVisible(find.bySemanticsLabel('Create post'));
      await h.settle(2);
    }
    if (find.byType(TextField).evaluate().isNotEmpty) {
      final field = tester.widget<TextField>(find.byType(TextField).last);
      if ((field.controller?.text ?? '') != body) {
        await tester.enterText(find.byType(TextField).last, body);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 800));
    await h.tapVisible(find.text('Publish post'));
    await tester.pump(const Duration(seconds: 6));
    await h.settle(3);
    final afterRetryFeed = await texts('O community after retry');
    var posts = -1;
    final c2 = NiswahSupabase.clientOrNull;
    final uid = c2?.auth.currentUser?.id;
    if (c2 != null && uid != null) {
      posts =
          (await c2
                  .from('community_posts')
                  .select('id')
                  .eq('user_id', uid)
                  .eq('content', body))
              .length;
    }
    final comm10 =
        wentDown2 &&
        !commLeak &&
        !shownAsPosted &&
        !crashed1 &&
        backUp2 &&
        afterRetryFeed.contains(body) &&
        posts == 1;
    h.note('O COMM-10 pass=$comm10 serverPostsForBody=$posts');

    final crashed = tester.takeException() != null;
    final pass = !crashed && onb12 && comm10;
    h.reportResult(
      PersonaResult(
        testId: 'O',
        expectedOutcome: 'ONB-12: onboarding save fails honestly during a real outage and the same answers save exactly once on retry; COMM-10: community publish fails honestly during a real outage (no crash/raw exception/false success) and a retry publishes exactly one post',
        actualOutcome:
            'crashed=$crashed onb12=$onb12 (honest=$onbHonest retry=$onbRetryOffered episodes=$episodes) comm10=$comm10 (leak=$commLeak falseSuccess=$shownAsPosted serverPosts=$posts)',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'O_community_publish_backend_down.png',
      ),
    );
  });
}
