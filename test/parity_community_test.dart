import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/community_language_controller.dart';
import 'package:niswah/main.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('Community English matches 390x844 reference', (tester) async {
    // Requirement 4: Community now gates first entry on an explicit
    // community-language choice. Pre-selecting it directly (rather than
    // relying on SharedPreferences/controller load timing in this
    // harness) keeps this golden capturing the board screen itself, not
    // the gate dialog — the gate's own behavior is covered separately.
    await ParityTestHarness.pump(tester, arabic: false);
    await CommunityLanguageController.instance.select(CommunityLanguage.en);
    await tester.tap(find.text('Community'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/community_en_390x844.png'),
    );
  });
  testWidgets('Community Arabic matches 390x844 RTL reference', (tester) async {
    await ParityTestHarness.pump(tester, arabic: true);
    await CommunityLanguageController.instance.select(CommunityLanguage.ar);
    await tester.tap(find.text('المجتمع'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(NiswahApp),
      matchesGoldenFile('goldens/community_ar_390x844.png'),
    );
  });
}
