import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/utils/device_timezone.dart';

import 'support/device_timezone_test_support.dart';

/// Menstrual Data Integrity charter, PR #4 completion wave — Fix B.
///
/// A real finding from building this: `FlutterTimezone.getLocalTimezone()`
/// (a bare `MethodChannel.invokeMethod` with no mock handler registered)
/// does not throw quickly under `testWidgets` the way it does under a
/// plain `test()` — it hangs indefinitely, because `testWidgets`' binding
/// waits for a handler that never arrives rather than immediately
/// rejecting with `MissingPluginException`. This was caught by
/// `start_bleeding_sheet_test.dart` timing out, not by this file — a
/// bare `test()` on its own gave a false sense that the graceful-
/// degradation contract was already covered. `mockDeviceTimezoneForTest`
/// closes that gap for every test in this app that reaches this code
/// path, mirroring `resetSecureLocalStoreForTest`'s own reason for
/// existing.
///
/// Real device behavior (does the plugin actually return "Asia/Riyadh" on
/// a real iOS/Android device) is E4 and is not claimed here.
void main() {
  testWidgets(
    'currentId() degrades to null rather than hanging or throwing when '
    'the platform channel is unavailable',
    (tester) async {
      mockDeviceTimezoneForTest();
      final id = await DeviceTimezone.currentId();
      expect(id, isNull);
    },
  );

  testWidgets(
    'currentId() returns the real value the platform channel provides',
    (tester) async {
      mockDeviceTimezoneForTest('Asia/Riyadh');
      final id = await DeviceTimezone.currentId();
      expect(id, 'Asia/Riyadh');
    },
  );
}
