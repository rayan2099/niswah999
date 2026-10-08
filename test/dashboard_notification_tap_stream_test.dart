import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import 'support/parity_test_harness.dart';

const _pluginChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

class _FakeCanonicalRepository extends BleedingEpisodeRepositoryImpl {
  _FakeCanonicalRepository() : super(client: null);

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async => const LoadSuccess([]);

  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String userId,
  ) async => const LoadSuccess([]);
}

/// F5(D) — "notification tap stream while dashboard already mounted."
///
/// Closure Blocker 9's live subscription
/// (`NotificationService.instance.onTap`) exists specifically so a tap
/// that happens *while the dashboard is already showing* is not missed
/// the way a one-shot `initState` check would miss it. This is the one
/// slice of `_consumeNotificationTap` a plain widget test can honestly
/// exercise: firing a real tap event through the plugin's own native-
/// to-Dart callback path (simulated via the mocked plugin channel,
/// mirroring `notification_multi_day_continuity_test.dart`'s own
/// established technique) and observing that the dashboard's live
/// subscription actually consumes it — for every payload shape it must
/// not crash on, well-formed or otherwise.
///
/// What this file does NOT (and, per this codebase's own established
/// scope boundary — see `correction_sheet_test.dart`'s identical note —
/// cannot) cover: the full account-isolation + episode-lookup + daily-
/// check-in-sheet round trip, which requires a real signed-in Supabase
/// session this test environment does not have. `signedInUserId` is
/// always null here, so every tap this test fires is correctly (and
/// safely) dropped by `_consumeNotificationTap`'s own "wrong user, or
/// logged out entirely" guard — proving robustness, not the full happy
/// path.
void main() {
  Future<void> simulateNotificationTap(String payload) async {
    const codec = StandardMethodCodec();
    final call = MethodCall('didReceiveNotificationResponse', {
      'notificationId': 1,
      'actionId': null,
      'input': null,
      'payload': payload,
      'notificationResponseType': 0,
    });
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _pluginChannel.name,
          codec.encodeMethodCall(call),
          (_) {},
        );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'createNotificationChannel':
            case 'getNotificationAppLaunchDetails':
              return null;
            case 'zonedSchedule':
            case 'cancel':
              return null;
            case 'areNotificationsEnabled':
              return true;
            default:
              return null;
          }
        });
    await NotificationService.instance.initialize();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, null);
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      homeOverride: DashboardScreen(
        canonicalRepositoryOverride: _FakeCanonicalRepository(),
        canonicalUserIdOverride: 'user-1',
      ),
    );
  }

  testWidgets(
    'a tap fired while the dashboard is already mounted is picked up by '
    'the live subscription (consumed from the pending-payload slot), not '
    'silently missed',
    (tester) async {
      await pumpDashboard(tester);

      final payload = jsonEncode({
        'type': 'activeBleedingCheckin',
        'userId': 'user-1',
        'episodeId': 'episode-1',
        'localDate': '2026-08-18',
      });
      await simulateNotificationTap(payload);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        NotificationService.instance.consumePendingTapPayload(),
        isNull,
        reason:
            'the live onTap subscription must have already drained the '
            'pending payload — nothing left for a later, redundant check '
            'to pick up',
      );
    },
  );

  testWidgets(
    'a malformed (non-JSON) payload tapped while mounted never crashes '
    'the dashboard',
    (tester) async {
      await pumpDashboard(tester);

      await simulateNotificationTap('not valid json {{{');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a foreign/unrelated notification type tapped while mounted is '
      'silently ignored, never crashes', (tester) async {
    await pumpDashboard(tester);

    final payload = jsonEncode({'type': 'someOtherFeatureEntirely'});
    await simulateNotificationTap(payload);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a wrong-typed (non-string) userId field never crashes the dashboard '
    '— a payload can be syntactically valid JSON while still carrying a '
    'field of the wrong type (corruption, or schema drift from an old '
    'notification still sitting in the shade)',
    (tester) async {
      await pumpDashboard(tester);

      final payload = jsonEncode({
        'type': 'activeBleedingCheckin',
        'userId': 12345,
        'episodeId': 'episode-1',
        'localDate': '2026-08-18',
      });
      await simulateNotificationTap(payload);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('multiple taps fired in quick succession while mounted are each '
      'handled independently, never crash or leave the subscription stuck', (
    tester,
  ) async {
    await pumpDashboard(tester);

    for (var i = 0; i < 3; i++) {
      await simulateNotificationTap(
        jsonEncode({
          'type': 'activeBleedingCheckin',
          'userId': 'user-1',
          'episodeId': 'episode-$i',
          'localDate': '2026-08-18',
        }),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // Commit H — adversarial review follow-up (2026-10-08). Point 3: every
  // field read from the payload must be independently proven type-safe,
  // not just the one field the original fix touched.
  group('payload field-safety matrix (missing fields, old/foreign shapes, '
      'duplicate delivery)', () {
    testWidgets('a payload missing userId entirely (not merely wrong-typed) '
        'never crashes — treated identically to a wrong-typed one', (
      tester,
    ) async {
      await pumpDashboard(tester);
      await simulateNotificationTap(
        jsonEncode({
          'type': 'activeBleedingCheckin',
          'episodeId': 'episode-1',
          'localDate': '2026-08-18',
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a payload missing episodeId entirely never crashes', (
      tester,
    ) async {
      await pumpDashboard(tester);
      await simulateNotificationTap(
        jsonEncode({
          'type': 'activeBleedingCheckin',
          'userId': 'user-1',
          'localDate': '2026-08-18',
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a payload missing localDate entirely never crashes', (
      tester,
    ) async {
      await pumpDashboard(tester);
      await simulateNotificationTap(
        jsonEncode({
          'type': 'activeBleedingCheckin',
          'userId': 'user-1',
          'episodeId': 'episode-1',
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong-typed episodeId (not a string) never crashes', (
      tester,
    ) async {
      await pumpDashboard(tester);
      await simulateNotificationTap(
        jsonEncode({
          'type': 'activeBleedingCheckin',
          'userId': 'user-1',
          'episodeId': 42,
          'localDate': '2026-08-18',
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong-typed localDate (not a string) never crashes', (
      tester,
    ) async {
      await pumpDashboard(tester);
      await simulateNotificationTap(
        jsonEncode({
          'type': 'activeBleedingCheckin',
          'userId': 'user-1',
          'episodeId': 'episode-1',
          'localDate': 20260818,
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'an unknown/future payload version — the known fields present but '
      'wrapped with extra, never-seen fields a future schema might add — '
      'is handled exactly like today\'s shape, extra fields simply '
      'ignored',
      (tester) async {
        await pumpDashboard(tester);
        await simulateNotificationTap(
          jsonEncode({
            'type': 'activeBleedingCheckin',
            'userId': 'user-1',
            'episodeId': 'episode-1',
            'localDate': '2026-08-18',
            'schemaVersion': 2,
            'futureField': {'nested': true},
          }),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the top-level JSON is syntactically valid but not an object at all '
      '(a bare list) — the existing malformed-JSON guard covers this too, '
      'not only invalid syntax',
      (tester) async {
        await pumpDashboard(tester);
        await simulateNotificationTap(jsonEncode([1, 2, 3]));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the identical payload delivered twice in a row (duplicate tap '
        'redelivery) is handled both times without crashing — each '
        'delivery is independently validated from scratch', (tester) async {
      await pumpDashboard(tester);
      final payload = jsonEncode({
        'type': 'activeBleedingCheckin',
        'userId': 'user-1',
        'episodeId': 'episode-1',
        'localDate': '2026-08-18',
      });
      await simulateNotificationTap(payload);
      await tester.pump();
      await simulateNotificationTap(payload);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
