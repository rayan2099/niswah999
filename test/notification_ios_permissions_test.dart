import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/app_clock.dart';

import 'support/notification_platform_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NotificationPlatformHarness os;
  setUp(() async {
    os = NotificationPlatformHarness();
    await os.install(platform: TargetPlatform.iOS);
  });
  tearDown(() => os.uninstall());
  test(
    'iOS denied permission is returned before either scheduling API is called',
    () async {
      os.allowed = false;
      final service = NotificationService.instance;
      expect(
        await service.scheduleAt(
          id: 1,
          title: 'N',
          body: 'R',
          when: AppClock.now().add(const Duration(hours: 1)),
        ),
        NotificationSchedulingOutcome.permissionUnavailable,
      );
      expect(
        await service.scheduleDaily(
          id: 2,
          title: 'N',
          body: 'R',
          hour: 10,
          minute: 0,
        ),
        NotificationSchedulingOutcome.permissionUnavailable,
      );
      expect(os.scheduled, isEmpty);
      expect(os.calls, contains('checkPermissions'));
    },
  );
}
