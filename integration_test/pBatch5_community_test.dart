import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 batch 5 — Community, one disposable account, real screens, each
/// state change verified against what the server actually holds (the
/// signed-in user reading their own rows through RLS):
///  COMM-09 empty state, COMM-01 create post, COMM-02 anonymous post,
///  COMM-03 search, COMM-04 like, COMM-05 post detail, COMM-06 delete own
///  post.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch 5: community posting lifecycle', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch5')) return;
    final f = Flows(h);

    final email = await f.newAccountOnDashboard('C');
    h.note('LOOKUP_EMAIL=$email');
    final client = NiswahSupabase.clientOrNull;
    final uid = client?.auth.currentUser?.id;

    Future<List<Map<String, dynamic>>> myPosts() async {
      if (client == null || uid == null) return const [];
      try {
        return List<Map<String, dynamic>>.from(
          await client
              .from('community_posts')
              .select()
              .eq('user_id', uid)
              .order('created_at'),
        );
      } catch (e) {
        h.note('C posts read failed: ${e.runtimeType}');
        return const [];
      }
    }

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    await h.scrollToTop();
    await h.tapVisible(find.text('Community'), last: true);
    await h.settle(3);
    await h.shot('C', 'community_empty');
    final emptyTexts = await texts('C community initial');
    final postsBefore = (await myPosts()).length;
    h.note('C COMM-09 initial posts on server for me=$postsBefore');

    Future<bool> publish(String body, {bool namedPost = false}) async {
      final opened = await h.tapVisible(find.bySemanticsLabel('Create post'));
      await h.settle(2);
      h.dumpTexts('C composer (opened=$opened)');
      final field = find.byType(TextField);
      if (field.evaluate().isEmpty) return false;
      await tester.enterText(field.last, body);
      await tester.pump(const Duration(milliseconds: 300));
      if (namedPost) {
        final sw = find.byType(Switch);
        if (sw.evaluate().isNotEmpty) {
          await h.tapVisible(sw);
          await h.settle(1);
        }
      }
      final tapped = await h.tapVisible(find.text('Publish post'));
      await tester.pump(const Duration(seconds: 4));
      await h.settle(2);
      return opened && tapped;
    }

    // ---------------- COMM-01: create a post ----------------
    final tag = DateTime.now().millisecondsSinceEpoch;
    final body1 = 'Synthetic acceptance post one $tag';
    final published1 = await publish(body1);
    final feed1 = await texts('C feed after post 1');
    final posts1 = await myPosts();
    final comm01 =
        published1 &&
        feed1.contains(body1) &&
        posts1.length == postsBefore + 1 &&
        posts1.any((p) => p['content'] == body1 && p['is_anonymous'] == true);
    h.note('C COMM-01 pass=$comm01 serverPosts=${posts1.length}');
    await h.shot('C', 'feed_after_post1');

    // ---------------- COMM-02: anonymous post ----------------
    final body2 = 'Synthetic named acceptance post $tag';
    final published2 = await publish(body2, namedPost: true);
    final posts2 = await myPosts();
    Map<String, dynamic>? anonRow;
    for (final p in posts2) {
      if (p['content'] == body2) anonRow = p;
    }
    final comm02 = published2 && anonRow != null && anonRow['is_anonymous'] == false;
    h.note('C COMM-02 pass=$comm02 anonRow=${anonRow?['is_anonymous']}');

    // ---------------- COMM-03: search ----------------
    final searchField = find.byType(TextField);
    var comm03 = false;
    if (searchField.evaluate().isNotEmpty) {
      await tester.enterText(searchField.first, 'named');
      await tester.pump(const Duration(seconds: 2));
      await h.settle(2);
      final searched = await texts('C feed filtered by "named"');
      comm03 = searched.contains(body2) && !searched.contains(body1);
      await tester.enterText(searchField.first, '');
      await tester.pump(const Duration(seconds: 1));
      await h.settle(2);
    }
    h.note('C COMM-03 pass=$comm03');

    // ---------------- COMM-04: like ----------------
    final likeFinder = find.bySemanticsLabel(RegExp('[Ll]ike'));
    var comm04 = false;
    final likesBefore = <String>{};
    if (likeFinder.evaluate().isNotEmpty) {
      await h.tapVisible(likeFinder);
      await tester.pump(const Duration(seconds: 3));
      await h.settle(2);
      if (client != null && uid != null) {
        final rows = await client
            .from('community_likes')
            .select()
            .eq('user_id', uid);
        comm04 = (rows as List).isNotEmpty;
        likesBefore.addAll(rows.map((r) => '${r['post_id']}'));
      }
    }
    h.note('C COMM-04 pass=$comm04 likedPosts=$likesBefore');

    // ---------------- COMM-05: open a post ----------------
    final openedDetail = await h.tapVisible(find.text(body1));
    await h.settle(3);
    await h.shot('C', 'post_detail');
    final detail = await texts('C post detail');
    final comm05 = openedDetail && detail.contains(body1);
    h.note('C COMM-05 pass=$comm05 opened=$openedDetail');

    // ---------------- COMM-06: delete own post (detail screen menu) ----------------
    var deleteTapped = false;
    if (find.byType(PopupMenuButton<String>).evaluate().isNotEmpty) {
      await h.tapVisible(find.byType(PopupMenuButton<String>));
      await h.settle(2);
      final menuItem = await h.tapVisible(find.text('Delete post'));
      await h.settle(2);
      h.dumpTexts('C delete confirmation');
      final confirmed = await h.tapVisible(find.text('Delete'), last: true);
      await tester.pump(const Duration(seconds: 4));
      await h.settle(3);
      deleteTapped = menuItem && confirmed;
    }
    await h.settle(2);
    final feedAfterDelete = await texts('C feed after delete');
    final postsAfterDelete = await myPosts();
    final comm06 = deleteTapped &&
        postsAfterDelete.length == posts2.length - 1 &&
        !postsAfterDelete.any((p) => p['content'] == body1) &&
        !feedAfterDelete.contains(body1);
    h.note(
      'C COMM-06 pass=$comm06 deleteTapped=$deleteTapped '
      'server=${postsAfterDelete.length} (was ${posts2.length})',
    );
    await h.shot('C', 'feed_after_delete');

    final crashed = tester.takeException() != null;
    final pass = !crashed && comm01 && comm02 && comm03 && comm04 && comm05 && comm06;
    h.reportResult(
      PersonaResult(
        testId: 'Batch5',
        expectedOutcome:
            'COMM-01/02/03/04/05/06: post, anonymous post, search, like, '
            'detail and delete-own-post change the real feed AND the '
            'server rows',
        actualOutcome:
            'crashed=$crashed comm01_create=$comm01 comm02_anonymous=$comm02 '
            'comm03_search=$comm03 comm04_like=$comm04 '
            'comm05_detail=$comm05 comm06_delete=$comm06 emptyStateSeen='
            '${emptyTexts.isNotEmpty}',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'C_feed_after_delete.png',
      ),
    );
  });
}
