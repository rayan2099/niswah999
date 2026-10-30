// Onboarding/server hardening regressions for
// lib/features/onboarding/presentation/screens/onboarding_screen.dart.
//
// Unlike the existing onboarding widget tests (which have no Supabase
// session, so _completeOnboarding never reaches the RPC), this file
// initializes the real Supabase singleton over a scripted HTTP transport
// with a signed-in synthetic user, so the exact
// `record_onboarding_menstrual_history` request body — and the pending
// operation queue — can be asserted. No network, no real project.
//
// Every test asserts the CORRECT behavior; a failure documents a finding.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging_sync_hardening/support/fake_supabase.dart'
    show fakeSessionJson, jsonResponse;
import '../support/secure_storage_test_support.dart';

const _userId = 'aaaaaaaa-0000-4000-8000-00000000000a';

/// Every `record_onboarding_menstrual_history` body the screen sent.
final List<Map<String, dynamic>> rpcBodies = [];

/// Scripted server for the onboarding RPC. Default: success.
Future<http.Response> Function(Map<String, dynamic> body) onOnboardingRpc = _ok;

Future<http.Response> _ok(Map<String, dynamic> body) async => jsonResponse([
  {
    'episode_id': body['p_start_date'] == null
        ? null
        : '11111111-1111-4111-8111-111111111111',
    'baseline_id': null,
    'episode_conflict': false,
    'conflicting_episode_id': null,
    'conflicting_start_date': null,
  },
]);

Future<http.Response> _route(http.Request request) async {
  final path = request.url.path;
  if (path == '/rest/v1/rpc/record_onboarding_menstrual_history') {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    rpcBodies.add(body);
    return onOnboardingRpc(body);
  }
  // users update (markOnboardingCompleted), profile reads, etc.
  return jsonResponse([]);
}

Future<void> _pumpAt(WidgetTester tester, int step) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OnboardingScreen(onFinished: () {}, initialStep: step),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Opens the date picker from the current Last-Period sub-step and picks
/// [day] of the month shown (the current month).
Future<void> _pickDay(WidgetTester tester, int day) async {
  await _tap(tester, find.byIcon(Icons.calendar_month_rounded));
  await tester.tap(find.text('$day').last);
  await tester.pumpAndSettle();
  await _tap(tester, find.text('OK'));
}

