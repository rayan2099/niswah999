import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 4 — a LIVE Arabic (RTL) journey on the real app: navigation, a
/// real save, the date picker, keyboard input, back navigation, layout at
/// 200% text scale, directional layout and screen-reader semantics. The
/// account is created and onboarded through the English flow (the shared,
/// proven path), then the language is switched to Arabic from the real
/// Profile language control and everything after is exercised in Arabic.
/// Existing Arabic WIDGET tests are not a substitute for this and are not
/// counted; nor is a compile.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Arabic RTL: live journey with layout/semantics checks', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('AR1')) return;
    final f = Flows(h);
    final semantics = tester.ensureSemantics();

    final email = await f.newAccountOnDashboard('AR');
    h.note('LOOKUP_EMAIL=$email');

    Future<String> texts(String label) async {
      await h.settle(1);
      h.dumpTexts(label);
      return h.notes.last;
    }

    // ---------------- switch to Arabic via the real control ----------------
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
    final profileArabic = await texts('AR profile after switching language');
    final nowArabic = profileArabic.contains('الملف الشخصي');
    h.note('AR switched=$switched profileIsArabic=$nowArabic');

    bool isRtl() {
      final scaffold = find.byType(Scaffold);
      if (scaffold.evaluate().isEmpty) return false;
      return Directionality.of(tester.element(scaffold.first)) ==
          TextDirection.rtl;
    }

    // ---------------- navigation across all five tabs ----------------
    final tabLabels = {
      'اليوم': 'today',
      'التقويم': 'calendar',
      'الرؤى': 'insights',
      'المجتمع': 'community',
      'الملف الشخصي': 'profile',
    };
    var tabsOk = true;
    var rtlEverywhere = true;
    for (final entry in tabLabels.entries) {
      await h.scrollToTop();
      final tapped = await h.tapVisible(find.text(entry.key), last: true);
      await h.settle(2);
      final body = await texts('AR tab ${entry.value}');
      final ok = tapped && body.contains(entry.key);
      final rtl = isRtl();
      tabsOk = tabsOk && ok;
      rtlEverywhere = rtlEverywhere && rtl;
      h.note('AR tab ${entry.value}: tapped=$tapped labelSeen=$ok rtl=$rtl');
      await h.shot('AR', 'tab_${entry.value}');
    }

    // ---------------- a real save in Arabic ----------------
    await h.scrollToTop();
    await h.tapVisible(find.text('اليوم'), last: true);
    await h.settle(2);
    await h.tapVisible(find.text('بدأ الحيض'));
    await h.settle(2);
    final sheetAr = await texts('AR start-bleeding sheet');
    final sheetIsArabic = sheetAr.contains('بدأ النزيف');
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
    final savedAr = await texts('AR dashboard after saving');
    final savedShown =
        savedAr.contains('تم تسجيل النزيف') || savedAr.contains('المتابعة اليومية');
    h.note('AR save: sheetArabic=$sheetIsArabic savedShown=$savedShown');
    await h.shot('AR', 'after_save');

    // ---------------- real date picker (backfill) in Arabic ----------------
    final openedBackfill = await h.tapVisible(find.text('إضافة يوم فائت'));
    await h.settle(2);
    final openedPicker = await h.tapVisible(find.text('اختيار تاريخ'));
    await h.settle(2);
    var pickedDate = false;
    final dialog = find.byType(Dialog);
    if (dialog.evaluate().isNotEmpty) {
      final loc = MaterialLocalizations.of(tester.element(dialog.first));
      final dayText = loc.formatDecimal(DateTime.now().day);
      h.note('AR date picker shows Arabic-Indic day text "$dayText"');
      final cell = find.descendant(of: dialog.first, matching: find.text(dayText));
      if (cell.evaluate().isNotEmpty) {
        await h.tapVisible(cell.last);
        await h.settle(1);
        // The confirm button is the dialog's last TextButton.
        final buttons = find.descendant(
          of: dialog.first,
          matching: find.byType(TextButton),
        );
        if (buttons.evaluate().isNotEmpty) {
          await h.tapVisible(buttons.last);
          await h.settle(2);
          pickedDate = true;
        }
      }
    }
    final afterPicker = await texts('AR backfill after picking a date');
    h.note(
      'AR date picker: openedBackfill=$openedBackfill openedPicker='
      '$openedPicker picked=$pickedDate',
    );
    await h.shot('AR', 'backfill_date_picked');
    // Close the sheet.
    await tester.tapAt(const Offset(195, 60));
    await h.settle(2);

    // ---------------- keyboard: Arabic text entry ----------------
    await h.scrollToTop();
    await h.tapVisible(find.text('المجتمع'), last: true);
    await h.settle(3);
    final search = find.byType(TextField);
    var typedArabic = false;
    if (search.evaluate().isNotEmpty) {
      await tester.enterText(search.first, 'نص تجريبي');
      await tester.pump(const Duration(seconds: 1));
      await h.settle(1);
      await texts('AR after typing Arabic');
      typedArabic =
          tester.widget<TextField>(search.first).controller?.text == 'نص تجريبي';
    }
    h.note('AR keyboard: arabic text accepted and shown=$typedArabic');

    // ---------------- back navigation (Android system back too) ----------------
    await h.scrollToTop();
    await h.tapVisible(find.text('اليوم'), last: true);
    await h.settle(2);
    final openedCalendar = await h.tapVisible(
      find.bySemanticsLabel('تقويم الدورة'),
    );
    await h.settle(3);
    await h.shot('AR', 'canonical_calendar');
    // Directional layout: previous/next month controls must follow RTL.
    final chevrons = find.byType(IconButton);
    var monthControlsRtl = false;
    if (chevrons.evaluate().length >= 2) {
      final first = tester.getCenter(chevrons.at(0)).dx;
      final second = tester.getCenter(chevrons.at(1)).dx;
      monthControlsRtl = first > second; // first child sits at the RIGHT in RTL
      h.note('AR month controls: first.dx=$first second.dx=$second');
    }
    final backViaSystem = await binding.handlePopRoute();
    await h.settle(2);
    final backAtDashboard = find.text('اليوم').evaluate().isNotEmpty;
    h.note(
      'AR back: openedCalendar=$openedCalendar systemBackHandled='
      '$backViaSystem backOnDashboard=$backAtDashboard '
      'monthControlsRtl=$monthControlsRtl',
    );

    // ---------------- 200% text scale: overflow sweep ----------------
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    await tester.pump(const Duration(seconds: 1));
    final overflowed = <String>[];
    Future<void> sweep(String tab) async {
      await h.scrollToTop();
      await h.tapVisible(find.text(tab), last: true);
      await h.settle(2);
      final ex = tester.takeException();
      if (ex != null) overflowed.add('$tab: ${ex.toString().split('\n').first}');
      await h.shot('AR', 'scale2_${tabLabels[tab]}');
    }
    for (final tab in tabLabels.keys) {
      await sweep(tab);
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pump(const Duration(seconds: 1));
    h.note('AR 200% text scale overflow findings: $overflowed');

    // ---------------- screen-reader semantics ----------------
    await h.scrollToTop();
    await h.tapVisible(find.text('اليوم'), last: true);
    await h.settle(2);
    var unlabeledIconButtons = 0;
    var totalIconButtons = 0;
    for (final tab in tabLabels.keys) {
      await h.tapVisible(find.text(tab), last: true);
      await h.settle(2);
      final buttons = find.byType(IconButton);
      for (var i = 0; i < buttons.evaluate().length; i++) {
        totalIconButtons++;
        final node = tester.getSemantics(buttons.at(i));
        if (node.label.trim().isEmpty && node.tooltip.trim().isEmpty) {
          unlabeledIconButtons++;
        }
      }
    }
    final navLabelled =
        find.bySemanticsLabel('الرؤى').evaluate().isNotEmpty &&
        find.bySemanticsLabel('التقويم').evaluate().isNotEmpty;
    h.note(
      'AR semantics: iconButtons=$totalIconButtons unlabeled='
      '$unlabeledIconButtons navLabelledArabic=$navLabelled',
    );
    semantics.dispose();

    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        switched &&
        nowArabic &&
        tabsOk &&
        rtlEverywhere &&
        sheetIsArabic &&
        savedShown &&
        pickedDate &&
        typedArabic &&
        backAtDashboard &&
        monthControlsRtl &&
        overflowed.isEmpty &&
        unlabeledIconButtons == 0 &&
        navLabelled;
    h.reportResult(
      PersonaResult(
        testId: 'AR1',
        expectedOutcome:
            'A live Arabic RTL journey: language switch, 5-tab navigation, a '
            'real save, the date picker, Arabic keyboard input, back '
            'navigation, RTL month controls, no overflow at 200% text '
            'scale, and screen-reader labels',
        actualOutcome:
            'crashed=$crashed switched=$switched profileArabic=$nowArabic '
            'tabs=$tabsOk rtl=$rtlEverywhere save(sheetAr=$sheetIsArabic '
            'shown=$savedShown) datePicker=$pickedDate keyboard=$typedArabic '
            'back=$backAtDashboard monthControlsRtl=$monthControlsRtl '
            'overflowAt200=${overflowed.length} $overflowed '
            'unlabeledIconButtons=$unlabeledIconButtons/$totalIconButtons '
            'navLabelled=$navLabelled',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'AR_scale2_profile.png',
      ),
    );
  });
}
