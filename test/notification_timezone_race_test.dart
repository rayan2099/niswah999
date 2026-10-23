import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/device_timezone.dart';

import 'support/notification_platform_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'late stale timezone resolution cannot overwrite the current zone or cache',
    () async {
      final os = NotificationPlatformHarness();
      await os.install();
      final oldZone = Completer<String>();
      final started = Completer<void>();
      var oldCurrent = true;
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NotificationPlatformHarness.timezoneChannel,
            (_) async {
              reads++;
              if (reads == 1) {
                started.complete();
                return oldZone.future;
              }
              return 'America/New_York';
            },
          );
      try {
        final service = NotificationService.instance;
        final oldRefresh = service.withWorkGuard(
          () => oldCurrent,
          () => service.refreshLocalTimezone(forceRefresh: true),
        );
        await started.future;
        oldCurrent = false;
        await service.refreshLocalTimezone(forceRefresh: true);
        expect(service.activeTimezoneId, 'America/New_York');
        oldZone.complete('Asia/Riyadh');
        await oldRefresh;
        expect(service.activeTimezoneId, 'America/New_York');
        expect(await DeviceTimezone.currentId(), 'America/New_York');
        expect(reads, 2);
      } finally {
        await os.uninstall();
      }
    },
  );
}
