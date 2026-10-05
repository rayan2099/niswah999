import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android main manifest grants INTERNET to release builds', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android.permission.INTERNET'),
      reason:
          'Release builds do not merge the debug/profile manifests, so the '
          'main manifest must grant INTERNET for Supabase/API/Sentry traffic.',
    );
  });
}
