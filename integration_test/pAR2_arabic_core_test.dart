import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/arabic_audit.dart';
import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 4 — Arabic critical path, part 1: auth, onboarding, Today, tracking,
/// Calendar, Insights, Profile — ALL started and finished in Arabic (the
/// account is created through the Arabic sign-up form, not switched later).
/// Every screen goes through ArabicAudit (RTL, no English-only remnants,
/// Arabic date presentation, mirrored icons, no overflow at 1.6x text scale).
/// A real save is made and checked on the server.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Arabic core journey: auth -> onboarding -> track -> calendar', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('AR2')) return;
    final f = Flows(h);
    final audit = ArabicAudit(h);
    const persona = 'Persona AR2';

    // ---------------- auth (Arabic) ----------------
    await f.boot(english: false);
    await audit.audit('auth landing');
    await f.acceptConsent();
    await h.tapVisible(find.text('البريد الإلكتروني'));
    await h.settle();
    await h.tapVisible(find.byKey(const Key('mode_tab_sign_up')));
    await h.settle();
    final email = 'AR2.${DateTime.now().millisecondsSinceEpoch}@example.test';
    h.note('LOOKUP_EMAIL=$email');
    for (final e in {
      'الاسم الكامل': persona,
      'البريد الإلكتروني': email,
      'كلمة المرور': 'Test-Pass-12345',
    }.entries) {
      final field = find.widgetWithText(TextField, e.key);
      if (field.evaluate().isNotEmpty)
        await tester.enterText(field.first, e.value);
    }
    await tester.pump(const Duration(milliseconds: 300));
    await audit.audit('auth sign-up form', userContent: {persona, email});
    await h.tapVisible(find.text('إنشاء حساب'), last: true);
    await h.waitFor(find.text('ابدئي'), timeout: const Duration(seconds: 25));

    // ---------------- onboarding (Arabic) ----------------
    final steps = <String, String>{
      'ابدئي': 'welcome',
      'لا أعرف مذهبي': 'madhhab',
      'سأقرر لاحقاً': 'madhhab-later',
      'متابعة': 'continue',
      'تخطي الآن': 'location-skip',
      'لست متأكدة': 'unsure',
    };
    var onboardingScreens = 0;
    for (var i = 0; i < 14; i++) {
      await h.settle(2);
      final texts = audit.visibleTexts();
      if (texts.any((t) => t.contains('اليوم')) &&
          texts.any((t) => t.contains('التقويم')))
        break; // reached the app
      await audit.audit('onboarding step $i', userContent: {persona});
      onboardingScreens++;
      String? pressed;
      // Priority: skip/unsure before generic continue.
      for (final label in [
        'ابدئي',
        'لا أعرف مذهبي',
        'سأقرر لاحقاً',
        'تخطي الآن',
        'لست متأكدة',
        'متابعة',
      ]) {
        final finder = find.text(label);
        if (finder.evaluate().isNotEmpty && await h.tapVisible(finder)) {
          pressed = steps[label];
          break;
        }
      }
      if (pressed == null) break;
      await tester.pump(const Duration(seconds: 2));
    }
    h.note('AR2 onboarding screens audited: $onboardingScreens');

    // ---------------- Today ----------------
    await h.settle(2);
    await h.scrollToTop();
    await audit.audit('today (no data)', userContent: {persona});
    final todayNoData = audit.visibleTexts().join(' | ');
    final onToday =
        todayNoData.contains('اليوم') && todayNoData.contains('التقويم');

    // ---------------- Start bleeding (real save, Arabic) ----------------
    await h.tapVisible(find.text('بدأ الحيض'));
    await h.settle(2);
    await audit.audit('start-bleeding sheet', userContent: {persona});
    await h.tapVisible(find.text('اليوم'), last: true);
    await h.tapVisible(find.text('متوسط'));
    await h.tapVisible(find.text('حفظ'));
    await tester.pump(const Duration(seconds: 6));
    await h.settle(2);
    for (final label in ['ليس الآن', 'Not now']) {
      if (find.text(label).evaluate().isNotEmpty) {
        await h.tapVisible(find.text(label));
        await h.settle(2);
        break;
      }
    }
    await h.scrollToTop();
    await audit.audit('today (bleeding recorded)', userContent: {persona});
    final client = NiswahSupabase.clientOrNull;
    final uid = client?.auth.currentUser?.id;
    var episodes = -1;
    var observations = -1;
    if (client != null && uid != null) {
      episodes =
          (await client
                  .from('bleeding_episodes')
                  .select('id')
                  .eq('user_id', uid))
              .length;
      observations =
          (await client
                  .from('bleeding_observations')
                  .select('id')
                  .eq('user_id', uid))
              .length;
    }
    h.note('AR2 server: episodes=$episodes observations=$observations');

    // ---------------- Calendar (bottom tab + canonical calendar) ----------------
    await h.scrollToTop();
    await h.tapVisible(find.text('التقويم'), last: true);
    await h.settle(2);
    await audit.audit('calendar tab', userContent: {persona});
    await h.tapVisible(find.text('اليوم'), last: true);
    await h.settle(2);
    await h.tapVisible(find.bySemanticsLabel('تقويم الدورة'));
    await h.settle(3);
    await audit.audit('canonical calendar', userContent: {persona});
    await h.tapVisible(find.text(DateTime.now().day.toString()), last: true);
    await h.settle(2);
    await audit.audit('calendar day detail', userContent: {persona});
    await binding.handlePopRoute();
    await h.settle(2);
    await binding.handlePopRoute();
    await h.settle(2);

    // ---------------- Insights, Community tab, Profile ----------------
    for (final tab in ['الرؤى', 'المجتمع', 'الملف الشخصي']) {
      await h.scrollToTop();
      await h.tapVisible(find.text(tab), last: true);
      await h.settle(2);
      await audit.audit('tab $tab', userContent: {persona, 'Persona', 'Synthetic'});
    }

    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        onToday &&
        episodes == 1 &&
        observations == 1 &&
        audit.findings.isEmpty;
    for (final finding in audit.findings) {
      h.note('AR2 FINDING: $finding');
    }
    h.reportResult(
      PersonaResult(
        testId: 'AR2',
        expectedOutcome:
            'The whole core journey works in Arabic (sign-up, onboarding, a real '
            'save, calendar, insights, community tab, profile) with RTL layout, '
            'no English-only remnants, Arabic date presentation, mirrored '
            'directional icons and no overflow at 1.6x text scale',
        actualOutcome:
            'crashed=$crashed onToday=$onToday server(episodes=$episodes '
            'observations=$observations) ${audit.summary}',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'AR2_calendar.png',
      ),
    );
  });
}
