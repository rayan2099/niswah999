import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AU-007/AU-008: `common_widgets.dart:217` used a physical
/// `EdgeInsets.only(left: 8.0)` inside a `Row` — invisible to any golden
/// test until an Arabic-locale golden happened to capture that specific
/// widget, since it's a layout defect that only misbehaves in RTL. This
/// test is the "add a lint rule" half of AU-007/AU-008's remediation: it
/// scans every `.dart` source file directly for the exact pattern that
/// caused it (`EdgeInsets.only(...left:` / `...right:`), so a new instance
/// fails a test run immediately rather than waiting to be noticed in a
/// screenshot.
///
/// `EdgeInsetsDirectional` and `Positioned`/`PositionedDirectional` are
/// intentionally out of scope here — this targets the specific
/// `EdgeInsets.only` constructor, matching the two real instances found and
/// fixed this wave.
void main() {
  test(
    'no lib/ source file uses physical EdgeInsets.only(left:/right:) — use '
    'EdgeInsetsDirectional.only(start:/end:) so padding follows reading '
    'direction in both English (LTR) and Arabic (RTL)',
    () {
      final libDir = Directory('lib');
      final offenders = <String>[];
      // A physical left/right side used as a named argument to
      // `EdgeInsets.only(`, allowing other named args (top/bottom) on
      // either side in any order.
      final pattern = RegExp(r'EdgeInsets\.only\([^)]*\b(left|right)\s*:');

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (pattern.hasMatch(content)) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Physical EdgeInsets.only(left:/right:) found — replace with '
            'EdgeInsetsDirectional.only(start:/end:) so the padding follows '
            'reading direction: ${offenders.join(', ')}',
      );
    },
  );
}
