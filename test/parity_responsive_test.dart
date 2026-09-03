import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/parity_test_harness.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets(
      'all core screens have no overflow at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await ParityTestHarness.pump(tester, arabic: false, size: size);
        expect(
          tester.takeException(),
          isNull,
          reason: 'Dashboard overflowed at $size',
        );
        for (final tab in [
          'Calendar',
          'Insights',
          'Community',
          'Profile',
          'Today',
        ]) {
          await tester.tap(find.text(tab));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester.takeException(),
            isNull,
            reason: '$tab overflowed at $size',
          );
        }
      },
    );
  }
}