/// Privacy -> Welcome -> "Start tracking", with a few bounded pumps (the
/// busy indicator never settles).
Future<void> _finishFromPredictionsGate(WidgetTester tester) async {
  await _tap(tester, find.text('Skip for now'));
  await _tap(tester, find.text('Continue'));
  await tester.ensureVisible(find.text('Start tracking'));
  await tester.tap(find.text('Start tracking'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fake.supabase.local',
      publishableKey: 'anon-key',
      httpClient: MockClient((request) async {
        final r = await _route(request);
        // postgrest reads response.request when parsing.
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
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = _userId;
    AppLocaleController.instance.setArabic(false);
    rpcBodies.clear();
    onOnboardingRpc = _ok;
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  testWidgets(
    'R2-ONB-1: a last-period answer she withdrew after a failed save is never '
    'replayed later by background sync',
    (tester) async {
      final today = DateTime.now();
      // First attempt fails in transit (offline / timeout).
      onOnboardingRpc = (_) async =>
          throw http.ClientException('Failed host lookup');
      await _pumpAt(tester, 5);
      await _pickDay(tester, today.day);
      await _tap(tester, find.text('Continue'));
      await _tap(tester, find.text('Yes, still going'));
      await _finishFromPredictionsGate(tester);
      expect(rpcBodies, hasLength(1));
      expect(find.text('Go back and review your answers'), findsOneWidget);

      // She reviews and decides she is not sure after all, then finishes.
      onOnboardingRpc = _ok;
      await _tap(tester, find.text('Go back and review your answers'));
      await _tap(tester, find.text('I’m not sure'));
      await _finishFromPredictionsGate(tester);
      expect(rpcBodies, hasLength(1), reason: 'nothing left to save');

      // App resume: reconcilePendingOperations (main.dart) runs.
      await tester.runAsync(
        () => BleedingEpisodeRepositoryImpl().reconcilePendingOperations(),
      );
      expect(
        rpcBodies.length,
        1,
        reason:
            'background sync replayed the withdrawn "period started '
            '${rpcBodies.last['p_start_date']}, still going" answer and '
            'created an episode she explicitly took back',
      );
    },
  );

  testWidgets(
    'R2-ONB-2: after a failed save, a CHANGED answer is sent as a new '
    'submission, not under the old operation id (whose first attempt may '
    'already have committed)',
    (tester) async {
      final today = DateTime.now();
      if (today.day < 3) return; // needs two distinct past days this month
      // Commit-then-lost-response: the server saved it, the app never knew.
      onOnboardingRpc = (_) async => throw http.ClientException('timeout');
      await _pumpAt(tester, 5);
      await _pickDay(tester, today.day);
      await _tap(tester, find.text('Continue'));
      await _tap(tester, find.text('Yes, still going'));
      await _finishFromPredictionsGate(tester);

      onOnboardingRpc = _ok;
      await _tap(tester, find.text('Go back and review your answers'));
      await _pickDay(tester, 1);
      await _tap(tester, find.text('Continue'));
      await _tap(tester, find.text('Yes, still going'));
      await _finishFromPredictionsGate(tester);

      expect(rpcBodies, hasLength(2));
      expect(rpcBodies[1]['p_start_date'], isNot(rpcBodies[0]['p_start_date']));
      expect(
        rpcBodies[1]['p_client_operation_id'],
        isNot(rpcBodies[0]['p_client_operation_id']),
        reason:
            'same id + different answer: record_onboarding_menstrual_history '
            'returns the FIRST attempt\'s episode, so her corrected date is '
            'silently dropped while the screen reports success',
      );
    },
  );

  testWidgets(
    'R2-ONB-3 / PT-002: "No, it has stopped" + "not sure exactly when" '
    'saves the known start as an ended period with an unknown end',
    (tester) async {
      await _pumpAt(tester, 5);
      await _pickDay(tester, 1);
      await _tap(tester, find.text('Continue'));
      await _tap(tester, find.text('No, it has stopped'));
      await _tap(tester, find.text('I’m not sure exactly when'));
      await _finishFromPredictionsGate(tester);

      // PT-002: an ended episode with the start she knows and an unknown
      // end; no end date is invented.
      final openEpisodes = rpcBodies
          .where((b) => b['p_lifecycle_status'] == 'open')
          .toList();
      expect(
        openEpisodes,
        isEmpty,
        reason:
            'she said bleeding has stopped, yet an open ("may still be '
            'bleeding") episode was sent: $openEpisodes',
      );
      final sent = rpcBodies.single;
      final now = DateTime.now();
      expect(
        sent['p_start_date'],
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-01',
        reason: 'PT-002: the start she picked must be saved',
      );
      expect(sent['p_lifecycle_status'], 'ended');
      expect(sent['p_end_precision'], 'unknown');
      expect(sent.containsKey('p_end_date'), isFalse);
      expect(sent.containsKey('p_continuation_certainty'), isFalse);
    },
  );

  testWidgets(
    'R2-ONB-4: changing the start date to after a previously chosen end date '
    'clears that end date (Continue must not submit end < start)',
    (tester) async {
      final today = DateTime.now();
      if (today.day < 5) return;
      await _pumpAt(tester, 5);
      await _pickDay(tester, 1);
      await _tap(tester, find.text('Continue'));
      await _tap(tester, find.text('No, it has stopped'));
      await _pickDay(tester, 3);
      await _tap(tester, find.text('Continue'));
      expect(
        find.text(
          'Would you like to add some information to improve predictions?',
        ),
        findsOneWidget,
      );

      // Back to Last Period, then back through its own sub-steps.
      await _tap(tester, find.byTooltip('Back'));
      await _tap(tester, find.text('Back')); // pickEnd -> stillHappening
      await _tap(tester, find.text('Back')); // stillHappening -> pickStart
      await _pickDay(tester, today.day);
      await _tap(tester, find.text('Continue'));
      await _tap(tester, find.text('No, it has stopped'));

      final continueButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(
        continueButton.onPressed,
        isNull,
        reason:
            'the stale end date (day 3) precedes the new start (day '
            '${today.day}) yet is still selected and submittable — the RPC '
            'then rejects the whole onboarding save with "end_date precedes '
            'start_date"',
      );
    },
  );

  testWidgets(
    'R2-ONB-5: entering estimates and then choosing "Skip for now" does not '
    'save those estimates',
    (tester) async {
      await _pumpAt(tester, 6);
      await _tap(tester, find.text('Yes, help me improve predictions'));
      await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -84));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Continue')); // duration -> cycle length
      await _tap(tester, find.byTooltip('Back')); // cycle length -> duration
      await _tap(tester, find.byTooltip('Back')); // duration -> gate
      await _finishFromPredictionsGate(tester); // taps "Skip for now"

      expect(
        rpcBodies,
        isEmpty,
        reason:
            'she skipped the predictions questions, but the duration she '
            'had scrolled to was still sent: ${rpcBodies.firstOrNull}',
      );
    },
  );

  testWidgets(
    'R2-ONB-7: a usual bleeding duration that is not shorter than the cycle '
    'length cannot be confirmed',
    (tester) async {
      await _pumpAt(tester, 6);
      await _tap(tester, find.text('Yes, help me improve predictions'));
      // Duration wheel starts at its midpoint (10); move to 12.
      await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -84));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Continue'));
      // Cycle wheel starts at 45; fling it down to the low single digits.
      for (var i = 0; i < 4; i++) {
        await tester.drag(
          find.byType(ListWheelScrollView),
          const Offset(0, 600),
        );
        await tester.pumpAndSettle();
      }
      final continueButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(
        continueButton.onPressed,
        isNull,
        reason: 'a 12-day bleed in a cycle of a few days must not be accepted',
      );
    },
  );

  testWidgets('R2-ONB-6: a first-time user is not pre-answered "Not married"', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await MaritalStatusController.instance.load();
    await _pumpAt(tester, 3);
    expect(find.text('Are you married?'), findsOneWidget);
    final continueButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(
      continueButton.onPressed,
      isNull,
      reason:
          'MaritalStatusController.isMarried defaults to false, so "No" is '
          'pre-selected and Continue is enabled before she answers',
    );
  });
}
