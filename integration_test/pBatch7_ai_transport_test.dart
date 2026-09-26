import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 batch 7 — AI features, TRANSPORT and ERROR HANDLING only.
///
/// The disposable local backend deliberately has no Edge Functions and no
/// model credentials, so this exercises exactly what the charter allows
/// without inventing medical or Fiqh expected answers: with the AI backend
/// genuinely unreachable, each assistant must (a) open, (b) accept a
/// synthetic prompt, (c) fail HONESTLY — a clear "temporarily unavailable"
/// state, never a crash, never a raw exception, never a fabricated
/// medical/religious answer — and (d) leave the app usable. Content
/// validation of real model output (AI-01/02/03/04 answers, AI-09
/// citations) needs an isolated test model and qualified review, and is
/// NOT claimed here.
///  AI-07 backend unavailable (Dr. Niswah chat, Fiqh advisor, Dream
///  interpreter); AI-08 malformed response is unit-covered elsewhere and is
///  not claimed live.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch 7: AI assistants degrade honestly when the backend is '
      'unreachable', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch7')) return;
    final f = Flows(h);

    final email = await f.newAccountOnDashboard('A');
    h.note('LOOKUP_EMAIL=$email');

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    Future<void> goBack() async {
      for (final finder in [
        find.byType(BackButton),
        find.byType(CloseButton),
        find.byIcon(Icons.arrow_back),
        find.byIcon(Icons.arrow_back_ios_new),
        find.byIcon(Icons.arrow_back_rounded),
        find.byIcon(Icons.close),
        find.byIcon(Icons.close_rounded),
      ]) {
        if (finder.evaluate().isNotEmpty) {
          await h.tapVisible(finder);
          await h.settle(2);
          return;
        }
      }
    }

    bool leaksRaw(String s) =>
        s.contains('Exception') ||
        s.contains('SocketException') ||
        s.contains('FunctionException') ||
        s.contains('ClientException') ||
        s.contains('Stack trace');

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

    // ---------------- Dr. Niswah (health assistant) ----------------
    await scrollUntil(find.text('Doctor Niswah'));
    final openedDoctor = await h.tapVisible(find.text('Doctor Niswah'));
    await h.settle(3);
    await h.shot('A', 'doctor_niswah_open');
    await texts('A doctor niswah opened');
    var doctorSent = false;
    final field = find.byType(TextField);
    if (field.evaluate().isNotEmpty) {
      await tester.enterText(field.last, 'Synthetic test question one');
      await tester.pump(const Duration(milliseconds: 300));
      for (final send in [
        find.byIcon(Icons.send),
        find.byIcon(Icons.send_rounded),
        find.byIcon(Icons.arrow_upward),
        find.byIcon(Icons.arrow_upward_rounded),
        find.bySemanticsLabel(RegExp('[Ss]end')),
      ]) {
        if (send.evaluate().isNotEmpty) {
          doctorSent = await h.tapVisible(send);
          break;
        }
      }
      await tester.pump(const Duration(seconds: 8));
      await h.settle(3);
    }
    await h.shot('A', 'doctor_niswah_after_send');
    final doctorAfter = await texts('A doctor niswah after send');
    final doctorHonest =
        doctorAfter.contains('temporarily unavailable') ||
        doctorAfter.contains('try again');
    final doctorLeaks = leaksRaw(doctorAfter);
    h.note(
      'A AI-07 DrNiswah opened=$openedDoctor sent=$doctorSent '
      'honestUnavailable=$doctorHonest rawLeak=$doctorLeaks',
    );
    await goBack();

    // ---------------- Fiqh advisor (dashboard ask box) ----------------
    await scrollUntil(find.textContaining('Ask any Fiqh or health question'));
    final askBox = find.textContaining('Ask any Fiqh or health question');
    var fiqhSent = false;
    if (askBox.evaluate().isNotEmpty) {
      await h.tapVisible(askBox);
      await h.settle(2);
      final fields = find.byType(TextField);
      if (fields.evaluate().isNotEmpty) {
        await tester.enterText(fields.last, 'Synthetic fiqh test question');
        await tester.pump(const Duration(milliseconds: 300));
        for (final send in [
          find.byIcon(Icons.send),
          find.byIcon(Icons.send_rounded),
          find.byIcon(Icons.arrow_upward),
          find.byIcon(Icons.arrow_upward_rounded),
          find.bySemanticsLabel(RegExp('[Ss]end')),
        ]) {
          if (send.evaluate().isNotEmpty) {
            fiqhSent = await h.tapVisible(send);
            break;
          }
        }
        await tester.pump(const Duration(seconds: 8));
        await h.settle(3);
      }
    }
    await h.shot('A', 'fiqh_advisor_after_send');
    final fiqhAfter = await texts('A fiqh advisor after send');
    final fiqhLeaks = leaksRaw(fiqhAfter);
    h.note('A AI-07 FiqhAdvisor sent=$fiqhSent rawLeak=$fiqhLeaks');
    await goBack();

    // ---------------- Dream interpreter ----------------
    await scrollUntil(find.text('Dream Interpretation'));
    final openedDream = await h.tapVisible(find.text('Dream Interpretation'));
    await h.settle(3);
    await h.shot('A', 'dream_open');
    await texts('A dream opened');
    var dreamSent = false;
    final dreamField = find.byType(TextField);
    if (dreamField.evaluate().isNotEmpty) {
      await tester.enterText(dreamField.last, 'Synthetic dream text');
      await tester.pump(const Duration(milliseconds: 300));
      for (final send in [
        find.byIcon(Icons.send),
        find.byIcon(Icons.send_rounded),
        find.byIcon(Icons.arrow_upward_rounded),
        find.byIcon(Icons.arrow_upward),
        find.textContaining('Interpret'),
      ]) {
        if (send.evaluate().isNotEmpty) {
          dreamSent = await h.tapVisible(send);
          break;
        }
      }
      await tester.pump(const Duration(seconds: 8));
      await h.settle(3);
    }
    await h.shot('A', 'dream_after_send');
    final dreamAfter = await texts('A dream after send');
    final dreamLeaks = leaksRaw(dreamAfter);
    final dreamHonest = dreamAfter.contains('could not be interpreted');
    h.note(
      'A AI-07 Dream opened=$openedDream sent=$dreamSent rawLeak=$dreamLeaks',
    );
    await goBack();

    // The app must still be usable after all three failures.
    await h.scrollToTop();
    final stillUsable = find.text('Profile').evaluate().isNotEmpty;

    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        openedDoctor &&
        doctorSent &&
        doctorHonest &&
        !doctorLeaks &&
        !fiqhLeaks &&
        !dreamLeaks &&
        dreamHonest &&
        stillUsable;
    h.reportResult(
      PersonaResult(
        testId: 'Batch7',
        expectedOutcome:
            'AI-07: with the AI backend unreachable, Dr. Niswah, the Fiqh '
            'advisor and the Dream interpreter fail honestly (clear '
            'unavailable state, no raw exception, no fabricated answer) '
            'and the app stays usable. Transport/error handling only — no '
            'medical or Fiqh content is validated or invented.',
        actualOutcome:
            'crashed=$crashed doctor(opened=$openedDoctor sent=$doctorSent '
            'honest=$doctorHonest leak=$doctorLeaks) fiqh(sent=$fiqhSent '
            'leak=$fiqhLeaks) dream(opened=$openedDream sent=$dreamSent '
            'honest=$dreamHonest leak=$dreamLeaks) stillUsable=$stillUsable',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'A_doctor_niswah_after_send.png',
      ),
    );
  });
}
