import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Six-surface cross-screen consistency walkthrough, using ONE
/// synthetic account and ONE shared menstrual history built the same
/// real way Persona H's is (`Flows.newAccountWithRealHistory`) — a real
/// historical completed episode plus a real current Day-1 episode.
/// Self-contained (its own fresh account) rather than depending on
/// session persistence across separate `flutter drive` invocations, so
/// it runs correctly regardless of execution order or whether the CI
/// loop uninstalls the app between tests.
///
/// Walks: (1) Today (dashboard), (2) canonical calendar, (3) legacy
/// Calendar tab, (4) Insights, (5) the dashboard's own Fiqh/prayer-status
/// card, (6) Export Fiqh Log (the relevant report/export screen) —
/// dumping every visible text on each so the SAME factual events can be
/// compared for divergence across surfaces, per the charter's explicit
/// instruction not to treat a code-intentional gap as automatic product
/// acceptance.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Six-surface cross-screen consistency walkthrough (one shared '
      'synthetic account and history)', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    final f = Flows(h);

    await f.newAccountWithRealHistory('W');
    await f.startBleedingToday('W', flow: 'Medium');

    // --- Surface 1: Today (dashboard) ---
    await h.scrollToTop();
    await h.settle(1);
    await h.shot('W', 'surface1_today_top');
    h.dumpTexts('W surface1 Today top');
    final surface1Top = h.notes.last;
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await h.settle(1);
    await h.shot('W', 'surface1_today_bottom');
    h.dumpTexts('W surface1 Today bottom (Fiqh/prayer card)');
    final surface5FiqhCard = h.notes.last;

    // --- Surface 2: canonical calendar ---
    await h.scrollToTop();
    await h.settle(1);
    final openedCanonical = await h.tapVisible(
      find.bySemanticsLabel('Cycle calendar'),
    );
    h.note('W opened canonical calendar: $openedCanonical');
    await h.settle(2);
    await h.shot('W', 'surface2_canonical_calendar');
    h.dumpTexts('W surface2 canonical calendar');
    final surface2 = h.notes.last;
    if (openedCanonical) {
      // Deliberately NOT `tester.pageBack()` — that helper's own
      // internal `expect()` requires a `CupertinoNavigationBarBackButton`
      // specifically, which this app (a plain Material `AppBar()`, no
      // Cupertino chrome) never has, and a hard `expect()` failure here
      // cascades into a fatal binding assertion that aborts the whole
      // test binary (the same failure mode every other live persona
      // test in this suite avoids for the same reason).
      // Not `find.byTooltip('Back')` (locale-dependent) and not
      // `find.byType(BackButton)` — dashboard_screen.dart pushes this
      // screen with `fullscreenDialog: true`, so Flutter's own AppBar
      // auto-generates a `CloseButton` (X icon), never a `BackButton`.
      final tappedBack = await h.tapVisible(find.byType(CloseButton));
      h.note('W tapped canonical-calendar close button: $tappedBack');
      await h.settle(2);
    }

    // --- Surface 3: legacy Calendar tab ---
    final openedLegacyCalendar = await h.tapVisible(find.text('Calendar'));
    h.note('W opened legacy Calendar tab: $openedLegacyCalendar');
    await h.settle(2);
    await h.shot('W', 'surface3_legacy_calendar');
    h.dumpTexts('W surface3 legacy Calendar tab');
    final surface3 = h.notes.last;

    // --- Surface 4: Insights ---
    final openedInsights = await h.tapVisible(find.text('Insights'));
    h.note('W opened Insights: $openedInsights');
    await h.settle(2);
    await h.shot('W', 'surface4_insights');
    h.dumpTexts('W surface4 Insights');
    final surface4 = h.notes.last;

    // --- Surface 6: Export Fiqh Log (Profile -> Export Fiqh Log) ---
    final openedProfile = await h.tapVisible(find.text('Profile'));
    h.note('W opened Profile: $openedProfile');
    await h.settle(2);
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await h.settle(1);
    final openedFiqhReport = await h.tapVisible(
      find.textContaining('Export Fiqh Log'),
    );
    h.note('W opened Export Fiqh Log: $openedFiqhReport');
    await h.settle(2);
    await h.shot('W', 'surface6_fiqh_report');
    h.dumpTexts('W surface6 Export Fiqh Log');
    final surface6 = h.notes.last;

    h.note('W surface1Top=$surface1Top');
    h.note('W surface5FiqhCard=$surface5FiqhCard');
    h.note('W surface2=$surface2');
    h.note('W surface3=$surface3');
    h.note('W surface4=$surface4');
    h.note('W surface6=$surface6');

    final crashed = tester.takeException() != null;
    h.note('W crashed=$crashed');
    h.reportResult(
      PersonaResult(
        testId: 'W-six-surface',
        expectedOutcome:
            'Today, canonical calendar, legacy Calendar tab, Insights, '
            'the Fiqh/prayer-status card, and Export Fiqh Log all '
            'render without crashing for the SAME account/history, '
            'with any factual divergence between surfaces explicitly '
            'recorded (not assumed acceptable)',
        actualOutcome:
            'crashed=$crashed openedCanonical=$openedCanonical '
            'openedLegacyCalendar=$openedLegacyCalendar '
            'openedInsights=$openedInsights '
            'openedFiqhReport=$openedFiqhReport — see full per-surface '
            'text dumps in this run\'s own notes/logs for the '
            'divergence analysis',
        status:
            (!crashed &&
                openedCanonical &&
                openedLegacyCalendar &&
                openedInsights)
            ? PersonaStatus.pass
            : PersonaStatus.fail,
        screenshotRef: 'W_surface1_today_top.png',
      ),
    );
  });
}
