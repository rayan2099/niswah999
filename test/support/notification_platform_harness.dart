import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/core/preferences/notification_log_controller.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/core/utils/device_timezone.dart';

/// Stateful fake OS request registry behind the real installed plugin's
/// method channel. Acceptance here is not proof of physical OS delivery.
class NotificationPlatformHarness {
  static const channel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  static const timezoneChannel = MethodChannel('flutter_timezone');
  final pending = <int, Map<String, dynamic>>{};
  final calls = <String>[];
  final scheduled = <Map<String, dynamic>>[];
  bool allowed = true;
  bool failCleanup = false;
  bool failPendingRead = false;
  final failedCancellations = <int>{};
  String? timezone = 'UTC';
  Future<void> Function(Map<String, dynamic>)? beforeSchedule;

  Future<void> install({
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    SharedPreferences.setMockInitialValues({});
    AppClock.now = () => DateTime.utc(2030, 1, 15, 9);
    debugDefaultTargetPlatformOverride = platform;
    if (platform == TargetPlatform.iOS) {
      IOSFlutterLocalNotificationsPlugin.registerWith();
    } else {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(timezoneChannel, (_) async => timezone);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'initialize':
        case 'requestNotificationsPermission':
        case 'requestPermissions':
          return true;
        case 'areNotificationsEnabled':
          return allowed;
        case 'checkPermissions':
          return {'isEnabled': allowed, 'isAlertEnabled': allowed};
        case 'zonedSchedule':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          await beforeSchedule?.call(args);
          scheduled.add(args);
          pending[args['id'] as int] = args;
          return null;
        case 'cancel':
          if (failedCancellations.contains(call.arguments['id'])) {
            throw PlatformException(code: 'CANCEL_FAILED');
          }
          pending.remove(call.arguments['id'] as int);
          return null;
        case 'cancelAll':
          if (failCleanup) throw PlatformException(code: 'CANCEL_FAILED');
          pending.clear();
          return null;
        case 'pendingNotificationRequests':
          if (failPendingRead) throw PlatformException(code: 'READ_FAILED');
          return pending.values
              .map((p) => {'id': p['id'], 'payload': p['payload']})
              .toList();
        default:
          return null;
      }
    });
    DeviceTimezone.invalidateCache();
    await NotificationService.instance.initialize();
    await NotificationService.instance.refreshLocalTimezone(forceRefresh: true);
    await NotificationService.instance.cancelAll();
    NotificationLogController.instance.resetInMemory();
    await NotificationLogController.instance.load();
    PrayerLocationController.instance.resetInMemory();
    PregnancyStatusController.instance.resetInMemory();
    calls.clear();
  }

  Future<void> uninstall() async {
    beforeSchedule = null;
    failCleanup = false;
    await NotificationService.instance.cancelAll();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
    NotificationLogController.instance.resetInMemory();
    PrayerLocationController.instance.resetInMemory();
    PregnancyStatusController.instance.resetInMemory();
    AppClock.reset();
    debugDefaultTargetPlatformOverride = null;
  }
}
