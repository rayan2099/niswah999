import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:niswah/features/notifications/data/services/app_notification_session.dart';
import 'package:niswah/features/notifications/domain/entities/activity_notification.dart';
import 'package:niswah/features/notifications/domain/entities/notification_target.dart';
import 'package:niswah/features/notifications/presentation/viewmodels/activity_inbox_controller.dart';

import 'logging_sync_hardening/support/fake_supabase.dart';
import 'support/notification_platform_harness.dart';
import 'app_wide_notification_controller_test.dart' show ActivityRepo;

const user = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NotificationPlatformHarness os;
  late FakeSupabase backend;
  late ActivityRepo repo;
  final session = AppNotificationSession.instance;
  setUp(() async {
    os = NotificationPlatformHarness();
    await os.install();
    backend = FakeSupabase((_, _) async => http.Response('null', 200));
    await backend.signIn(user);
    repo = ActivityRepo()
      ..rows = [
        ActivityNotification(
          id: 'event',
          kind: 'privateMessage',
          target: const NotificationTarget(
            destination: NotificationDestination.conversation,
            userId: user,
            targetId: 'thread',
          ),
          createdAt: DateTime.utc(2030),
        ),
      ];
    await session.start(backend.client, repositoryFactory: () => repo);
    await ActivityInboxController.instance.refresh();
  });
  tearDown(() async {
    await session.stop();
    await backend.client.dispose();
    await os.uninstall();
  });
  Map<String, dynamic> data({String id = user, String event = 'event'}) => {
    'userId': id,
    'eventId': event,
    'destination': 'conversation',
    'targetId': 'thread',
  };
  test('verified foreground activity produces one alert under duplicate concurrent callbacks', () async {
    await Future.wait([
      session.handleForegroundData(data()),
      session.handleForegroundData(data()),
    ]);
    expect(os.calls.where((c) => c == 'show').length, 1);
  });
  test('foreign account, fabricated event and currently open conversation cannot alert', () async {
    await session.handleForegroundData(data(id: 'other'));
    await session.handleForegroundData(data(event: 'fabricated'));
    session.activeConversation = 'thread';
    await session.handleForegroundData(data());
    expect(os.calls, isNot(contains('show')));
  });
  test(
    'sign-out invalidates a late inbox lookup before showing an alert',
    () async {
      repo.held = Completer<List<ActivityNotification>>();
      final showing = session.handleForegroundData(data());
      await Future<void>.delayed(Duration.zero);
      await session.stop();
      repo.held!.complete(repo.rows);
      await showing;
      expect(os.calls, isNot(contains('show')));
    },
  );
}
