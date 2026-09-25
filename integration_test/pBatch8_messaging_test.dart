import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 batch 8 — Community author preview, private messaging between
/// two REAL accounts, unread state, and cross-account privacy (RLS) seen by
/// a third real account:
///  COMM-07 author preview, COMM-08 message author, MSG-01 conversation
///  opens/creates, MSG-02 send, MSG-03 receive (as the other account),
///  MSG-04 unread -> read, MSG-05 history, MSG-07 a third account cannot
///  read or write the conversation. MSG-06 (delete conversation) has no UI
///  or repository method, which is reported as a finding, not a pass.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch 8: two-account messaging + RLS', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch8')) return;
    final f = Flows(h);

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    Future<void> signOut() async {
      await h.scrollToTop();
      await h.tapVisible(find.text('Profile'), last: true);
      await h.settle(2);
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -3000),
        warnIfMissed: false,
      );
      await h.settle(1);
      await h.tapVisible(find.textContaining('Sign Out'));
      await h.settle(2);
      if (find.textContaining('Sign Out').evaluate().isNotEmpty) {
        await h.tapVisible(find.textContaining('Sign Out'), last: true);
        await h.settle(2);
      }
    }

    Future<void> signIn(String email) async {
      await f.acceptConsent();
      await h.tapVisible(find.text('Email'));
      await h.settle();
      await h.tapVisible(find.byKey(const Key('mode_tab_sign_in')));
      await h.settle();
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
    }

    String? uid() => NiswahSupabase.clientOrNull?.auth.currentUser?.id;

    // ---------------- Account A publishes a NAMED post ----------------
    final emailA = await f.newAccountOnDashboard('MA');
    h.note('LOOKUP_EMAIL_A=$emailA');
    final uidA = uid();
    final tag = DateTime.now().millisecondsSinceEpoch;
    final body = 'Synthetic messaging post $tag';
    await h.scrollToTop();
    await h.tapVisible(find.text('Community'), last: true);
    await h.settle(3);
    await h.tapVisible(find.bySemanticsLabel('Create post'));
    await h.settle(2);
    await tester.enterText(find.byType(TextField).last, body);
    await tester.pump(const Duration(milliseconds: 300));
    await h.tapVisible(find.byType(Switch)); // default anonymous -> named
    await h.settle(1);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 800));
    await h.tapVisible(find.text('Publish post'));
    await tester.pump(const Duration(seconds: 4));
    await h.settle(2);
    final postedNamed = (await texts('MA feed')).contains(body);
    await signOut();
    await texts('after A sign out');

    // ---------------- Account B: preview + message author ----------------
    final emailB = await f.newAccountOnDashboard('MB');
    h.note('LOOKUP_EMAIL_B=$emailB');
    final uidB = uid();
    await h.scrollToTop();
    await h.tapVisible(find.text('Community'), last: true);
    await h.settle(3);
    final bSeesPost = (await texts('MB feed')).contains(body);

    // COMM-07: tap the author name -> preview sheet.
    await h.tapVisible(find.text('Persona MA').first);
    await h.settle(2);
    final previewTexts = await texts('MB author preview');
    final comm07 =
        previewTexts.contains('Persona MA') &&
        previewTexts.contains('public posts');
    await h.shot('M', 'author_preview');
    // Dismiss the sheet (tap the scrim above it).
    await tester.tapAt(const Offset(200, 80));
    await h.settle(2);

    // COMM-08 / MSG-01: "Connect" on the post opens a private chat.
    await h.tapVisible(find.text('Connect').first);
    await h.settle(3);
    final chatTexts = await texts('MB chat opened');
    final chatOpen =
        chatTexts.contains('Write a message') ||
        find.byIcon(Icons.send_rounded).evaluate().isNotEmpty;
    await h.shot('M', 'chat_opened');

    // MSG-02: send.
    final msgText = 'Synthetic hello $tag';
    if (chatOpen) {
      await tester.enterText(find.byType(TextField).last, msgText);
      await tester.pump(const Duration(milliseconds: 300));
      await h.tapVisible(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(seconds: 3));
      await h.settle(2);
    }
    final sentShown = (await texts('MB after send')).contains(msgText);
    final clientB = NiswahSupabase.clientOrNull;
    List<dynamic> convB = const [];
    List<dynamic> msgsB = const [];
    if (clientB != null) {
      convB = await clientB.from('private_conversations').select();
      msgsB = await clientB
          .from('private_messages')
          .select()
          .eq('content', msgText);
    }
    final convId = convB.isNotEmpty ? '${convB.first['id']}' : '';
    final serverSent =
        convB.length == 1 &&
        msgsB.length == 1 &&
        msgsB.first['sender_id'] == uidB &&
        msgsB.first['is_read'] == false;
    h.note(
      'M MSG-01/02 conversations=${convB.length} messages=${msgsB.length} '
      'sender==B:${msgsB.isNotEmpty && msgsB.first['sender_id'] == uidB} '
      'unread=${msgsB.isNotEmpty ? msgsB.first['is_read'] == false : null}',
    );

    // Leave chat, sign out B.
    if (find.byType(BackButton).evaluate().isNotEmpty) {
      await h.tapVisible(find.byType(BackButton));
    } else if (find.byIcon(Icons.arrow_back_ios_new).evaluate().isNotEmpty) {
      await h.tapVisible(find.byIcon(Icons.arrow_back_ios_new));
    } else if (find.byIcon(Icons.arrow_back).evaluate().isNotEmpty) {
      await h.tapVisible(find.byIcon(Icons.arrow_back));
    }
    await h.settle(2);
    // Back out of post detail if we are still on it.
    if (find.text('Profile').evaluate().isEmpty) {
      if (find.byType(BackButton).evaluate().isNotEmpty) {
        await h.tapVisible(find.byType(BackButton));
      } else if (find.byIcon(Icons.arrow_back_ios_new).evaluate().isNotEmpty) {
        await h.tapVisible(find.byIcon(Icons.arrow_back_ios_new));
      }
      await h.settle(2);
    }
    await signOut();

    // ---------------- Account C (third party): RLS ----------------
    final emailC = await f.newAccountOnDashboard('MC');
    h.note('LOOKUP_EMAIL_C=$emailC');
    final clientC = NiswahSupabase.clientOrNull;
    var cReadsConv = -1;
    var cReadsMsg = -1;
    var cWriteBlocked = false;
    if (clientC != null && convId.isNotEmpty) {
      cReadsConv =
          (await clientC.from('private_conversations').select().eq('id', convId))
              .length;
      cReadsMsg =
          (await clientC
                  .from('private_messages')
                  .select()
                  .eq('conversation_id', convId))
              .length;
      try {
        await clientC.from('private_messages').insert({
          'conversation_id': convId,
          'sender_id': uid(),
          'content': 'intruder $tag',
        });
      } catch (e) {
        cWriteBlocked = true;
        h.note('M RLS blocked intruder write: ${e.runtimeType}');
      }
      // Attempt to forge a message as B in the conversation.
      try {
        await clientC.from('private_messages').insert({
          'conversation_id': convId,
          'sender_id': uidB,
          'content': 'forged $tag',
        });
        cWriteBlocked = false;
      } catch (_) {}
    }
    final msg07 = cReadsConv == 0 && cReadsMsg == 0 && cWriteBlocked;
    h.note(
      'M MSG-07 RLS: C reads conversations=$cReadsConv messages=$cReadsMsg '
      'writeBlocked=$cWriteBlocked',
    );
    await signOut();

    // ---------------- Account A receives, reads ----------------
    await signIn(emailA);
    final aSignedIn = uid() == uidA;
    final clientA = NiswahSupabase.clientOrNull;
    int unreadBefore = -1;
    if (clientA != null) {
      unreadBefore =
          (await clientA
                  .from('private_messages')
                  .select('id')
                  .eq('is_read', false)
                  .neq('sender_id', uidA!))
              .length;
    }
    await h.scrollToTop();
    await h.tapVisible(find.text('Community'), last: true);
    await h.settle(3);
    await texts('MA community with unread');
    await h.shot('M', 'A_community_unread');
    await h.tapVisible(find.text('Messages').first);
    await h.settle(3);
    final inbox = await texts('MA messages inbox');
    await h.shot('M', 'A_inbox');
    final inboxHasConversation = !inbox.contains('No conversations yet');
    await h.tapVisible(find.text('Tap to open chat').first);
    await h.settle(3);
    final thread = await texts('MA conversation thread');
    final receivedShown = thread.contains(msgText);
    await h.shot('M', 'A_thread');
    int unreadAfter = -1;
    if (clientA != null) {
      unreadAfter =
          (await clientA
                  .from('private_messages')
                  .select('id')
                  .eq('is_read', false)
                  .neq('sender_id', uidA!))
              .length;
    }
    final msg04 = unreadBefore == 1 && unreadAfter == 0;
    h.note(
      'M MSG-03/04 signedInAsA=$aSignedIn inbox=$inboxHasConversation '
      'received=$receivedShown unread $unreadBefore -> $unreadAfter',
    );

    // A replies; history (MSG-05) = both messages on the server, in order.
    final replyText = 'Synthetic reply $tag';
    await tester.enterText(find.byType(TextField).last, replyText);
    await tester.pump(const Duration(milliseconds: 300));
    await h.tapVisible(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(seconds: 3));
    await h.settle(2);
    final thread2 = await texts('MA thread after reply');
    List<dynamic> history = const [];
    if (clientA != null && convId.isNotEmpty) {
      history = await clientA
          .from('private_messages')
          .select()
          .eq('conversation_id', convId)
          .order('created_at', ascending: true);
    }
    final msg05 =
        thread2.contains(msgText) &&
        thread2.contains(replyText) &&
        history.length == 2 &&
        history[0]['content'] == msgText &&
        history[1]['content'] == replyText;
    h.note(
      'M MSG-05 history=${history.length} ordered=$msg05 '
      'contents=${history.map((m) => m['content']).toList()} convId=$convId',
    );

    // Raw identifiers must not be shown as the conversation title.
    final rawUuid = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    );
    final showsRawUuid = rawUuid.hasMatch(inbox) || rawUuid.hasMatch(thread);
    h.note('M FINDING inbox/thread expose a raw user id: $showsRawUuid');

    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        postedNamed &&
        bSeesPost &&
        comm07 &&
        chatOpen &&
        sentShown &&
        serverSent &&
        msg07 &&
        aSignedIn &&
        inboxHasConversation &&
        receivedShown &&
        msg04 &&
        msg05 &&
        !showsRawUuid;
    h.reportResult(
      PersonaResult(
        testId: 'Batch8',
        expectedOutcome:
            'COMM-07/08, MSG-01..05 and MSG-07: two real accounts exchange '
            'private messages, unread flips to read on open, history is '
            'ordered, and a third account can neither read nor write the '
            'conversation',
        actualOutcome:
            'crashed=$crashed postedNamed=$postedNamed bSeesPost=$bSeesPost '
            'comm07=$comm07 chatOpen=$chatOpen sentShown=$sentShown '
            'serverSent=$serverSent msg07=$msg07 aSignedIn=$aSignedIn '
            'inbox=$inboxHasConversation received=$receivedShown '
            'msg04=$msg04 msg05=$msg05 rawUserIdShown=$showsRawUuid',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'M_A_thread.png',
      ),
    );
  });
}
