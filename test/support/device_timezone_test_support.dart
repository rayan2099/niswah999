import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mocks the `flutter_timezone` platform channel — call from `setUp()` in
/// any test that (directly or indirectly, via `DeviceTimezone`) reaches
/// `FlutterTimezone.getLocalTimezone()`. Mirrors
/// `resetSecureLocalStoreForTest()`'s own reason for existing: without a
/// registered mock handler, a `MethodChannel.invokeMethod` call under
/// `testWidgets` hangs indefinitely rather than throwing quickly — unlike
/// `flutter_secure_storage`, which ships its own in-memory
/// `TestFlutterSecureStoragePlatform`, `flutter_timezone` has no
/// equivalent test double, so the mock is set up directly here.
///
/// Defaults to simulating "unavailable" (returns null via a thrown
/// `MissingPluginException`, exactly matching what a real, un-mocked
/// channel throws in a plain `test()` — see `DeviceTimezone.currentId`'s
/// own graceful-degradation contract) unless [timezoneId] is given.
void mockDeviceTimezoneForTest([String? timezoneId]) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (
        call,
      ) async {
        if (call.method == 'getLocalTimezone') {
          if (timezoneId == null) {
            throw MissingPluginException();
          }
          return timezoneId;
        }
        return null;
      });
}
