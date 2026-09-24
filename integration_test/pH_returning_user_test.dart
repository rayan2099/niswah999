import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Persona H — a returning user with real historical data and a real
/// prediction derived from it. Unlike B-J, this drives the onboarding
/// history questions (via `Flows.newAccountWithRealHistory`) with REAL
/// answers instead of "I'm not sure" — the
/// `record_onboarding_menstrual_history` RPC this submits creates one
/// real, ended, historical `bleeding_episodes` row plus a
/// `cycle_baselines` row in the same atomic transaction. A second,
/// current episode is then started live so this account has BOTH a
/// completed historical cycle and an active one.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona H: a returning user with real historical data sees an '
      'honest predicted-cycle picture, not "insufficient history"', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);

    await f.newAccountWithRealHistory('H');
    await h.shot('H', 'dashboard_with_historical_data');
    h.dumpTexts('H dashboard after real historical onboarding');
    final historicalDashboardTexts = h.notes.last;
    final showsInsufficientHistory = historicalDashboardTexts.contains(
      'Two Haid starts are needed',
    );

    // A second real Haid start, giving both the canonical status AND
    // the legacy CycleCalculationService (which needs >= 2 starts) a
    // real interval to compute an average from.
    await f.startBleedingToday('H', flow: 'Medium');
    await h.shot('H', 'dashboard_after_second_start');
    h.dumpTexts('H dashboard after second real Haid start');
    final secondStartTexts = h.notes.last;
    final showsCurrentDay =
        secondStartTexts.contains('Bleeding recorded') ||
        secondStartTexts.contains('Day 1 of this record');

    final pass = !showsInsufficientHistory && showsCurrentDay;
    h.note(
      'H showsInsufficientHistory(after real history)='
      '$showsInsufficientHistory showsCurrentDay(after 2nd start)='
      '$showsCurrentDay',
    );
    h.note(
      pass
          ? 'H RESULT: PASS — real historical onboarding data was '
                'honestly reflected, never treated as "insufficient '
                'history," and a second real Haid start now gives a '
                'real predictable interval'
          : 'H RESULT: FAIL — showsInsufficientHistory='
                '$showsInsufficientHistory showsCurrentDay='
                '$showsCurrentDay',
    );
    h.reportResult(
      PersonaResult(
        testId: 'H',
        expectedOutcome:
            'A returning user with real historical data (a real '
            'completed episode reported during onboarding, plus a '
            'second live Haid start) sees an honest predicted-cycle '
            'picture, never "insufficient history" once real data '
            'exists',
        actualOutcome:
            'showsInsufficientHistory=$showsInsufficientHistory '
            'showsCurrentDay=$showsCurrentDay',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'H_dashboard_after_second_start.png',
      ),
    );
  });
}
