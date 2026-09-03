import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets(
    'Today shows an explicit state when cycle history is insufficient',
    (tester) async {
      await ParityTestHarness.pump(tester, arabic: true);

      expect(find.text('سجّلي دورتكِ لمعرفة يومكِ'), findsOneWidget);
      expect(
        find.text('نحتاج إلى بدايتَي حيض لحساب نمطكِ الشخصي.'),
        findsOneWidget,
      );
      expect(find.text('تسجيل الدورة'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('٣٦'), findsNothing);
      expect(find.textContaining('٢٨'), findsNothing);
    },
  );
}
