import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:niswah/core/auth/auth_controller.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/utils/app_clock.dart';

import 'logging_sync_hardening/support/fake_supabase.dart';
import 'support/notification_platform_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real auth session replacement invalidates and cancels old reminders',
    () async {
      final os = NotificationPlatformHarness();
      await os.install();
      await Supabase.initialize(
        url: 'http://fake.supabase.local',
        publishableKey: 'anon-key',
        httpClient: MockClient(
          (request) async => http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
          detectSessionInUri: false,
          autoRefreshToken: false,
        ),
      );
      final client = Supabase.instance.client;
      await client.auth.setInitialSession(
        fakeSessionJson('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
      );
      AuthController.instance.init();
      // Drain the initial-session event before scheduling account A's work.
      await Future<void>.delayed(Duration.zero);
      final service = NotificationService.instance;
      await service.finishPendingAccountCleanup();
      expect(
        await service.scheduleAt(
          id: 701,
          title: 'Niswah',
          body: 'Reminder',
          when: AppClock.now().add(const Duration(hours: 1)),
        ),
        NotificationSchedulingOutcome.accepted,
      );
      final generation = service.sessionGeneration;
      final changed = Completer<void>();
      void listener() {
        if (service.sessionGeneration > generation && !changed.isCompleted) {
          changed.complete();
        }
      }

      AuthController.instance.addListener(listener);
      try {
        await client.auth.setInitialSession(
          fakeSessionJson('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
        );
        await changed.future.timeout(const Duration(seconds: 2));
        await service.finishPendingAccountCleanup();
        expect(service.sessionGeneration, greaterThan(generation));
        expect(os.pending, isEmpty);
      } finally {
        AuthController.instance.removeListener(listener);
        await Supabase.instance.dispose();
        await os.uninstall();
      }
    },
  );
}
