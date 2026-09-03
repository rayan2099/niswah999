import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/core/preferences/ttc_mode_controller.dart';
import 'package:niswah/features/auth/presentation/screens/profile_screen.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('marital status gates pregnancy tools and husband report', (
    tester,
  ) async {
    // The pregnancy-chance card also requires sufficient cycle history —
    // seed two Haid starts so toggling marital status/TTC mode is the only
    // remaining variable this test is actually exercising.
    final seededLogs = jsonEncode([
      CycleLog(
        id: 'seed-1',
        userId: 'local-user',
        date: DateTime(2026, 7, 1),
        flow: FlowLevel.medium,
        cycleDay: 1,
      ).toJson(),
      CycleLog(
        id: 'seed-2',
        userId: 'local-user',
        date: DateTime(2026, 7, 29),
        flow: FlowLevel.medium,
        cycleDay: 1,
      ).toJson(),
    ]);
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      extraPrefs: {'niswah_cycle_tracking_logs': seededLogs},
    );
    await tester.tap(find.text('Calendar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Chance of pregnancy'), findsNothing);

    await MaritalStatusController.instance.setMarried(true);
    await TtcModeController.instance.setEnabled(true);
    await tester.pump();
    expect(find.text('Chance of pregnancy'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.text('Husband Report'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Husband Report'), findsOneWidget);
    await MaritalStatusController.instance.setMarried(false);
    await TtcModeController.instance.setEnabled(false);
  });

  testWidgets('Calendar renders only the selected date system', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await tester.tap(find.text('Calendar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('August 2026'), findsNWidgets(3));
    expect(find.textContaining('Saf'), findsNothing);
    await tester.tap(find.text('Hijri').first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Rabi I 1448'), findsNWidgets(3));
    expect(find.text('August 2026'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Month summary opens historical month picker', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await tester.tap(find.text('Calendar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    await tester.tap(find.byKey(const Key('month-summary-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Select month'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Month summary exposes yearly and custom periods', (
    tester,
  ) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await tester.tap(find.text('Calendar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    await tester.tap(find.text('Yearly'));
    await tester.pump();
    expect(find.text('Period summary'), findsOneWidget);
    await tester.tap(find.text('Custom period'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Choose a quick period or set exact start and end dates.'),
      findsOneWidget,
    );
    expect(find.text('30 days'), findsOneWidget);
    expect(find.text('Apply period'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('custom-range-calendar-toggle')),
        matching: find.text('Hijri'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('annual summary opens a year picker in the selected calendar', (
    tester,
  ) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await tester.tap(find.text('Calendar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Hijri').first);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    await tester.tap(find.text('Yearly'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('month-summary-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Select year'), findsOneWidget);
    expect(find.text('1448 AH'), findsOneWidget);
    expect(find.text('Select month'), findsNothing);
  });

  testWidgets('Insights symptom period can be changed', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await tester.tap(find.text('Insights'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.byKey(const Key('insights-trend-range')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('insights-trend-range')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 6 months'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('insights-trend-range')),
        matching: find.text('Last 6 months'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Profile toggle state changes without affecting adjacent toggles',
    (tester) async {
      await ParityTestHarness.pump(tester, arabic: false);
      await tester.tap(find.text('Profile'));
      await tester.pump(const Duration(milliseconds: 300));
      final switches = find.byType(Switch);
      expect(switches, findsWidgets);
      await tester.ensureVisible(switches.first);
      await tester.pump(const Duration(milliseconds: 300));
      final first = tester.widget<Switch>(switches.first).value;
      final second = tester.widget<Switch>(switches.at(1)).value;
      await tester.tap(switches.first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Switch>(switches.first).value, !first);
      expect(tester.widget<Switch>(switches.at(1)).value, second);
    },
  );

  testWidgets('central action opens and closes Dr Niswah overlay', (
    tester,
  ) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('Niswah'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
