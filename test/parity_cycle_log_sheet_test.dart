import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import 'package:niswah/main.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('Arabic blood log sheet matches the mobile reference', (
    tester,
  ) async {
    await ParityTestHarness.pump(tester, arabic: true);
    // Madhhab Resolution Gate wave (2026-09-16): the log sheet's default
    // (period) mode now gates on a SELECTED Madhhab — selecting one here
    // matches a real already-onboarded user and keeps this test's own
    // pre-existing (unrelated) golden-image comparison the thing that
    // actually gets exercised. Must come *after* the harness's own pump()
    // — that call is what installs the SharedPreferences mock this
    // selection needs to persist against; calling it any earlier hits a
    // real (nonexistent in tests) platform channel and hangs.
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
    await tester.tap(find.byKey(const Key('today-cycle-log')));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل اليوم'), findsWidgets);
    expect(find.text('شدة التدفق'), findsOneWidget);
    expect(find.text('لون الدم'), findsOneWidget);
    // Mood now shares the same rating-row UI as the Wellbeing check-in, and
    // sits directly under Flow/Color — Energy/Sleep follow it, pushed below
    // the fold now that Mood no longer needs its own separate scroll.
    expect(find.text('المزاج'), findsWidgets);
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/cycle_log_sheet_ar_390x844.png'),
    );
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    scrollable.position.jumpTo(700);
    await tester.pumpAndSettle();
    expect(find.text('الطاقة'), findsOneWidget);
    expect(find.text('النوم'), findsOneWidget);
    scrollable.position.jumpTo(1400);
    await tester.pumpAndSettle();
    expect(find.text('الأعراض'), findsOneWidget);
    expect(find.text('آلام الثدي'), findsOneWidget);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('ملاحظات'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
