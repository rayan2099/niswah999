import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/notifications/domain/entities/notification_target.dart';
import 'package:niswah/features/notifications/presentation/navigation/notification_navigator.dart';
import 'package:niswah/features/private_messaging/data/repositories/mock_private_messaging_repository.dart';
import 'package:niswah/features/private_messaging/private_messaging_locator.dart';
import 'package:niswah/features/private_messaging/presentation/screens/chat_detail_screen.dart';

import 'logging_sync_hardening/support/fake_supabase.dart';

const user = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const other = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const targetId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var denied = false;
  var requests = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    await Supabase.initialize(
      url: 'http://fake.supabase.local',
      publishableKey: 'anon-key',
      httpClient: MockClient((request) async {
        requests++;
        final value = request.url.path.endsWith('/private_conversations')
            ? denied
                  ? null
                  : {
                      'id': targetId,
                      'participant_one': user,
                      'participant_two': other,
                      'created_at': '2030-01-01T00:00:00Z',
                      'updated_at': '2030-01-01T00:00:00Z',
                    }
            : [];
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
    await Supabase.instance.client.auth.setInitialSession(
      fakeSessionJson(user),
    );
    privateMessagingRepositoryOverride = MockPrivateMessagingRepository(
      currentUserId: user,
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets('foreign account target never queries data or changes screen', (
    tester,
  ) async {
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            root = context;
            return const Scaffold(body: Text('Home'));
          },
        ),
      ),
    );
    final before = requests;
    await NotificationNavigator.open(
      root,
      const NotificationTarget(
        destination: NotificationDestination.conversation,
        userId: other,
        targetId: targetId,
      ),
      calendar: () {},
      wellbeing: () {},
    );
    await tester.pumpAndSettle();
    expect(requests, before);
    expect(find.byType(ChatDetailScreen), findsNothing);
  });
  testWidgets(
    'verified conversation opens the chat and removes lookup progress',
    (tester) async {
      denied = false;
      late BuildContext root;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              root = context;
              return const Scaffold(body: Text('Home'));
            },
          ),
        ),
      );
      final opening = NotificationNavigator.open(
        root,
        const NotificationTarget(
          destination: NotificationDestination.conversation,
          userId: user,
          targetId: targetId,
        ),
        calendar: () {},
        wellbeing: () {},
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChatDetailScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      Navigator.of(root).pop();
      await tester.pumpAndSettle();
      await opening;
      expect(find.text('Home'), findsOneWidget);
    },
  );
  testWidgets(
    'deleted/forbidden target shows clear message without leaving a spinner',
    (tester) async {
      denied = true;
      late BuildContext root;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              root = context;
              return const Scaffold(body: Text('Home'));
            },
          ),
        ),
      );
      final opening = NotificationNavigator.open(
        root,
        const NotificationTarget(
          destination: NotificationDestination.conversation,
          userId: user,
          targetId: targetId,
        ),
        calendar: () {},
        wellbeing: () {},
      );
      await tester.pumpAndSettle();
      await opening;
      expect(find.byType(ChatDetailScreen), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('no longer available'), findsOneWidget);
    },
  );
}
