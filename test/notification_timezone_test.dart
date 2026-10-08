import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/device_timezone.dart';

const _channel = MethodChannel('flutter_timezone');

void _mockDeviceTimezone(String? id) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'getLocalTimezone') return id;
        return null;
      });
}

/// Closure Blocker 6 — the real fix under test: `NotificationService`
/// used to do `tz.setLocalLocation(tz.local)`, a no-op that never reads
/// the device's real IANA zone at all. These tests mock the platform
/// channel `flutter_timezone` itself uses, so they exercise the same
/// path a real device would — not merely a fake stand-in for
/// `DeviceTimezone`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  setUp(() {
    DeviceTimezone.invalidateCache();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('applies the real device IANA zone (Asia/Riyadh) to tz.local', () async {
    _mockDeviceTimezone('Asia/Riyadh');

    await NotificationService.instance.refreshLocalTimezone(forceRefresh: true);

    expect(NotificationService.instance.activeTimezoneId, 'Asia/Riyadh');
    expect(tz.local.name, 'Asia/Riyadh');
  });

  test('applies a different real device IANA zone (America/Vancouver) to '
      'tz.local — proves this is not a cached/first-call-only fluke', () async {
    _mockDeviceTimezone('America/Vancouver');

    await NotificationService.instance.refreshLocalTimezone(forceRefresh: true);

    expect(NotificationService.instance.activeTimezoneId, 'America/Vancouver');
    expect(tz.local.name, 'America/Vancouver');
  });

  test('DST forward: America/Vancouver observes a different UTC offset in '
      'July than in January, proving a real rules-aware zone was applied '
      '— never a fixed UTC-offset stand-in', () async {
    _mockDeviceTimezone('America/Vancouver');
    await NotificationService.instance.refreshLocalTimezone(forceRefresh: true);

    final winter = tz.TZDateTime(tz.local, 2026, 1, 15, 12);
    final summer = tz.TZDateTime(tz.local, 2026, 7, 15, 12);

    expect(winter.timeZoneOffset, const Duration(hours: -8));
    expect(summer.timeZoneOffset, const Duration(hours: -7));
  });

  test('DST backward: Asia/Riyadh never observes daylight saving — the same '
      'offset applies year-round', () async {
    _mockDeviceTimezone('Asia/Riyadh');
    await NotificationService.instance.refreshLocalTimezone(forceRefresh: true);

    final winter = tz.TZDateTime(tz.local, 2026, 1, 15, 12);
    final summer = tz.TZDateTime(tz.local, 2026, 7, 15, 12);

    expect(winter.timeZoneOffset, const Duration(hours: 3));
    expect(summer.timeZoneOffset, const Duration(hours: 3));
  });

  test('a platform-channel failure falls back to UTC honestly rather than '
      'leaving tz.local unset or crashing scheduling', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          throw PlatformException(code: 'UNAVAILABLE');
        });

    await NotificationService.instance.refreshLocalTimezone(forceRefresh: true);

    expect(NotificationService.instance.activeTimezoneId, isNull);
    expect(tz.local, tz.UTC);
  });
}
