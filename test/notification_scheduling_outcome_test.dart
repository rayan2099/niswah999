import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/services/notification_service.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

/// New integrity finding — NotificationService.scheduleAt/scheduleDaily/
/// cancel previously caught every platform exception internally and
/// returned `void`, giving a caller no way to tell "the OS accepted
/// this" apart from "it silently failed." These tests mock the real
/// `flutter_local_notifications` platform channel itself (not a fake
/// stand-in) to inject a genuine platform-scheduling failure and prove
/// the returned outcome is honest — never a false "accepted."
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var shouldFailZonedSchedule = false;
  var shouldFailCancel = false;
  var notificationsEnabled = true;

  setUp(() {
    shouldFailZonedSchedule = false;
    shouldFailCancel = false;
    notificationsEnabled = true;
    // The plugin's own initialize() resolves a platform-specific
    // implementation via this platform-interface singleton — nothing
    // registers one automatically under `flutter test` (that normally
    // happens via generated, platform-specific plugin registration code
    // that only runs on a real device/emulator). Registering Android's
    // own real implementation here means every call below still goes
    // through the SAME method-channel code path a real Android device
    // would use — genuinely exercising NotificationService's own logic,
    // not a hand-rolled stand-in for the plugin.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'createNotificationChannel':
            case 'getNotificationAppLaunchDetails':
              return null;
            case 'zonedSchedule':
              if (shouldFailZonedSchedule) {
                throw PlatformException(
                  code: 'SCHEDULE_EXACT_ALARM_PERMISSION_REQUIRED',
                  message: 'simulated platform scheduling rejection',
                );
              }
              return null;
            case 'cancel':
              if (shouldFailCancel) {
                throw PlatformException(
                  code: 'FAIL',
                  message: 'simulated cancellation failure',
                );
              }
              return null;
            case 'areNotificationsEnabled':
              return notificationsEnabled;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('NotificationService.scheduleAt outcome honesty', () {
    test('a platform call the OS actually accepts returns accepted', () async {
      await NotificationService.instance.initialize();
      final outcome = await NotificationService.instance.scheduleAt(
        id: 1,
        title: 'Niswah',
        body: 'Test',
        when: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(outcome, NotificationSchedulingOutcome.accepted);
    });

    test('a genuine platform scheduling rejection returns failed, never a '
        'false accepted — the exact false-success-audit gap this finding '
        'closes', () async {
      await NotificationService.instance.initialize();
      shouldFailZonedSchedule = true;

      final outcome = await NotificationService.instance.scheduleAt(
        id: 2,
        title: 'Niswah',
        body: 'Test',
        when: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(outcome, NotificationSchedulingOutcome.failed);
      expect(
        outcome,
        isNot(NotificationSchedulingOutcome.accepted),
        reason:
            'a caller that logs a "scheduled" audit event only on '
            'accepted must never see accepted here',
      );
    });

    test('a known-disabled OS notification permission is reported as '
        'permissionUnavailable — checked before ever attempting the '
        'platform scheduling call', () async {
      await NotificationService.instance.initialize();
      notificationsEnabled = false;

      final outcome = await NotificationService.instance.scheduleAt(
        id: 4,
        title: 'Niswah',
        body: 'Test',
        when: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(outcome, NotificationSchedulingOutcome.permissionUnavailable);
    });

    test('scheduleDaily surfaces the same honest failed outcome on a '
        'genuine platform rejection', () async {
      await NotificationService.instance.initialize();
      shouldFailZonedSchedule = true;

      final outcome = await NotificationService.instance.scheduleDaily(
        id: 3,
        title: 'Niswah',
        body: 'Test',
        hour: 20,
        minute: 0,
      );

      expect(outcome, NotificationSchedulingOutcome.failed);
    });
  });

  group('NotificationService.cancel outcome honesty', () {
    test('a successful cancellation returns true', () async {
      await NotificationService.instance.initialize();
      final result = await NotificationService.instance.cancel(1);
      expect(result, isTrue);
    });

    test('a genuine platform cancellation failure returns false — never '
        'recorded as a successful cancellation', () async {
      await NotificationService.instance.initialize();
      shouldFailCancel = true;

      final result = await NotificationService.instance.cancel(1);

      expect(result, isFalse);
    });
  });
}
