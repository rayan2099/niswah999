import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/main.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('Community English matches 390x844 reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await tester.tap(find.text('Community'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/community_en_390x844.png'),
    );
  });
  testWidgets('Community Arabic matches 390x844 RTL reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: true);
    await tester.tap(find.text('المجتمع'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/community_ar_390x844.png'),
    );
  });
}
