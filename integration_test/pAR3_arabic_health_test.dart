import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/arabic_audit.dart';
import 'support/flows.dart';
import 'support/harness.dart';
import 'support/reports.dart';

/// Phase 4 — Arabic critical path, part 2: pregnancy / Nifas, prayer
/// location, notification settings, profile / privacy, and every report and
/// export, all in Arabic. Each screen goes through ArabicAudit (RTL, no
/// English-only remnants, Arabic dates, mirrored icons, no overflow at 1.6x
/// text scale); each generated PDF is read and must be Arabic text with no
/// English report/section wording.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Arabic health journey: pregnancy, Nifas, prayer, notifications, reports',
    (tester) async {
      app.main();
      final h = Harness(binding, tester);
      if (!await h.guardBackend('AR3')) return;
      final f = Flows(h);
      final audit = ArabicAudit(h);
      const persona = 'Persona A3';

      final email = await f.newAccountOnDashboard('A3');
      h.note('LOOKUP_EMAIL=$email');

      // ---- switch the language from Profile (the real control) ----
      await h.scrollToTop();
      await h.tapVisible(find.text('Profile'), last: true);
      await h.settle(2);
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -2500),
        warnIfMissed: false,
      );
      await h.settle(1);
      final switched = await h.tapVisible(find.text('AR'));
      await h.settle(3);

      Future<void> openTab(String label) async {
        await h.scrollToTop();
        await h.tapVisible(find.text(label), last: true);
        await h.settle(2);
      }

      Future<void> profileTop() async {
        await openTab('الملف الشخصي');
        await h.scrollToTop();
        await h.settle(1);
      }

      Finder switchFor(String title) => find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(Container),
        ),
        matching: find.byType(Switch),
      );

      await profileTop();
      await audit.audit('profile (top)', userContent: {persona});

      // ---------------- prayer location (Arabic city sheet) ----------------
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -500),
        warnIfMissed: false,
      );
      await h.settle(1);
      await audit.audit('profile (prayer settings)', userContent: {persona});
      await h.tapVisible(find.text('تغيير المدينة'));
      await h.settle(2);
      await audit.audit('city sheet', userContent: {persona});
      final cityChosen = await h.tapVisible(find.textContaining('الرياض'));
      await h.settle(2);
      await audit.audit('profile after city', userContent: {persona});

      // ---------------- married + pregnancy (Arabic) ----------------
      await profileTop();
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -700),
        warnIfMissed: false,
      );
      await h.settle(1);
      if (!(switchFor('أنا متزوجة').evaluate().first.widget as Switch).value) {
        await h.tapVisible(switchFor('أنا متزوجة'));
        await h.settle(2);
      }
      await h.tapVisible(switchFor('أنا حامل حالياً'));
      await h.settle(2);
      await audit.audit('pregnancy setup sheet', userContent: {persona});
      await h.tapVisible(find.text('أسبوع 12'));
      await h.settle(1);
      await h.tapVisible(find.byKey(const Key('pregnancy-setup-activate')));
      await tester.pump(const Duration(seconds: 3));
      await h.settle(2);
      await audit.audit('profile (pregnant)', userContent: {persona});

      await openTab('اليوم');
      final today = await () async {
        await audit.audit('today (pregnancy overview)', userContent: {persona});
        return audit.visibleTexts().join(' | ');
      }();
      final pregnancyShown = today.contains('12');

      // ---------------- reports while pregnant (Arabic) ----------------
      await profileTop();
      await h.scrollToExports();
      Future<bool> arabicPdf(
        String row, {
        bool mustMentionPregnancy = false,
      }) async {
        final pdf = await h.openReportPdf(row);
        if (pdf == null) {
          audit.findings.add('report "$row": could not be opened/generated');
          return false;
        }
        final all = pdf.all;
        final hasArabic = RegExp(r'[؀-ۿﭐ-﻿]').hasMatch(all);
        final english = RegExp(r'[A-Za-z]{3,}')
            .allMatches(all)
            .map((m) => m.group(0)!)
            .where(
              (w) => !const {'NISWAH', 'Niswah', 'PDF', 'Persona'}.contains(w),
            )
            .toSet();
        if (!hasArabic) audit.findings.add('report "$row": no Arabic text');
        if (english.isNotEmpty)
          audit.findings.add(
            'report "$row": English words in the PDF $english',
          );
        return hasArabic && english.isEmpty;
      }

      final rFiqh = await arabicPdf('تصدير سجل فقهي');
      final rDoctor = await arabicPdf('تصدير تقرير للطبيبة');
      final rWellbeing = await arabicPdf('تقرير الحالة النفسية');
      final rHusband = await arabicPdf('تقرير الزوج');
      // JSON export screen (not a PDF): audit its chrome.
      final exportTexts = await h.openExportScreenTexts('تصدير بياناتي (JSON)');
      final jsonOk = exportTexts.any((t) => t.contains('"exported_at"'));

      // ---------------- notification settings (Arabic) ----------------
      await profileTop();
      await tester.scrollUntilVisible(
        find.text('إعدادات التنبيهات'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await h.tapVisible(find.text('إعدادات التنبيهات'));
      await h.settle(2);
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -600),
        warnIfMissed: false,
      );
      await h.settle(1);
      await audit.audit('notification settings', userContent: {persona});
      await h.tapVisible(find.text('تغيير').first);
      await h.settle(2);
      await audit.audit(
        'reminder time picker',
        userContent: {persona},
        extraAllowed: {'AM', 'PM'},
      );
      await binding.handlePopRoute();
      await h.settle(1);
      await binding.handlePopRoute();
      await h.settle(2);

      // ---------------- birth -> Nifas (Arabic) ----------------
      await openTab('اليوم');
      await h.tapVisible(find.text('تسجيل الولادة وبدا النفاس'));
      await h.settle(2);
      await audit.audit('birth confirmation', userContent: {persona});
      for (final label in ['تأكيد', 'نعم', 'حفظ', 'موافق']) {
        if (find.text(label).evaluate().isNotEmpty) {
          await h.tapVisible(find.text(label), last: true);
          await h.settle(2);
          break;
        }
      }
      await tester.pump(const Duration(seconds: 3));
      await h.settle(2);
      await h.scrollToTop();
      await audit.audit('today (Nifas)', userContent: {persona});
      final nifasShown = audit.visibleTexts().join(' | ').contains('النفاس');
      final fiqhNifas = await () async {
        await profileTop();
        await h.scrollToExports();
        return arabicPdf('تصدير سجل فقهي');
      }();

      // ---------------- privacy policy (Arabic long text) ----------------
      await profileTop();
      await tester.scrollUntilVisible(
        find.text('سياسة الخصوصية'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await h.tapVisible(find.text('سياسة الخصوصية'));
      await h.settle(2);
      await audit.audit('privacy policy', userContent: {persona});

      final crashed = tester.takeException() != null;
      for (final finding in audit.findings) {
        h.note('AR3 FINDING: $finding');
      }
      final pass =
          !crashed &&
          switched &&
          cityChosen &&
          pregnancyShown &&
          rFiqh &&
          rDoctor &&
          rWellbeing &&
          rHusband &&
          jsonOk &&
          nifasShown &&
          fiqhNifas &&
          audit.findings.isEmpty;
      h.reportResult(
        PersonaResult(
          testId: 'AR3',
          expectedOutcome:
              'Pregnancy, Nifas, prayer location, notification settings, '
              'privacy policy and every report/export work in Arabic with RTL '
              'layout, Arabic dates, no English remnants (screens and PDFs), '
              'mirrored icons and no overflow at 1.6x text scale',
          actualOutcome:
              'crashed=$crashed switched=$switched city=$cityChosen '
              'pregnancy=$pregnancyShown reports(fiqh=$rFiqh doctor=$rDoctor '
              'wellbeing=$rWellbeing husband=$rHusband json=$jsonOk) '
              'nifas=$nifasShown fiqhNifas=$fiqhNifas ${audit.summary}',
          status: pass ? PersonaStatus.pass : PersonaStatus.fail,
          screenshotRef: 'AR3_profile.png',
        ),
      );
    },
  );
}
