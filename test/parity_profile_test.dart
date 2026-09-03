import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/main.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('Profile English matches 390x844 reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: false);
    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/profile_en_390x844.png'),
    );
  });
  testWidgets('Profile Arabic matches 390x844 RTL reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: true);
    await tester.tap(find.text('الملف الشخصي'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/profile_ar_390x844.png'),
    );
  });
}
