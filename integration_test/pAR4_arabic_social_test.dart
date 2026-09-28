import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/arabic_audit.dart';
import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 4 — Arabic critical path, part 3: Community and private Messaging
/// between two REAL accounts, entirely in Arabic (account creation is the
/// shared English path; the language is switched from Profile and stays Arabic
/// through sign-out / sign-in). Every screen goes through ArabicAudit; the
/// post, the message and the read state are checked on the server.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Arabic social journey: community post + private messaging', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('AR4')) return;
    final f = Flows(h);
    final audit = ArabicAudit(h);
    const userText = {'Persona', 'Synthetic'};

    Future<void> toArabic() async {
      await h.scrollToTop();
      await h.tapVisible(find.text('Profile'), last: true);
      await h.settle(2);
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -2500),
        warnIfMissed: false,
      );
      await h.settle(1);
      await h.tapVisible(find.text('AR'));
      await h.settle(3);
    }

    Future<void> signOut() async {
      await h.scrollToTop();
      await h.tapVisible(find.text('الملف الشخصي'), last: true);
      await h.settle(2);
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -3000),
        warnIfMissed: false,
      );
      await h.settle(1);
      await h.tapVisible(find.textContaining('تسجيل الخروج'));
      await h.settle(2);
      if (find.textContaining('تسجيل الخروج').evaluate().isNotEmpty) {
        await h.tapVisible(find.textContaining('تسجيل الخروج'), last: true);
        await h.settle(2);
      }
    }

    Future<void> signInArabic(String email) async {
      await f.acceptConsent();
      await h.tapVisible(find.text('البريد الإلكتروني'));
      await h.settle();
      await h.tapVisible(find.byKey(const Key('mode_tab_sign_in')));
      await h.settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'البريد الإلكتروني').first,
        email,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور').first,
        'Test-Pass-12345',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await h.tapVisible(find.text('تسجيل الدخول'), last: true);
      await tester.pump(const Duration(seconds: 6));
      await h.settle(3);
    }

    Future<void> tab(String label) async {
      await h.scrollToTop();
      await h.tapVisible(find.text(label), last: true);
      await h.settle(3);
    }

    // ================= account A: a named post =================
    final emailA = await f.newAccountOnDashboard('A4');
    h.note('LOOKUP_EMAIL_A=$emailA');
    await toArabic();
    await tab('المجتمع');
    await audit.audit('community (empty feed)', userContent: userText);
    final tag = DateTime.now().millisecondsSinceEpoch;
    final body = 'Synthetic arabic-mode post $tag';
    await h.tapVisible(find.bySemanticsLabel('اكتبي منشورًا'));
    await h.settle(2);
    await audit.audit('community composer', userContent: userText);
    await tester.enterText(find.byType(TextField).last, body);
    await tester.pump(const Duration(milliseconds: 300));
    await h.tapVisible(find.byType(Switch)); // default anonymous -> named
    await h.settle(1);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 800));
    await h.tapVisible(find.text('نشر المنشور'));
    await tester.pump(const Duration(seconds: 4));
    await h.settle(2);
    await audit.audit(
      'community feed (own post)',
      userContent: {...userText, body},
    );
    final client = NiswahSupabase.clientOrNull!;
    final posts =
        (await client.from('community_posts').select().eq('content', body))
            .length;
    await signOut();

    // ================= account B: preview + message the author =================
    final emailB = await f.newAccountOnDashboard('B4');
    h.note('LOOKUP_EMAIL_B=$emailB');
    await toArabic();
    await tab('المجتمع');
    await audit.audit(
      'community (other author\'s post)',
      userContent: {...userText, body},
    );
    final sees = audit.visibleTexts().any((t) => t.contains(body));
    await h.tapVisible(find.textContaining('Persona A4').first);
    await h.settle(2);
    await audit.audit('author preview sheet', userContent: {...userText, body});
    await tester.tapAt(const Offset(200, 80));
    await h.settle(2);
    await h.tapVisible(find.text('تواصلي معها').first);
    await h.settle(3);
    await audit.audit('private chat (empty)', userContent: userText);
    final msg = 'Synthetic arabic hello $tag';
    await tester.enterText(find.byType(TextField).last, msg);
    await tester.pump(const Duration(milliseconds: 300));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    await h.tapVisible(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(seconds: 3));
    await h.settle(2);
    await audit.audit('private chat (sent)', userContent: {...userText, msg});
    final sent =
        (await client.from('private_messages').select().eq('content', msg))
            .length;
    if (find.byType(BackButton).evaluate().isNotEmpty) {
      await h.tapVisible(find.byType(BackButton));
      await h.settle(2);
    }
    if (find.text('الملف الشخصي').evaluate().isEmpty) {
      await binding.handlePopRoute();
      await h.settle(2);
    }
    await signOut();

    // ================= account A signs in (Arabic) and reads it =================
    await signInArabic(emailA);
    await tab('المجتمع');
    await h.tapVisible(find.text('رسائلي').first);
    await h.settle(3);
    await audit.audit('messages inbox', userContent: userText);
    final inboxHasConversation = audit.visibleTexts().any(
      (t) => t.contains('اضغطي لفتح المحادثة'),
    );
    await h.tapVisible(find.text('اضغطي لفتح المحادثة').first);
    await h.settle(3);
    await audit.audit('conversation thread', userContent: {...userText, msg});
    final received = audit.visibleTexts().any((t) => t.contains(msg));
    final unread =
        (await NiswahSupabase.clientOrNull!
                .from('private_messages')
                .select('id')
                .eq('is_read', false))
            .length;

    final crashed = tester.takeException() != null;
    for (final finding in audit.findings) {
      h.note('AR4 FINDING: $finding');
    }
    final pass =
        !crashed &&
        posts == 1 &&
        sees &&
        sent == 1 &&
        inboxHasConversation &&
        received &&
        unread == 0 &&
        audit.findings.isEmpty;
    h.reportResult(
      PersonaResult(
        testId: 'AR4',
        expectedOutcome:
            'Community posting and private messaging between two accounts work '
            'in Arabic with RTL layout, no English remnants around the user '
            'content, mirrored icons and no overflow at 1.6x text scale',
        actualOutcome:
            'crashed=$crashed serverPosts=$posts otherSeesPost=$sees '
            'serverMessages=$sent inbox=$inboxHasConversation received=$received '
            'unreadAfterOpen=$unread ${audit.summary}',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'AR4_thread.png',
      ),
    );
  });
}
