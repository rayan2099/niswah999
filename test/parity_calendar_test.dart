import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/main.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('Calendar English matches 390x844 reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await tester.tap(find.text('Calendar'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/calendar_en_390x844.png'),
    );
  });
  testWidgets('Calendar Arabic matches 390x844 RTL reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: true);
    await tester.tap(find.text('التقويم'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/calendar_ar_390x844.png'),
    );
  });
}
