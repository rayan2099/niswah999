import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/flows_ext.dart';
import 'support/harness.dart';
import 'support/reports.dart';

/// Phase 3 batch 6 (rewritten): wellbeing check-in + every report/export for
/// an account whose state is KNOWN, asserted against independent oracles.
///
/// The earlier version tapped each row's TITLE (which does nothing — only the
/// small "Download" button opens a report) and passed on the Profile screen's
/// own text: that evidence was invalid and is replaced here by reading the
/// generated PDF text itself.
///
/// Account: Hanafi selected; period started 3 days ago and is STILL GOING
/// (onboarding records an open canonical episode whose start flow is
/// "uncertain"); married; one wellbeing check-in today.
///  Oracles: Today says "Bleeding recorded — Day 4"; therefore NO report may
///  say the current state is Tahara (D-011), the wellbeing report must count
///  exactly the ONE saved check-in, the JSON export must be complete and each
///  section's row count must equal what the account's own reads return.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch 6: wellbeing + reports/exports checked against oracles', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch6')) return;
    final f = Flows(h);

    final email = await f.newAccountHanafiStillBleeding('R');
    h.note('LOOKUP_EMAIL=$email');
    final client = NiswahSupabase.clientOrNull;
    final uid = client?.auth.currentUser?.id;

    // ---------------- Today: the oracle for every report ----------------
    await h.scrollToTop();
    h.dumpTexts('R Today');
    final today = h.notes.last;
    final todayBleeding =
        today.contains('Bleeding recorded') && today.contains('Day 4');

    // ---------------- WELL-01: mental check-in ----------------
    final logButton = find.widgetWithText(OutlinedButton, 'Log');
    for (var i = 0; i < 12 && logButton.evaluate().isEmpty; i++) {
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -400),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
    h.note('R wellbeing Log button found=${logButton.evaluate().isNotEmpty}');
    await h.tapVisible(logButton);
    await h.settle(2);
    var wellbeingSaved = false;
    if (find.text('Save check-in').evaluate().isNotEmpty) {
      await h.tapVisible(find.text('Save check-in'));
      await h.settle(2);
      h.dumpTexts('R after Save check-in');
      wellbeingSaved = h.notes.last.contains('Your check-in was saved');
    }
    var wellbeingRows = -1;
    if (client != null && uid != null) {
      wellbeingRows =
          (await client.from('wellbeing_logs').select().eq('user_id', uid))
              .length;
    }
    h.note('R WELL-01 saved=$wellbeingSaved serverRows=$wellbeingRows');

    // ---------------- Profile -> exports ----------------
    await h.tapVisible(find.text('Profile'), last: true);
    await h.settle(2);
    final marriedRow = find.ancestor(
      of: find.text('I am married'),
      matching: find.byType(Container),
    );
    if (marriedRow.evaluate().isNotEmpty) {
      final marriedSwitch = find.descendant(
        of: marriedRow.first,
        matching: find.byType(Switch),
      );
      if (marriedSwitch.evaluate().isNotEmpty &&
          !(marriedSwitch.evaluate().first.widget as Switch).value) {
        await h.tapVisible(marriedSwitch);
        await h.settle(2);
      }
    }
    await h.scrollToExports();

    // ---------------- RPT-01 Fiqh report ----------------
    final fiqh = await h.openReportPdf('Export Fiqh Log');
    final rpt01 =
        fiqh != null &&
        fiqh.contains('Fiqh Report') &&
        fiqh.contains('Selected madhhab: Hanafi') &&
        !fiqh.contains('Current state: Tahara') &&
        fiqh.contains('Current state: Insufficient history') &&
        fiqh.contains('bleeding episode is recorded');
    h.note('R RPT-01 fiqh=$rpt01');

    // ---------------- RPT-02 Doctor report ----------------
    final doctor = await h.openReportPdf("Export Doctor's Report");
    final rpt02 =
        doctor != null &&
        doctor.contains("Doctor's Report") &&
        doctor.contains('Overview') &&
        !doctor.contains('Tahara') &&
        doctor.contains('Not enough history yet') &&
        !doctor.contains('enough recorded history yet to generate');
    h.note('R RPT-02 doctor=$rpt02');

    // ---------------- WELL-03 / RPT-03 Wellbeing report ----------------
    final wellbeing = await h.openReportPdf('Mental state report');
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final now = DateTime.now();
    final monthLabel = '${months[now.month - 1]} ${now.year}';
    final well03 =
        wellbeing != null &&
        wellbeing.contains('Mental State Report') &&
        wellbeing.contains(monthLabel) &&
        wellbeing.contains("you've checked in 1 time so far this month") &&
        wellbeing.contains('You checked in 1 days this month');
    h.note('R WELL-03 wellbeing=$well03 (month "$monthLabel")');

    // ---------------- RPT-04 Husband report ----------------
    final husband = await h.openReportPdf('Husband Report');
    final rpt04 =
        husband != null &&
        husband.contains('Husband Report') &&
        husband.contains('Persona R') &&
        !husband.contains('State: Tahara') &&
        husband.contains('Insufficient history') &&
        husband.contains(
          'intercourse is prohibited during the menstrual period',
        );
    h.note('R RPT-04 husband=$rpt04');

    // ---------------- RPT-05 JSON export vs the account's own reads ----------------
    final texts = await h.openExportScreenTexts('Export My Data (JSON)');
    final jsonText = texts.firstWhere(
      (t) => t.contains('"exported_at"'),
      orElse: () => '',
    );
    Map<String, dynamic>? export;
    try {
      export = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (_) {}
    var rpt05 = export != null;
    if (export != null && client != null && uid != null) {
      final expectedEpisodes =
          (await client
                  .from('bleeding_episodes')
                  .select('id')
                  .eq('user_id', uid))
              .length;
      final expectedObservations =
          (await client
                  .from('bleeding_observations')
                  .select('id')
                  .eq('user_id', uid))
              .length;
      int n(String k) => (export![k] as List?)?.length ?? -1;
      final account = export['account'] as Map?;
      rpt05 =
          export['export_complete'] == true &&
          !texts.any((t) => t.contains('export is incomplete')) &&
          account != null &&
          account['id'] == uid &&
          (account['madhhab'] as String?)?.toLowerCase() == 'hanafi' &&
          expectedEpisodes >= 1 &&
          n('bleeding_episodes') == expectedEpisodes &&
          n('bleeding_observations') == expectedObservations;
      h.note(
        'R RPT-05 complete=${export['export_complete']} accountId='
        '${account?['id'] == uid} episodes=${n('bleeding_episodes')}/'
        '$expectedEpisodes observations=${n('bleeding_observations')}/'
        '$expectedObservations',
      );
    } else {
      h.note('R RPT-05 no parsable export JSON (texts=${texts.length})');
    }

    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        todayBleeding &&
        wellbeingSaved &&
        wellbeingRows == 1 &&
        rpt01 &&
        rpt02 &&
        well03 &&
        rpt04 &&
        rpt05;
    h.reportResult(
      PersonaResult(
        testId: 'Batch6',
        expectedOutcome:
            'For an account that Today shows as bleeding (day 4, Hanafi): the '
            'Fiqh, Doctor and Husband reports agree it is not Tahara; the '
            'wellbeing report counts exactly the one saved check-in for this '
            'month; the JSON export is complete and its row counts equal the '
            'account\'s own reads',
        actualOutcome:
            'crashed=$crashed todayBleeding=$todayBleeding '
            'well01(saved=$wellbeingSaved rows=$wellbeingRows) '
            'rpt01_fiqh=$rpt01 rpt02_doctor=$rpt02 well03=$well03 '
            'rpt04_husband=$rpt04 rpt05_json=$rpt05',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'R_Today.png',
      ),
    );
  });
}
