import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Found by the Arabic acceptance suite (D-016): the root MaterialApp set a
/// `locale` but no localization delegates, so every built-in Material string —
/// the time/date pickers ("Select time", "Cancel", "OK"), tooltips, the
/// text-selection menu — stayed English in Arabic mode. The live proof is the
/// Arabic persona AR3 (reminder time picker); this guards the wiring itself.
void main() {
  test('the root MaterialApp installs the global localization delegates', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('GlobalMaterialLocalizations.delegate'));
    expect(main, contains('GlobalWidgetsLocalizations.delegate'));
    expect(main, contains('GlobalCupertinoLocalizations.delegate'));
    expect(main, contains("supportedLocales: const [Locale('ar'), Locale('en')]"));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('flutter_localizations:'));
  });
}
