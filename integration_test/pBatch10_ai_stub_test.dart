import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/ai_function_gateway.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 batch 10 — AI features driven through the AiFunctionGateway test
/// seam (no live model, so NO answer-quality claim is made):
///  AI-08  malformed replies fail honestly (no blank bubble, and no urgent
///         red-flag banner for a routine question);
///  AI-05  conversation history: a persisted conversation is listed and
///         reopens with both messages;
///  AI-06  deleting a conversation removes it from the picker AND the server;
///  request contract: what the app SENDS (the message text and the madhhab
///         context — never a fabricated madhhab).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Batch 10: stubbed AI — malformed replies, history, delete, request contract',
    (tester) async {
      app.main();
      final h = Harness(binding, tester);
      if (!await h.guardBackend('Batch10')) return;
      final f = Flows(h);

      final email = await f.newAccountOnDashboard('AS');
      h.note('LOOKUP_EMAIL=$email');
      final client = NiswahSupabase.clientOrNull;
      final uid = client?.auth.currentUser?.id;

      final requests = <String, List<Map<String, dynamic>?>>{};
      Object? nextReply;
      AiFunctionGateway.testOverride = (name, body) async {
        requests.putIfAbsent(name, () => []).add(body);
        return FunctionResponse(status: 200, data: nextReply);
      };
      addTearDown(() => AiFunctionGateway.testOverride = null);

      Future<String> texts(String label) async {
        await h.settle(1);
        h.dumpTexts(label);
        return h.notes.last;
      }

      Future<void> scrollUntil(Finder target) async {
        await h.scrollToTop();
        for (var i = 0; i < 14 && target.evaluate().isEmpty; i++) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -500),
            warnIfMissed: false,
          );
          await tester.pump(const Duration(milliseconds: 400));
        }
        await h.settle(1);
      }

      Future<bool> send(String text) async {
        final field = find.byType(TextField);
        if (field.evaluate().isEmpty) return false;
        await tester.enterText(field.last, text);
        await tester.pump(const Duration(milliseconds: 300));
        var typed = tester.widget<TextField>(field.last).controller?.text;
        if (typed != text) {
          // The simulated IME sometimes drops the text after an earlier
          // failure; the composer's own controller is the source of truth
          // for what a send will submit, so set it directly.
          tester.widget<TextField>(field.last).controller?.text = text;
          typed = tester.widget<TextField>(field.last).controller?.text;
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 500));
        final buttons = find.byType(IconButton);
        h.note(
          'AS send(): typed="$typed" textFields=${field.evaluate().length} '
          'iconButtons=${buttons.evaluate().length} enabled='
          '${buttons.evaluate().map((e) => (e.widget as IconButton).onPressed != null).toList()}',
        );
        for (final send in [
          find.byIcon(Icons.send),
          find.byIcon(Icons.send_rounded),
          find.byIcon(Icons.arrow_upward),
          find.byIcon(Icons.arrow_upward_rounded),
        ]) {
          if (send.evaluate().isNotEmpty) {
            final ok = await h.tapVisible(send);
            await tester.pump(const Duration(seconds: 4));
            await h.settle(2);
            return ok;
          }
        }
        return false;
      }

      Future<void> closeChat() async {
        await h.tapVisible(find.byIcon(Icons.close_rounded));
        await h.settle(2);
      }

      Future<void> openGeneral() async {
        await scrollUntil(
          find.textContaining('Ask any Fiqh or health question'),
        );
        await h.tapVisible(
          find.textContaining('Ask any Fiqh or health question'),
        );
        await h.settle(3);
      }

      // ---------------- General assistant: malformed then well-formed ----------------
      await openGeneral();
      nextReply = <String, dynamic>{}; // malformed: a Map with no text
      final sentBad = await send('Synthetic malformed question');
      final afterBad = await texts('AS general after malformed reply');
      final honestFailure = afterBad.contains('could not be sent');
      final noBlankBubble = !afterBad.contains('Niswah AI |  |');
      h.note('AS AI-08 general sent=$sentBad honest=$honestFailure');

      nextReply = <String, dynamic>{'text': 'Stub general answer'};
      final sentGood = await send('Synthetic history question');
      final afterGood = await texts('AS general after good reply');
      final answerShown = afterGood.contains('Stub general answer');
      final generalRequests = requests['ai-assistant-chat'] ?? const [];
      final lastGeneral = generalRequests.isNotEmpty
          ? generalRequests.last
          : null;
      final requestContract =
          lastGeneral != null &&
          lastGeneral['content'] == 'Synthetic history question' &&
          lastGeneral.containsKey('madhhab') &&
          lastGeneral['madhhab'] ==
              null && // "I don't know" was chosen: never fabricated
          lastGeneral['madhhab_state'] ==
              'unknown'; // "I don't know" is UNKNOWN, not unset
      h.note(
        'AS contract general request=$lastGeneral sent=$sentGood shown=$answerShown',
      );

      // Server rows written by the client for this conversation.
      var threads = -1;
      var messages = -1;
      if (client != null && uid != null) {
        threads =
            (await client.from('chat_threads').select('id').eq('user_id', uid))
                .length;
        messages =
            (await client.from('chat_messages').select('id').eq('user_id', uid))
                .length;
      }
      h.note('AS server rows threads=$threads messages=$messages');

      // ---------------- AI-05: history ----------------
      await closeChat();
      await openGeneral();
      final picker = await texts('AS reopened -> history picker');
    // The picker lists threads by their default (timestamp) title.
    final listed = find.byType(ListTile).evaluate().isNotEmpty;
    if (listed) {
      await h.tapVisible(find.byType(ListTile).first);
      await h.settle(3);
    }
    h.note('AS picker had a ListTile=$listed (${picker.length} chars)');
    final reopened = await texts('AS conversation reopened');
    final ai05 =
        listed &&
        reopened.contains('Synthetic history question') &&
        reopened.contains('Stub general answer');
    h.note('AS AI-05 listed=$listed restored=$ai05');

      // ---------------- AI-06: delete ----------------
      // Back to the picker (History button), then delete.
      final historyButton = find.byTooltip('History');
      if (historyButton.evaluate().isNotEmpty) {
        await h.tapVisible(historyButton);
        await h.settle(2);
      } else {
        await closeChat();
        await openGeneral();
      }
      await texts('AS picker before delete');
      final deleteIcon = find.byIcon(Icons.delete_outline_rounded);
      var deleted = false;
      if (deleteIcon.evaluate().isNotEmpty) {
        await h.tapVisible(deleteIcon);
        await h.settle(2);
        await texts('AS delete confirmation');
        deleted = await h.tapVisible(find.text('Delete'), last: true);
        await tester.pump(const Duration(seconds: 3));
        await h.settle(2);
      }
      var threadsAfter = -1;
      var messagesAfter = -1;
      if (client != null && uid != null) {
        threadsAfter =
            (await client.from('chat_threads').select('id').eq('user_id', uid))
                .length;
        messagesAfter =
            (await client.from('chat_messages').select('id').eq('user_id', uid))
                .length;
      }
      final afterDelete = await texts('AS after delete');
      final ai06 =
          deleted &&
          threads >= 1 &&
          threadsAfter == 0 &&
          messagesAfter == 0 &&
          !afterDelete.contains('Synthetic history question');
      h.note(
        'AS AI-06 deleted=$deleted threads $threads -> $threadsAfter messages $messages -> $messagesAfter',
      );
      await closeChat();

      // ---------------- Doctor Niswah: malformed must not become the urgent banner ----------------
      await scrollUntil(find.text('Doctor Niswah'));
      await h.tapVisible(find.text('Doctor Niswah'));
      await h.settle(3);
      nextReply = <String, dynamic>{'reply': '', 'urgent': false};
      await send('What is a normal cycle length?');
      final doctorBad = await texts('AS doctor after empty reply');
      // The Arabic red-flag banner starts with this phrase (DrNiswahRedFlags.bannerTextAr).
      final noUrgentBanner = !RegExp(r'[؀-ۿ]')
          .hasMatch(doctorBad.replaceAll(RegExp(r'[^\u0000-ɏ؀-ۿ]'), ''));
      final doctorHonest = doctorBad.contains('could not be sent');
      h.note(
        'AS AI-08 doctor honest=$doctorHonest noUrgentBanner=$noUrgentBanner',
      );
      nextReply = <String, dynamic>{
        'reply': 'Stub doctor answer',
        'urgent': false,
      };
      await send('Second question');
      final doctorGood = await texts('AS doctor after good reply');
      final doctorReqs = requests['dr-niswah-chat'] ?? const [];
      final doctorContract =
          doctorGood.contains('Stub doctor answer') &&
          doctorReqs.isNotEmpty &&
          doctorReqs.last?['content'] == 'Second question' &&
          (doctorReqs.last?['threadId'] as String?)?.isNotEmpty == true;
      h.note(
        'AS doctor contract=$doctorContract request=${doctorReqs.isNotEmpty ? doctorReqs.last : null}',
      );

      final crashed = tester.takeException() != null;
      final pass =
          !crashed &&
          honestFailure &&
          noBlankBubble &&
          answerShown &&
          requestContract &&
          threads >= 1 &&
          messages >= 2 &&
          ai05 &&
          ai06 &&
          doctorHonest &&
          noUrgentBanner &&
          doctorContract;
      h.reportResult(
        PersonaResult(
          testId: 'Batch10',
          expectedOutcome:
              'With a stubbed backend: malformed replies fail honestly (no blank '
              'bubble, no urgent banner for a routine question); a persisted '
              'conversation is listed and restores; deleting it removes the '
              'server rows; requests carry the message and the (unfabricated) '
              'madhhab context',
          actualOutcome:
              'crashed=$crashed general(honest=$honestFailure noBlank=$noBlankBubble '
              'answer=$answerShown contract=$requestContract) '
              'serverRows(threads=$threads messages=$messages) ai05=$ai05 '
              'ai06=$ai06 doctor(honest=$doctorHonest noBanner=$noUrgentBanner '
              'contract=$doctorContract)',
          status: pass ? PersonaStatus.pass : PersonaStatus.fail,
          screenshotRef: 'AS_general_after_good_reply.png',
        ),
      );
    },
  );
}
