import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/main.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets(
    'Dashboard defaults to mood check-in and prayer times without cycle data',
    (tester) async {
      await ParityTestHarness.pump(tester, arabic: true);

      expect(find.text('كيف نفسيتكِ اليوم؟'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pump();
      expect(find.text('الصلاة واجبة عليكِ'), findsOneWidget);
      expect(find.text('الصلاة مرفوعة عنكِ'), findsNothing);
    },
  );

  testWidgets('Dashboard English matches 390x844 reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/dashboard_en_390x844.png'),
    );
  });
  testWidgets('Dashboard Arabic matches 390x844 RTL reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: true);
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/dashboard_ar_390x844.png'),
    );
  });
}
