import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/correction_sheet.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/daily_checkin_sheet.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/start_bleeding_sheet.dart';

import '../support/device_timezone_test_support.dart';
import '../support/secure_storage_test_support.dart';
import 'support/fake_supabase.dart';

/// Logging/sync hardening — what the bleeding write sheets tell her when
/// the save does not complete, driven through a real Supabase client over a
/// scripted HTTP transport:
/// - offline (a transport exception postgrest does not wrap) -> the
///   operation stays queued and the sheet settles on "Saved on device —
///   syncing." — never an escaped exception with a stuck spinner;
/// - a deterministic server rejection (P0001) -> a real error, and the
///   queued copy is dropped (re-sending can never succeed).
typedef _Handler = Future<http.Response> Function(http.Request request);

const _offlineMessage = 'Saved on device — syncing.';
const _rejectedMessage =
    "This couldn't be saved — it conflicts with what's already recorded. "
    'Nothing was changed.';
const _episodeId = '11111111-1111-1111-1111-111111111111';
const _userId = 'aaaaaaaa-0000-0000-0000-000000000001';

const _pluginChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

Future<http.Response> _offline(http.Request request) async =>
    throw http.ClientException('Failed host lookup', request.url);

Future<http.Response> _rejectP0001(http.Request request) async => pgError(
  'P0001',
  'cannot add a new observation to episode — it is not open',
);

_Handler _handler = _offline;
final _cancelledIds = <int>[];

