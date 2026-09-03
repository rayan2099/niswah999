import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/main.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('Insights English matches 390x844 reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false, initialTabIndex: 2);
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/insights_en_390x844.png'),
    );
  });
  testWidgets('Insights Arabic matches 390x844 RTL reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: true, initialTabIndex: 2);
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/insights_ar_390x844.png'),
    );
  });
}
