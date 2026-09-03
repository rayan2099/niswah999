import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('Today lower Fiqh state matches the Arabic mobile reference', (
    tester,
  ) async {
    await ParityTestHarness.pump(tester, arabic: true);

    final prefs = await SharedPreferences.getInstance();
    final logsJson = jsonEncode([
      {
        "id": "1",
        "user_id": "local-user",
        "date": "2026-07-15T12:00:00.000",
        "flow": "medium",
        "cycle_day": 1,
        "sync_status": "synced",
      },
      {
        "id": "2",
        "user_id": "local-user",
        "date": "2026-08-15T12:00:00.000",
        "flow": "medium",
        "cycle_day": 1,
        "sync_status": "synced",
      },
      {
        "id": "3",
        "user_id": "local-user",
        "date": "2026-08-18T12:00:00.000",
        "flow": "medium",
        "cycle_day": 4,
        "sync_status": "synced",
      },
    ]);

    await prefs.setString('niswah_cycle_tracking_logs', logsJson);
    await prefs.setString('flutter.niswah_cycle_tracking_logs', logsJson);

    await tester.pumpWidget(NiswahApp(key: UniqueKey()));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(900);
    await tester.pumpAndSettle();

    expect(find.text('وضع الاستحاضة'), findsOneWidget);
    expect(find.text('الصلاة مرفوعة عنكِ'), findsWidgets);
    expect(find.text('بناءً على المذهب الHANBALI'), findsOneWidget);
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/today_lower_ar_390x844.png'),
    );
  });
}
