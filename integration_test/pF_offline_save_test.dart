import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Persona F — offline save, pending state, reconnection, replay. ONE
/// continuous app session against a REAL backend outage orchestrated
/// host-side by `scripts/run_persona_f_offline.sh` (it stops/restarts the
/// local Supabase backend on this test's two marker lines — never a
/// mocked/injected offline flag).
///
/// Sequence asserted: offline save -> pending state visible (UI copy AND
/// the on-device pending store) -> connectivity restored -> the app's real
/// resume trigger (`main.dart`'s `didChangeAppLifecycleState(resumed)` ->
/// `reconcilePendingOperations()`) -> pending operation cleared -> exactly
/// ONE persisted canonical episode and observation (idempotent replay, no
/// duplicate) -> UI reflects the synced state.
///
/// ROOT CAUSE of the earlier "reconnect hangs" blocker (it was this
/// harness, not the app): `AppLifecycleState.hidden`/`paused` set
/// `SchedulerBinding.framesEnabled = false` and `scheduleFrame()` then
/// returns early (flutter/lib/src/scheduler/binding.dart), so an
/// `await tester.pump()` placed BETWEEN the paused and resumed
/// transitions waits for a frame that can never be produced — a silent,
/// permanent hang. The lifecycle chain therefore has to be dispatched
/// back-to-back with no frame await until `resumed` re-enables frames.
/// (An earlier direct resumed->paused jump also tripped
/// `AppLifecycleListener`'s legal-transition assertion; the real chain is
/// resumed->inactive->hidden->paused->hidden->inactive->resumed.)
///
/// A cross-`flutter drive`-invocation design (relaunch the process while
/// offline) is not used: a relaunched `flutter drive` process starts with
/// its app data cleared (the language preference and Supabase session are
/// gone, so the sign-up screen returns), so session persistence across
/// invocations cannot be relied on here.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const expected =
      'Starting a period during a real backend outage shows an honest '
      '"saved on device, syncing" pending state (never a crash or raw '
      'exception); on reconnect the pending operation is replayed into '
      'exactly one canonical episode, the pending record clears, and '
      'the UI reflects the synced state';

  testWidgets('Persona F: offline save, pending state, reconnection replay, no '
      'duplicate', (tester) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('F')) return;
    final f = Flows(h);
    final email = await f.newAccountOnDashboard('F');
    h.note('LOOKUP_EMAIL=$email');
    await h.shot('F', 'dashboard_backend_up');

    // ---- 1. real outage: host stops the backend on this marker ----
    h.note('F READY FOR OUTAGE');
    await tester.pump(const Duration(seconds: 6));
    await h.settle(2);

    final openedStart = await h.tapVisible(find.text('Period Started'));
    h.note('F opened Period Started sheet: $openedStart');
    await h.settle(2);
    if (!openedStart) {
      h.reportResult(
        PersonaResult(
          testId: 'F',
          expectedOutcome: expected,
          actualOutcome: 'Could not open the Period Started sheet',
          status: PersonaStatus.blocked,
        ),
      );
      return;
    }
    await h.tapVisible(find.text('Today'), last: true);
    await h.tapVisible(find.text('Medium'));
    final tappedSave = await h.tapVisible(find.text('Save'));
    h.note('F tapped Save (backend down): $tappedSave');
    await tester.pump(const Duration(seconds: 10));
    await h.settle(3);
    await h.shot('F', 'after_save_attempt_offline');
    h.dumpTexts('F after Save attempt (backend down)');
    final offlineTexts = h.notes.last;

    // ---- 2. pending state visible: UI copy AND on-device store ----
    final crashedOffline = tester.takeException() != null;
    final showsHonestPending =
        offlineTexts.contains('Saved on device') ||
        offlineTexts.contains('تم الحفظ على الجهاز');
    final showsRawException =
        offlineTexts.contains('SocketException') ||
        offlineTexts.contains('Connection refused') ||
        offlineTexts.contains('ClientException');
    final pendingWhileOffline =
        (await PendingBleedingOperationStore.loadPending()).length;
    h.note(
      'F offline: crashed=$crashedOffline honestPending='
      '$showsHonestPending rawException=$showsRawException '
      'pendingOps=$pendingWhileOffline',
    );

    // ---- 3. restore connectivity: host restarts the backend ----
    h.note('F READY FOR RECONNECT');
    final authHealth = Uri.parse(
      '${dotenv.env['SUPABASE_URL']}/auth/v1/health',
    );
    var backendBack = false;
    for (var i = 0; i < 90 && !backendBack; i++) {
      await tester.pump(const Duration(seconds: 1));
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        final response = await (await client.getUrl(authHealth)).close();
        await response.drain<void>();
        client.close(force: true);
        backendBack = response.statusCode == 200;
      } catch (_) {
        backendBack = false;
      }
    }
    h.note('F backend reachable again: $backendBack');

    // ---- 4. the app's real resume trigger -> reconcile ----
    // Dispatched back-to-back: NO frame await between `hidden`/`paused`
    // and `resumed` (frames are disabled in between; see class doc).
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
    h.note('F resume chain dispatched (real reconcile trigger)');

    // ---- 5. pending cleared ----
    var pendingAfter = pendingWhileOffline;
    for (var i = 0; i < 40 && pendingAfter > 0; i++) {
      await tester.pump(const Duration(seconds: 1));
      pendingAfter = (await PendingBleedingOperationStore.loadPending()).length;
    }
    h.note('F pending ops after reconnect: $pendingAfter');

    // ---- 6. exactly one canonical record, no duplicate ----
    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    var episodeCount = -1;
    var observationCount = -1;
    if (userId != null) {
      final repo = BleedingEpisodeRepositoryImpl();
      final episodes = (await repo.getEpisodesForUser(userId)).dataOrNull;
      episodeCount = episodes?.length ?? -1;
      if (episodes != null && episodes.length == 1) {
        observationCount =
            (await repo.getObservationsForEpisode(episodes.first.id!))
                .dataOrNull
                ?.length ??
            -1;
      }
    }
    h.note(
      'F canonical: episodes=$episodeCount observations='
      '$observationCount',
    );

    // ---- 7. UI reflects the synced state (as a real user would: close
    // the stale sheet, look at Today) ----
    await tester.pump(const Duration(seconds: 2));
    await h.shot('F', 'after_reconnect_sheet');
    h.dumpTexts('F after reconnect (sheet may still be open)');
    final sheetStillShowsPending = h.notes.last.contains('Saved on device');
    // Tap the scrim above the bottom sheet to dismiss it.
    await tester.tapAt(const Offset(195, 60));
    await tester.pump(const Duration(seconds: 2));
    await h.settle(2);
    await h.scrollToTop();
    await h.settle(1);
    await h.shot('F', 'after_reconnect_today');
    h.dumpTexts('F Today after reconnect');
    var todayTexts = h.notes.last;
    var showsSyncedEpisode =
        todayTexts.contains('Bleeding recorded') ||
        todayTexts.contains('Day 1 of this record');
    var neededManualRefresh = false;
    if (!showsSyncedEpisode) {
      // A real user switches tabs / pulls to refresh.
      neededManualRefresh = true;
      await h.tapVisible(find.text('Calendar'));
      await h.settle(2);
      await h.tapVisible(find.text('Today'), last: true);
      await h.settle(3);
      h.dumpTexts('F Today after tab round trip');
      todayTexts = h.notes.last;
      showsSyncedEpisode =
          todayTexts.contains('Bleeding recorded') ||
          todayTexts.contains('Day 1 of this record');
    }
    // The replayed episode must never leave the prayer card claiming
    // "Salah is obligatory" for a woman who is bleeding.
    final claimsObligatory = todayTexts.contains('Salah is obligatory');
    h.note(
      'F UI: syncedEpisodeShown=$showsSyncedEpisode '
      'claimsObligatory=$claimsObligatory '
      'neededManualRefresh=$neededManualRefresh '
      'sheetStillShowedPendingAfterSync=$sheetStillShowsPending',
    );

    final crashed = tester.takeException() != null;
    final pass =
        !crashedOffline &&
        !crashed &&
        showsHonestPending &&
        !showsRawException &&
        pendingWhileOffline == 1 &&
        backendBack &&
        pendingAfter == 0 &&
        episodeCount == 1 &&
        observationCount == 1 &&
        showsSyncedEpisode &&
        !claimsObligatory &&
        !neededManualRefresh;
    h.note(
      pass
          ? 'F RESULT: PASS — offline save shown honestly and queued '
                '(1 pending op), then replayed on reconnect into exactly '
                'one episode/one observation, pending cleared, UI synced'
          : 'F RESULT: FAIL — see F offline/canonical/UI lines above',
    );
    h.reportResult(
      PersonaResult(
        testId: 'F',
        expectedOutcome: expected,
        actualOutcome:
            'offline: crashed=$crashedOffline honestPending='
            '$showsHonestPending rawException=$showsRawException '
            'pendingOps=$pendingWhileOffline | reconnect: '
            'backendBack=$backendBack pendingAfter=$pendingAfter '
            'episodes=$episodeCount observations=$observationCount | UI: '
            'syncedEpisodeShown=$showsSyncedEpisode '
            'neededManualRefresh=$neededManualRefresh '
            'crashed=$crashed',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'F_after_reconnect_today.png',
      ),
    );
  });
}