BleedingObservation _target() => BleedingObservation(
  id: '22222222-2222-2222-2222-222222222222',
  userId: _userId,
  episodeId: _episodeId,
  observedDate: DateTime(2026, 10, 9),
  precision: ObservationPrecision.dateOnly,
  flow: ObservationFlow.medium,
  source: ObservationSource.userObserved,
  utcOffsetMinutes: 180,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fake.supabase.local',
      publishableKey: 'anon-key',
      httpClient: MockClient((request) async {
        final r = await _handler(request);
        return http.Response(
          r.body,
          r.statusCode,
          headers: r.headers,
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
      fakeSessionJson(_userId),
    );

    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'cancel':
              _cancelledIds.add(
                (call.arguments as Map<dynamic, dynamic>)['id'] as int,
              );
              return null;
            case 'pendingNotificationRequests':
              return <Object>[];
            default:
              return null;
          }
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (call) async => 'UTC');
    await NotificationService.instance.initialize();
  });

  setUp(() {
    resetSecureLocalStoreForTest();
    mockDeviceTimezoneForTest('Asia/Riyadh');
    AppLocaleController.instance.setArabic(false);
    SecureLocalStore.debugUserIdOverride = _userId;
    _cancelledIds.clear();
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  Future<void> open(
    WidgetTester tester,
    Future<Object?> Function(BuildContext) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => show(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndLetRpcFinish(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  Future<List<PendingBleedingOperation>> queued(WidgetTester tester) async =>
      (await tester.runAsync(
        () => PendingBleedingOperationStore.loadPending(userId: _userId),
      ))!;

  testWidgets('daily check-in YES while offline settles on "Saved on device" '
      'with the operation queued — no escaped exception, no stuck spinner', (
    tester,
  ) async {
    _handler = _offline;
    await open(
      tester,
      (context) => showDailyCheckinSheet(
        context,
        episodeId: _episodeId,
        episodeStartDate: DateTime(2026, 10, 15),
      ),
    );
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    await tapAndLetRpcFinish(tester, 'Save');

    expect(tester.takeException(), isNull);
    expect(find.text(_offlineMessage), findsOneWidget);
    expect(find.text('Save'), findsOneWidget, reason: 'spinner is gone');
    expect(await queued(tester), hasLength(1));
  });

  testWidgets('End sheet while offline: queued, "Saved on device", and the '
      "episode's active-bleeding reminders are still cancelled", (
    tester,
  ) async {
    _handler = _offline;
    await open(
      tester,
      (context) => showEndBleedingSheet(
        context,
        episodeId: _episodeId,
        episodeStartDate: DateTime(2026, 10, 1),
      ),
    );
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await tapAndLetRpcFinish(tester, 'Save');

    expect(tester.takeException(), isNull);
    expect(find.text(_offlineMessage), findsOneWidget);
    expect(await queued(tester), hasLength(1));
    expect(
      _cancelledIds,
      isNotEmpty,
      reason: 'she told us it stopped — reminders must not keep asking',
    );
  });

  testWidgets('backfilling a day the server deterministically rejects (P0001) '
      'shows a real error and drops the queued copy', (tester) async {
    _handler = _rejectP0001;
    await open(
      tester,
      (context) => showBackfillObservationSheet(
        context,
        episodeId: _episodeId,
        episodeStartDate: DateTime(2026, 10, 1),
        initialDate: DateTime(2026, 10, 3),
      ),
    );
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    await tapAndLetRpcFinish(tester, 'Save');

    expect(tester.takeException(), isNull);
    expect(find.text(_offlineMessage), findsNothing);
    expect(find.text(_rejectedMessage), findsOneWidget);
    expect(await queued(tester), isEmpty);
  });

  testWidgets('a rejected correction shows a real error and drops the queued '
      'copy', (tester) async {
    _handler = (request) async => pgError(
      'P0001',
      'the closing observation of an ended episode cannot be corrected to '
          'bleeding (flow heavy)',
    );
    await open(
      tester,
      (context) => showCorrectObservationSheet(context, target: _target()),
    );
    await tester.tap(find.text('Heavy'));
    await tester.pumpAndSettle();
    await tapAndLetRpcFinish(tester, 'Save correction');

    expect(tester.takeException(), isNull);
    expect(find.text(_rejectedMessage), findsOneWidget);
    expect(await queued(tester), isEmpty);
  });

  testWidgets('a correction while offline settles on "Saved on device" with '
      'the operation queued', (tester) async {
    _handler = _offline;
    await open(
      tester,
      (context) => showCorrectObservationSheet(context, target: _target()),
    );
    await tester.tap(find.text('Heavy'));
    await tester.pumpAndSettle();
    await tapAndLetRpcFinish(tester, 'Save correction');

    expect(tester.takeException(), isNull);
    expect(find.text(_offlineMessage), findsOneWidget);
    expect(await queued(tester), hasLength(1));
  });

  group('correction options never contradict the episode boundaries', () {
    final episode = BleedingEpisode(
      id: _episodeId,
      userId: _userId,
      lifecycleStatus: LifecycleStatus.ended,
      startDate: DateTime(2026, 10, 1),
      startPrecision: ObservationPrecision.dateOnly,
      startSource: ObservationSource.userReportedHistorical,
      endDate: DateTime(2026, 10, 6),
      endPrecision: ObservationPrecision.dateOnly,
      endSource: ObservationSource.userReportedHistorical,
    );
    BleedingObservation on(DateTime day, ObservationFlow flow) =>
        BleedingObservation(
          id: 'o',
          userId: _userId,
          episodeId: _episodeId,
          observedDate: day,
          precision: ObservationPrecision.dateOnly,
          flow: flow,
          source: ObservationSource.userReportedHistorical,
          utcOffsetMinutes: 180,
        );

    test('closing observation: only none / not sure', () {
      expect(
        correctionFlowOptions(
          on(DateTime(2026, 10, 6), ObservationFlow.none),
          episode,
        ),
        [ObservationFlow.none, ObservationFlow.uncertain],
      );
    });

    test('start-day observation: never none', () {
      expect(
        correctionFlowOptions(
          on(DateTime(2026, 10, 1), ObservationFlow.heavy),
          episode,
        ),
        isNot(contains(ObservationFlow.none)),
      );
    });

    test('a mid-episode day, or no episode known: every flow', () {
      expect(
        correctionFlowOptions(
          on(DateTime(2026, 10, 3), ObservationFlow.light),
          episode,
        ),
        ObservationFlow.values,
      );
      expect(
        correctionFlowOptions(
          on(DateTime(2026, 10, 6), ObservationFlow.none),
          null,
        ),
        ObservationFlow.values,
      );
    });
  });
}
