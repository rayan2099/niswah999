import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';
import 'support/reports.dart';

/// WELL-03 / RPT-03 — the figures the Wellbeing and Doctor reports state are
/// checked against an oracle computed HERE from a known dataset, not merely
/// "the report opens".
///
/// Setup (disclosed): eight check-ins are written through the signed-in
/// account's own authenticated API (the RLS-permitted path a real client
/// uses), on days 10-17 of the month, moods [2,3,4,4,5,3,4,4]. The app's clock
/// is pinned to the 20th so the dataset always sits inside "this month".
///
///   check-in days            = 8
///   days with mood >= 4      = 5           (4,4,5,4,4)
///   average mood             = 29 / 8 = 3.625 -> "3.6"
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch 16: wellbeing report figures match the dataset', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch16')) return;
    addTearDown(AppClock.reset);
    final f = Flows(h);
    final email = await f.newAccountOnDashboard('WF');
    h.note('LOOKUP_EMAIL=$email');

    final client = NiswahSupabase.clientOrNull!;
    final uid = client.auth.currentUser!.id;
    final real = DateTime.now();
    final moods = [2, 3, 4, 4, 5, 3, 4, 4];
    String day(int d) =>
        '${real.year}-${real.month.toString().padLeft(2, '0')}-'
        '${d.toString().padLeft(2, '0')}';
    var seedError = '';
    try {
      await client.from('wellbeing_logs').insert([
        for (var i = 0; i < moods.length; i++)
          {
            'user_id': uid,
            'log_date': day(10 + i),
            'mood': moods[i],
            'energy': 3,
            'sleep': 3,
          },
      ]);
    } catch (e) {
      seedError = e.toString();
    }
    final stored =
        (await client.from('wellbeing_logs').select('mood').eq('user_id', uid))
            .map((r) => r['mood'] as int)
            .toList();
    final expectedAverage = (moods.reduce((a, b) => a + b) / moods.length)
        .toStringAsFixed(1);
    final expectedGood = moods.where((m) => m >= 4).length;
    h.note(
      'WF seeded=${stored.length} (error="$seedError") '
      'oracle: days=${moods.length} good=$expectedGood average=$expectedAverage',
    );

    // The app's "today" is the 20th of this month, so the data is "this month".
    AppClock.now = () => DateTime(real.year, real.month, 20, 12);

    await h.scrollToTop();
    await h.tapVisible(find.text('Profile'), last: true);
    await h.settle(2);
    await h.scrollToExports();

    final wellbeing = await h.openReportPdf('Mental state report');
    final wellbeingDays =
        wellbeing?.contains('You checked in ${moods.length} days this month') ??
        false;
    final wellbeingGood =
        wellbeing?.contains(
          'You had $expectedGood days this month where you felt good or excellent',
        ) ??
        false;
    h.note('WF wellbeing report: days=$wellbeingDays good=$wellbeingGood');

    await h.scrollToExports();
    final doctor = await h.openReportPdf("Export Doctor's Report");
    final doctorAverage =
        doctor?.contains('Average mood this month: $expectedAverage/5') ??
        false;
    h.note('WF doctor report: averageMood=$doctorAverage');

    AppClock.reset();
    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        stored.length == moods.length &&
        wellbeingDays &&
        wellbeingGood &&
        doctorAverage;
    h.reportResult(
      PersonaResult(
        testId: 'Batch16',
        expectedOutcome:
            'WELL-03/RPT-03: with 8 check-ins (moods 2,3,4,4,5,3,4,4) the '
            'Wellbeing report says 8 check-in days and 5 good days, and the '
            'Doctor report says the average mood is $expectedAverage/5',
        actualOutcome:
            'crashed=$crashed seeded=${stored.length}/${moods.length} '
            'wellbeingDays=$wellbeingDays wellbeingGood=$wellbeingGood '
            'doctorAverageMood=$doctorAverage seedError="$seedError"',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
      ),
    );
  });
}
