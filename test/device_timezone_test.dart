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
  setUp(() {
    // Hardening 3: DeviceTimezone's cache is a static, so it otherwise
    // leaks across tests within this file — every test starts from a
    // known-empty cache regardless of execution order.
    DeviceTimezone.invalidateCache();
  });

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

  group('Hardening 3 — the cache must not be permanent', () {
    testWidgets(
      'without invalidateCache or forceRefresh, a changed platform value '
      'is NOT reflected (proves a cache genuinely exists)',
      (tester) async {
        mockDeviceTimezoneForTest('Asia/Riyadh');
        expect(await DeviceTimezone.currentId(), 'Asia/Riyadh');

        // Simulates travel: the device's real zone has changed, but
        // nothing has told DeviceTimezone to look again yet.
        mockDeviceTimezoneForTest('America/Vancouver');
        expect(
          await DeviceTimezone.currentId(),
          'Asia/Riyadh',
          reason:
              'the stale cached value is still returned until '
              'something explicitly invalidates or bypasses it',
        );
      },
    );

    testWidgets('invalidateCache() makes the next currentId() call genuinely '
        're-query the platform — the exact mechanism app-resume relies on '
        'to detect a travel/manual timezone change', (tester) async {
      mockDeviceTimezoneForTest('Asia/Riyadh');
      expect(await DeviceTimezone.currentId(), 'Asia/Riyadh');

      mockDeviceTimezoneForTest('America/Vancouver');
      DeviceTimezone.invalidateCache();

      expect(await DeviceTimezone.currentId(), 'America/Vancouver');
    });

    testWidgets(
      'forceRefresh: true bypasses the cache without needing a separate '
      'invalidateCache() call first',
      (tester) async {
        mockDeviceTimezoneForTest('Asia/Riyadh');
        expect(await DeviceTimezone.currentId(), 'Asia/Riyadh');

        mockDeviceTimezoneForTest('America/Vancouver');
        expect(
          await DeviceTimezone.currentId(forceRefresh: true),
          'America/Vancouver',
        );
      },
    );
  });
}
