import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/harness.dart';

/// Persona F — offline save / pending state, live against a REAL backend
/// outage (see `scripts/run_persona_f_offline.sh`, which stops/restarts
/// the local Supabase backend host-side around this test's own "F READY
/// FOR OUTAGE" marker — never a mocked/injected offline flag).
///
/// Scope, disclosed honestly: this proves the SAVE half of "offline
/// save, pending state, reconnection" — `start_bleeding_sheet.dart`'s
/// `savePending()` commits before the RPC is attempted, so a real
/// network failure here must surface the sheet's own honest "Saved on
/// device — syncing." copy, never a crash or a raw exception.
///
/// The RECONNECTION half (does `main.dart`'s automatic
/// `reconcilePendingOperations()` actually replay this into a real
/// synced episode) was attempted live this same session and is NOT
/// included here — disclosed as a genuine test-infrastructure blocker,
/// not swept under this test's own PASS:
///   - A cross-`flutter drive`-invocation design (sign up while the
///     backend is up, relaunch while it's down, restart it, relaunch
///     again) was tried first and disproved: a relaunched process shows
///     the sign-up screen again regardless of backend state, so the
///     simulator's Keychain session does not reliably persist across
///     separate `flutter drive` invocations here.
///   - A single-continuous-session redesign using
///     `binding.handleAppLifecycleStateChanged` to simulate a real
///     app pause/resume (the actual trigger `main.dart` listens for)
///     was tried next. `AppLifecycleListener`'s own state machine
///     rejected a direct resumed->paused jump (fixed: the full
///     resumed->inactive->hidden->paused->hidden->inactive->resumed
///     chain a real backgrounding sends). With that fixed, the test
///     still hung for 180s+ with zero further output immediately after
///     the transition, cause undetermined without VM-service-level
///     debugging (not safe to leave in the automated suite: a hang
///     here would stall the whole acceptance CI job, which has no
///     per-test bounded-kill mechanism the way the local orchestration
///     script does).
/// `reconcilePendingOperations()` itself is a real, existing code path
/// (confirmed by reading `main.dart`/`bleeding_episode_repository_impl.
/// dart`), so this is a test-harness gap, not a claim that reconnection
/// itself is broken — a follow-up session should attach DevTools/
/// Observatory to root-cause the hang rather than guess blind from logs.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persona F: starting a period during a real backend outage shows '
      'an honest pending state, never a crash, never a raw exception', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    // Production kill switch — before ANY sign-up, fixture or action.
    if (!await h.guardBackend('F')) return;
    final f = Flows(h);
    final email = await f.newAccountOnDashboard('F');
    h.note('F EMAIL $email');
    await h.shot('F', 'dashboard_backend_up');

    // Marker: host stops the backend now.
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
          expectedOutcome:
              'Starting a period during a real backend outage shows '
              'an honest pending state, never a crash or raw '
              'exception',
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
    // A real connection attempt against a stopped backend takes
    // longer than a normal round trip (TCP refusal/timeout) —
    // settle generously.
    await tester.pump(const Duration(seconds: 10));
    await h.settle(3);
    await h.shot('F', 'after_save_attempt_offline');
    h.dumpTexts('F after Save attempt (backend down)');
    final offlineTexts = h.notes.last;

    final crashed = tester.takeException() != null;
    final showsHonestPending =
        offlineTexts.contains('Saved on device') ||
        offlineTexts.contains('تم الحفظ على الجهاز');
    final showsRawException =
        offlineTexts.contains('SocketException') ||
        offlineTexts.contains('Connection refused') ||
        offlineTexts.contains('ClientException');
    final pass = !crashed && showsHonestPending && !showsRawException;
    h.note(
      'F crashed=$crashed showsHonestPending=$showsHonestPending '
      'showsRawException=$showsRawException',
    );
    h.note(
      pass
          ? 'F RESULT: PASS — a real backend outage produced an '
                'honest "saved on device, syncing" pending state, '
                'never a crash, never a raw exception. Reconnection '
                'replay NOT verified live this run — see this '
                'file\'s own doc comment for the disclosed blocker.'
          : 'F RESULT: FAIL — crashed=$crashed showsHonestPending='
                '$showsHonestPending showsRawException='
                '$showsRawException',
    );

    // Marker: host restarts the backend now (state hygiene for
    // whatever runs next — this test itself does not verify
    // reconnection; see the doc comment above).
    h.note('F READY FOR RECONNECT');

    h.reportResult(
      PersonaResult(
        testId: 'F',
        expectedOutcome:
            'Starting a period during a real backend outage shows an '
            'honest "saved on device, syncing" pending state, never '
            'a crash or raw exception',
        actualOutcome:
            'crashed=$crashed showsHonestPending=$showsHonestPending '
            'showsRawException=$showsRawException',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'F_after_save_attempt_offline.png',
      ),
    );
  });
}
