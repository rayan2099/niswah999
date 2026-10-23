import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:niswah/core/preferences/notification_log_controller.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/features/ai_assistant/presentation/viewmodels/chat_view_model.dart';

import 'logging_sync_hardening/support/fake_supabase.dart';
import 'support/notification_platform_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final succeed in [true, false]) {
    test(
      'late urgent chat ${succeed ? 'response' : 'failure'} cannot notify the next session',
      () async {
        final os = NotificationPlatformHarness();
        await os.install();
        final requested = Completer<void>();
        final response = Completer<http.Response>();
        await Supabase.initialize(
          url: 'http://fake.supabase.local',
          publishableKey: 'anon-key',
          httpClient: MockClient((request) async {
            requested.complete();
            return response.future;
          }),
          authOptions: const FlutterAuthClientOptions(
            localStorage: EmptyLocalStorage(),
            detectSessionInUri: false,
            autoRefreshToken: false,
          ),
        );
        await Supabase.instance.client.auth.setInitialSession(
          fakeSessionJson('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
        );
        final vm = ChatViewModel();
        try {
          final reply = vm.sendViaDrNiswahBackendForTesting(
            threadId: 'thread-a',
            userId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            content: 'I have severe pain',
          );
          await requested.future;
          await NotificationService.instance.cancelAll();
          if (succeed) {
            response.complete(
              http.Response(
                '{"reply":"Review this update","urgent":true}',
                200,
                headers: {'content-type': 'application/json'},
              ),
            );
          } else {
            response.complete(
              http.Response(
                '{"error":"offline"}',
                400,
                headers: {'content-type': 'application/json'},
              ),
            );
          }
          await reply;
          await NotificationService.instance.finishPendingAccountCleanup();
          expect(os.calls, isNot(contains('show')));
          expect(NotificationLogController.instance.allEntries, isEmpty);
        } finally {
          vm.dispose();
          await Supabase.instance.dispose();
          await os.uninstall();
        }
      },
    );
  }
}
