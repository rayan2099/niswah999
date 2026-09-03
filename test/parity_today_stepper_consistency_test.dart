import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/parity_test_harness.dart';

/// Regression coverage for the cycle ring / phase stepper contradiction,
/// now against the 6-segment model (haid, tahara1, fertile, tahara2,
/// prePeriod, expected): the ring, the pill beneath it, and the stepper's
/// "أنتِ هنا" marker must always agree about which phase is current, and
/// a non-current node must never render a "day X of Y" progress format.
/// Only haid/tahara may ever be "current" — fertile/prePeriod/expected are
/// always upcoming reference markers, even when the statistical model
/// would place "today" inside one of them.
void main() {
  Future<void> seedLogs(WidgetTester tester, List<Map<String, Object?>> logs) async {
    final prefs = await SharedPreferences.getInstance();
    final logsJson = jsonEncode(logs);
    await prefs.setString('niswah_cycle_tracking_logs', logsJson);
    await prefs.setString('flutter.niswah_cycle_tracking_logs', logsJson);
    await tester.pumpWidget(NiswahApp(key: UniqueKey()));
    await tester.pumpAndSettle();
  }

  Map<String, Object?> log({
    required String id,
    required String date,
    required String flow,
    int cycleDay = 1,
  }) => {
    'id': id,
    'user_id': 'local-user',
    'date': date,
    'flow': flow,
    'cycle_day': cycleDay,
    'sync_status': 'synced',
  };

  testWidgets(
    'period is days away (tahara1 active): ring, pill, and stepper all '
    'agree — the "you are here" marker is on the correct Taharah instance, '
    'all 6 segments render, and Haid never shows a progress format',
    (tester) async {
      await ParityTestHarness.pump(tester, arabic: true);
      await seedLogs(tester, [
        log(id: '1', date: '2026-06-01T08:00:00.000', flow: 'medium'),
        log(id: '2', date: '2026-06-05T08:00:00.000', flow: 'none'),
        log(id: '3', date: '2026-07-20T08:00:00.000', flow: 'medium'),
        log(id: '4', date: '2026-07-24T08:00:00.000', flow: 'none'),
      ]);

      // Ring headline agrees this is Tahara.
      expect(find.text('طهارة'), findsWidgets);

      // All 6 segments render (haid=4, tahara1=26, fertile=7, tahara2=8,
      // prePeriod=3, expected=1 for this fixture — none filtered to 0).
      for (final key in [
        'phase-node-haid',
        'phase-node-tahara1',
        'phase-node-fertile',
        'phase-node-tahara2',
        'phase-node-prePeriod',
        'phase-node-expected',
      ]) {
        expect(
          find.byKey(Key(key)),
          findsOneWidget,
          reason: '$key should render',
        );
      }

      // Exactly one "you are here" marker, on tahara1 (the fixture's last
      // period ended well before the fertile window, so the statistical
      // model resolves "today" to the first purity span, not the second).
      expect(find.text('أنتِ هنا'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-tahara1')),
          matching: find.text('أنتِ هنا'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.text('أنتِ هنا'),
        ),
        findsNothing,
      );

      // Pre-Period must show its real constant (3), not the old hardcoded
      // '1'.
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-prePeriod')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );

      // The Haid node is inactive here, so it must show a plain flat
      // duration ("يوم"), never the hardcoded "of N"/"من N" progress
      // format.
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.text('يوم'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.textContaining('من'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'actively bleeding (day 5): "you are here" is on Haid, and its '
    'denominator is the real computed average period length, not the old '
    'hardcoded 5 — true even though the statistical model would '
    'otherwise place "today" inside the fertile window',
    (tester) async {
      await ParityTestHarness.pump(tester, arabic: true);
      await seedLogs(tester, [
        // One completed 7-day episode — its real length must show up as
        // the Haid node's denominator later, proving it isn't a fabricated
        // constant.
        log(id: '1', date: '2026-06-01T08:00:00.000', flow: 'medium'),
        log(id: '2', date: '2026-06-08T08:00:00.000', flow: 'none'),
        // A currently-active episode, 5 days in as of the fixed test clock
        // (2026-08-18).
        log(id: '3', date: '2026-08-14T08:00:00.000', flow: 'medium'),
        log(id: '4', date: '2026-08-15T08:00:00.000', flow: 'medium', cycleDay: 2),
        log(id: '5', date: '2026-08-16T08:00:00.000', flow: 'medium', cycleDay: 3),
        log(id: '6', date: '2026-08-17T08:00:00.000', flow: 'medium', cycleDay: 4),
        log(id: '7', date: '2026-08-18T08:00:00.000', flow: 'medium', cycleDay: 5),
      ]);

      expect(find.text('حيض'), findsWidgets);

      // The guarantee: exactly one "you are here" marker, and it's on
      // Haid — not Fertile, even though this fixture's own average-cycle
      // math would statistically place "today" inside the fertile window.
      expect(find.text('أنتِ هنا'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.text('أنتِ هنا'),
        ),
        findsOneWidget,
      );
      for (final key in [
        'phase-node-tahara1',
        'phase-node-fertile',
        'phase-node-tahara2',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.text('أنتِ هنا'),
          ),
          findsNothing,
          reason: '$key must never be marked current while actually bleeding',
        );
      }

      // Real elapsed day (5) with the real average period length (7) —
      // not the previous hardcoded "من 5".
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.text('من 7'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.text('من 5'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'currently bleeding but no completed episode has ever been recorded: '
    'the pill shows an honest no-data message instead of a countdown built '
    'from a fabricated 0, and the Haid node has no fake denominator',
    (tester) async {
      await ParityTestHarness.pump(tester, arabic: true);
      await seedLogs(tester, [
        // Two prior starts (enough for cycle-length averaging) but neither
        // was ever logged as ended — averagePeriodLength must stay null.
        log(id: '1', date: '2026-06-01T08:00:00.000', flow: 'medium'),
        log(id: '2', date: '2026-07-01T08:00:00.000', flow: 'medium'),
        log(id: '3', date: '2026-08-14T08:00:00.000', flow: 'medium'),
        log(id: '4', date: '2026-08-15T08:00:00.000', flow: 'medium', cycleDay: 2),
        log(id: '5', date: '2026-08-16T08:00:00.000', flow: 'medium', cycleDay: 3),
        log(id: '6', date: '2026-08-17T08:00:00.000', flow: 'medium', cycleDay: 4),
        log(id: '7', date: '2026-08-18T08:00:00.000', flow: 'medium', cycleDay: 5),
      ]);

      expect(
        find.text('نتابع حيضك — سيظهر تقدير الطُهر بعد تسجيل دورة كاملة.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.text('يوم'),
        ),
        findsOneWidget,
        reason: 'no averagePeriodLength yet — must fall back to a plain '
            'unit, never a fabricated "of N"',
      );
    },
  );

  testWidgets(
    'manual istihadah mode still shows a real day count, not a blank or '
    'crashed stepper — the toggle only overrides the label, never the '
    'underlying data source',
    (tester) async {
      await ParityTestHarness.pump(tester, arabic: true);
      await seedLogs(tester, [
        log(id: '1', date: '2026-06-01T08:00:00.000', flow: 'medium'),
        log(id: '2', date: '2026-06-08T08:00:00.000', flow: 'none'),
        log(id: '3', date: '2026-08-14T08:00:00.000', flow: 'medium'),
        log(id: '4', date: '2026-08-15T08:00:00.000', flow: 'medium', cycleDay: 2),
        log(id: '5', date: '2026-08-16T08:00:00.000', flow: 'medium', cycleDay: 3),
        log(id: '6', date: '2026-08-17T08:00:00.000', flow: 'medium', cycleDay: 4),
        log(id: '7', date: '2026-08-18T08:00:00.000', flow: 'medium', cycleDay: 5),
      ]);

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(600);
      await tester.pumpAndSettle();

      final toggle = find.byType(Switch);
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      // Scroll back up so the ring/stepper (culled while we were down at
      // the toggle) are rebuilt and visible again.
      scrollable.position.jumpTo(0);
      await tester.pumpAndSettle();

      // The ring's center headline now folds the state label into a full
      // "day X of <phase>" sentence rather than showing it standalone, so
      // match on containment rather than an exact string.
      expect(find.textContaining('استحاضة'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const Key('phase-node-haid')),
          matching: find.text('5'),
        ),
        findsOneWidget,
        reason:
            'the toggle must not blank out the real, grounded episode day '
            'count — only override the displayed label',
      );
    },
  );
}
