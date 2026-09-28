import 'dart:async';

import '../errors/app_error_reporter.dart';
import 'marital_status_controller.dart';
import 'notification_log_controller.dart';
import 'pregnancy_status_controller.dart';
import 'prayer_location_controller.dart';
import 'ttc_mode_controller.dart';

/// Keeps the in-memory singletons that mirror device-local, per-user answers
/// (see [UserScopedPreferences]) in step with whoever is signed in.
class LocalPreferenceScope {
  LocalPreferenceScope._();

  /// Sign-out: forget everything in memory so the next account can never
  /// observe the previous account's answers, even for one frame.
  static void resetInMemory() {
    MaritalStatusController.instance.resetInMemory();
    TtcModeController.instance.resetInMemory();
    PregnancyStatusController.instance.resetInMemory();
    PrayerLocationController.instance.resetInMemory();
    NotificationLogController.instance.resetInMemory();
  }

  /// Sign-in: load the signed-in user's own values. Each load is independent —
  /// one failing must not leave the others holding stale values.
  static Future<void> reload() async {
    final loads = <String, Future<void> Function()>{
      'marital': MaritalStatusController.instance.load,
      'ttc': TtcModeController.instance.load,
      'pregnancy': PregnancyStatusController.instance.load,
      'prayer_location': PrayerLocationController.instance.load,
      'notification_log': NotificationLogController.instance.load,
    };
    for (final entry in loads.entries) {
      try {
        await entry.value();
      } catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'LocalPreferenceScope.reload',
          feature: entry.key,
        );
      }
    }
  }
}
