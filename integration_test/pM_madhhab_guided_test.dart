import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 — MAD-01 guided Madhhab suggestion. "Help me choose" asks for a
/// country and offers a SUGGESTION that "only becomes your choice once you
/// confirm it yourself". Two real accounts prove both sides of that promise
/// against what the server persisted:
///  M1: suggestion shown -> nothing is stored yet -> the user confirms the
///      Shafi'i suggestion -> exactly that madhhab is persisted.
///  M2: same flow but "None of these — I'll decide later" -> NO madhhab is
///      stored (nothing assumed on the user's behalf).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MAD-01: guided Madhhab suggestion is never assumed', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('M')) return;
    final f = Flows(h);

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    Future<String?> storedMadhhab() async {
      final client = NiswahSupabase.clientOrNull;
      final uid = client?.auth.currentUser?.id;
      if (client == null || uid == null) return 'NO_SESSION';
      final row = await client
          .from('users')
          .select('madhhab')
          .eq('id', uid)
          .maybeSingle();
      return row?['madhhab'] as String?;
    }

    Future<String> reachSuggestion(String persona) async {
      await f.boot();
      final email = await f.signUpWithEmail(persona);
      h.note('LOOKUP_EMAIL_$persona=$email');
      await h.tapVisible(find.text('Create Account'));
      await h.waitFor(
        find.text('Get Started'),
        timeout: const Duration(seconds: 25),
      );
      await h.settle(2);
      await h.tapVisible(find.text('Get Started'));
      await h.settle(2);
      await h.tapVisible(find.text("I don't know my Madhhab"));
      await h.settle(2);
      await h.tapVisible(find.text('Help me choose'));
      await h.settle(3);
      await tester.enterText(find.byType(TextField).first, 'Egypt');
      await tester.pump(const Duration(milliseconds: 400));
      await h.tapVisible(find.text('Continue'));
      await h.settle(3);
      return texts('$persona suggestion screen');
    }

    // ---------------- M1: confirm the suggestion ----------------
    final s1 = await reachSuggestion('M1');
    final shown = s1.contains('A suggestion for you') && s1.contains("Shafi'i");
    await h.shot('M', 'suggestion');
    final beforeConfirm = await storedMadhhab();
    h.note('M1 suggestion shown=$shown storedBeforeConfirm=$beforeConfirm');
    await h.tapVisible(find.text("Yes, Shafi'i is my Madhhab"));
    await h.settle(3);
    // Finish onboarding so the choice is committed.
    await f.walkOnboarding('M1', [
      'Get Started',
      'I’m not sure',
      'Skip for now',
      'Continue',
    ], maxSteps: 10);
    await h.settle(2);
    final afterConfirm = await storedMadhhab();
    h.note('M1 storedAfterConfirm=$afterConfirm');
    final m1 =
        shown &&
        beforeConfirm == null &&
        (afterConfirm ?? '').toLowerCase().contains('shafi');

    // ---------------- sign out ----------------
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

    // ---------------- M2: decline the suggestion ----------------
    final s2 = await reachSuggestion('M2');
    final shown2 = s2.contains('A suggestion for you');
    await h.tapVisible(find.text('None of these — I\'ll decide later'));
    await h.settle(3);
    await f.walkOnboarding('M2', [
      'Get Started',
      'I’m not sure',
      'Skip for now',
      'Continue',
    ], maxSteps: 10);
    await h.settle(2);
    final afterDecline = await storedMadhhab();
    h.note('M2 shown=$shown2 storedAfterDecline=$afterDecline');
    final m2 = shown2 && afterDecline == null;

    final crashed = tester.takeException() != null;
    final pass = !crashed && m1 && m2;
    h.reportResult(
      PersonaResult(
        testId: 'M',
        expectedOutcome: 'MAD-01: the suggested Madhhab is stored only after the user confirms it; declining stores nothing',
        actualOutcome:
            'crashed=$crashed m1(shown=$shown before=$beforeConfirm after=$afterConfirm)=$m1 m2(shown=$shown2 afterDecline=$afterDecline)=$m2',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'M_suggestion.png',
      ),
    );
  });
}
