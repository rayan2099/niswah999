import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';
import 'support/reports.dart';

/// Phase 3 batch 11 — pregnancy, end to end, against oracles:
///  PREG-06(a) the state the AI context is BUILT FROM: turning pregnancy on in
///             the app writes the pregnancy_profile row the server's AI
///             functions read; the pregnancy engine (identical to the server's
///             — proven by 21 shared vectors run through the real TS engine in
///             CI) applied to THAT row gives the week Today shows.
///  PREG-03    progression with a controlled clock: +49 days -> week 19.
///  PREG-05    the Doctor's report (the report that carries pregnancy state)
///             states the pregnancy while pregnant; the separate Fiqh report's
///             existing Nifas behavior is observed separately, not derived by the pregnancy engine.
///  PREG-04    logging birth writes is_postpartum + a start date.
/// Whether a MODEL answers well is NOT claimed here.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch 11: pregnancy state, context row, progression, report', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch11')) return;
    final f = Flows(h);

    final email = await f.newAccountOnDashboard('G');
    h.note('LOOKUP_EMAIL=$email');
    final client = NiswahSupabase.clientOrNull;
    final uid = client?.auth.currentUser?.id;

    Future<String> texts(String label) async {
      await tester.pump(const Duration(seconds: 1));
      h.dumpTexts(label);
      return h.notes.last;
    }

    Future<void> openTab(String label) async {
      await h.scrollToTop();
      await h.tapVisible(find.text(label), last: true);
      await h.settle(2);
    }

    Future<Map<String, dynamic>?> profileRow() async {
      if (client == null || uid == null) return null;
      return await client
          .from('pregnancy_profile')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
    }

    Finder switchFor(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Container)),
      matching: find.byType(Switch),
    );

    // ---------------- enable pregnancy at week 12 ----------------
    final rowBefore = await profileRow();
    await openTab('Profile');
    await h.tapVisible(switchFor('I am currently pregnant'));
    await h.settle(2);
    await h.tapVisible(find.text('Week 12'));
    await h.settle(1);
    await h.tapVisible(find.byKey(const Key('pregnancy-setup-activate')));
    await tester.pump(const Duration(seconds: 3));
    await h.settle(2);

    // ---------------- PREG-06(a): the row the AI context is built from ----------------
    final row = await profileRow();
    final setAt = DateTime.tryParse('${row?['manual_week_set_at']}')?.toLocal();
    // (a default row may pre-exist; what matters is what it says now)
    final rowOk =
        row != null &&
        row['tracking_basis'] == 'manual_week' &&
        row['manual_week_value'] == 12 &&
        row['is_postpartum'] == false &&
        setAt != null &&
        DateTime.now().difference(setAt).inMinutes.abs() < 5;
    h.note('G PREG-06a row=$row rowOk=$rowOk');
    // The engine (== the server's) on the REAL row.
    final profile = row == null ? null : PregnancyProfile.fromJson(row);
    final serverView = PregnancyStatusEngine.getStatus(profile, DateTime.now());
    final serverAgrees =
        serverView.mode == PregnancyMode.pregnant &&
        serverView.week == 12 &&
        serverView.trimester == 1 &&
        serverView.weeksToDue == 28;
    h.note(
      'G server-side view of that row: week=${serverView.week} agrees=$serverAgrees',
    );

    // ---------------- Today shows the same state ----------------
    await openTab('Today');
    final today12 = await texts('G Today (pregnant, week 12)');
    final shows12 =
        today12.contains('12 weeks') &&
        today12.contains('Week 12') &&
        today12.contains('28 weeks to go');
    h.note('G Today week12=$shows12');

    // ---------------- PREG-03: controlled time ----------------
    AppClock.now = () => DateTime.now().add(const Duration(days: 49));
    addTearDown(() => AppClock.now = DateTime.now);
    await PregnancyStatusController.instance.load(); // notifies the dashboard
    await tester.pump(const Duration(seconds: 2));
    final today19 = await texts('G Today (+49 days)');
    final shows19 =
        today19.contains('19 weeks') &&
        today19.contains('Week 19') &&
        today19.contains('21 weeks to go');
    final serverView19 = PregnancyStatusEngine.getStatus(
      profile,
      AppClock.now(),
    );
    final serverAgrees19 = serverView19.week == 19;
    h.note(
      'G PREG-03 shows19=$shows19 serverAgrees19=$serverAgrees19 '
      'serverWeek=${serverView19.week} mode=${serverView19.mode} '
      'profileNull=${profile == null} setAt=${profile?.manualWeekSetAt} '
      'clock=${AppClock.now()} diff=${profile == null ? null : AppClock.now().difference(profile.manualWeekSetAt!)} '
      'tz=${DateTime.now().timeZoneName} offset=${DateTime.now().timeZoneOffset} setAtIsUtc=${profile?.manualWeekSetAt?.isUtc}',
    );
    AppClock.now = DateTime.now;
    await PregnancyStatusController.instance.load();
    await tester.pump(const Duration(seconds: 1));

    // ---------------- Fiqh report while pregnant ----------------
    await openTab('Profile');
    await h.scrollToExports();
    final fiqhPregnant = await h.openReportPdf('Export Fiqh Log');
    final fiqhPregnantOk =
        fiqhPregnant != null &&
        fiqhPregnant.contains(
          'Pregnancy tracking is active: week 12 (trimester 1)',
        );
    h.note('G fiqh(pregnant) states pregnancy=$fiqhPregnantOk');

    // ---------------- PREG-05: the Doctor's report while pregnant ----------------
    await openTab('Profile');
    await h.scrollToExports();
    final doctorPregnant = await h.openReportPdf("Export Doctor's Report");
    h.note('G doctor(pregnant) available=${doctorPregnant != null}');
    final doctorPregnantOk =
        doctorPregnant != null &&
        doctorPregnant.contains("Doctor's Report") &&
        doctorPregnant.contains('Pregnant') &&
        doctorPregnant.contains(
          'Week 12 (trimester 1, month 3); about 28 weeks to the due date.',
        );

    // ---------------- PREG-04: birth -> Nifas, server row ----------------
    await openTab('Today');
    await h.tapVisible(find.text('Log birth & start Nifas'));
    await h.settle(2);
    for (final label in ['Confirm', 'Yes', 'Start Nifas', 'Save', 'OK']) {
      if (find.text(label).evaluate().isNotEmpty) {
        await h.tapVisible(find.text(label), last: true);
        await h.settle(2);
        break;
      }
    }
    await tester.pump(const Duration(seconds: 3));
    final rowNifas = await profileRow();
    // postpartum_start_date is a DATE: it must be today's local date.
    final startText = '${rowNifas?['postpartum_start_date']}';
    final nowLocal = DateTime.now();
    final todayText =
        '${nowLocal.year}-${nowLocal.month.toString().padLeft(2, '0')}-'
        '${nowLocal.day.toString().padLeft(2, '0')}';
    final nifasRowOk =
        rowNifas != null &&
        rowNifas['is_postpartum'] == true &&
        startText.startsWith(todayText);
    h.note('G postpartum row start=$startText today=$todayText');
    final nifasView = PregnancyStatusEngine.getStatus(
      rowNifas == null ? null : PregnancyProfile.fromJson(rowNifas),
      DateTime.now(),
    );
    final postpartumAgrees =
        nifasView.mode == PregnancyMode.postpartum &&
        nifasView.daysPostpartum == 0;
    h.note(
      'G PREG-04 postpartum row=$nifasRowOk factual engine agrees=$postpartumAgrees',
    );

    await openTab('Profile');
    await h.scrollToExports();
    final fiqhNifas = await h.openReportPdf('Export Fiqh Log');
    final fiqhNifasOk = fiqhNifas != null && fiqhNifas.contains('Nifas');
    h.note('G fiqh report in Nifas mentions Nifas=$fiqhNifasOk');

    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        rowOk &&
        serverAgrees &&
        shows12 &&
        shows19 &&
        serverAgrees19 &&
        doctorPregnantOk &&
        fiqhPregnantOk &&
        nifasRowOk &&
        postpartumAgrees &&
        fiqhNifasOk;
    h.reportResult(
      PersonaResult(
        testId: 'Batch11',
        expectedOutcome:
            'Pregnancy on at week 12 writes the pregnancy_profile row the AI '
            'context is built from, and the server-equivalent engine on that '
            'row agrees with Today; +49 days moves both to week 19; the Doctor '
            'report reflects pregnancy; birth writes the postpartum row and '
            'the Fiqh report enters Nifas mode',
        actualOutcome:
            'crashed=$crashed rowOk=$rowOk serverAgrees=$serverAgrees '
            'shows12=$shows12 shows19=$shows19 serverAgrees19=$serverAgrees19 '
            'doctorPregnant=$doctorPregnantOk fiqhPregnant=$fiqhPregnantOk nifasRow=$nifasRowOk '
            'postpartumAgrees=$postpartumAgrees fiqhNifas=$fiqhNifasOk',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'G_Today.png',
      ),
    );
  });
}
