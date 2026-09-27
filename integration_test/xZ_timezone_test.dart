import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/core/services/notification_service.dart';
import 'package:niswah/main.dart' as app;

import 'support/flows.dart';
import 'support/flows_ext.dart';
import 'support/harness.dart';

/// PRAY-05 — a device time-zone change while the app is installed, on a REAL
/// Android emulator (driven by scripts/run_android_device_persona.sh, which
/// changes the OS zone and pauses/resumes the app — a Flutter test cannot).
///
/// The account has an open episode and a daily check-in reminder set for the
/// default 6:00 PM. The OS zone is moved to a zone whose CURRENT local date is
/// different from today's, the app is paused and resumed, and:
///  * the app re-reads the zone (NotificationService.activeTimezoneId);
///  * reminder reconciliation leaves the same number of DISTINCT reminders (no
///    duplicates, none lost) and — verified by the host from the OS alarm table —
///    they fire at 6:00 PM LOCAL in the new zone;
///  * a check-in recorded after the change carries the NEW zone/offset while the
///    one recorded before keeps the OLD (history is never rewritten);
///  * "today" follows the device date (the open episode's day count advances).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PRAY-05: time-zone change re-derives reminders and today', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Z')) return;
    if (!h.isAndroid) {
      h.reportResult(
        PersonaResult(
          testId: 'Z',
          expectedOutcome: 'A device time-zone change is handled',
          actualOutcome:
              'Not runnable here: the iOS Simulator follows the host Mac\'s '
              'zone and cannot change it per device; needs a physical iPhone (E4).',
          status: PersonaStatus.blocked,
        ),
      );
      return;
    }
    final f = Flows(h);
    final email = await f.newAccountHanafiStillBleeding('Z');
    h.note('LOOKUP_EMAIL=$email');
    final client = NiswahSupabase.clientOrNull!;
    final uid = client.auth.currentUser!.id;

    Future<String> texts(String label) async {
      await tester.pump(const Duration(seconds: 1));
      h.dumpTexts(label);
      return h.notes.last;
    }

    Future<void> openTab(String label) async {
      await h.scrollToTop();
      await h.tapVisible(find.text(label), last: true);
      await h.settle(2);
    }

    Future<List<Map<String, dynamic>>> observations() async =>
        List<Map<String, dynamic>>.from(
          await client
              .from('bleeding_observations')
              .select()
              .eq('user_id', uid)
              .order('created_at', ascending: true),
        );

    // ---- enable the daily check-in reminder (default 6:00 PM) ----
    await openTab('Profile');
    // Found live, repeatedly: on a slow machine, Profile's row for
    // "Notification settings" can still not exist in the tree right after
    // the tab switch (still populating), even once a Scrollable itself
    // exists and settle() has run. `scrollUntilVisible` requires its
    // target to already exist (it reveals something off-screen, it does
    // not wait for something not yet built) -- calling it before the row
    // exists throws "Bad state: No element" and aborts the whole test
    // binary. Wait for the target text itself, not just any Scrollable.
    final foundSettingsRow = await h.waitFor(
      find.text('Notification settings'),
    );
    h.dumpTexts('Z Profile (foundSettingsRow=$foundSettingsRow)');
    await tester.scrollUntilVisible(
      find.text('Notification settings'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await h.tapVisible(find.text('Notification settings'));
    await h.settle(2);
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -600),
      warnIfMissed: false,
    );
    await h.settle(1);
    final card = find.ancestor(
      of: find.text('Daily check-in reminder'),
      matching: find.byType(Card),
    );
    final sw = find.descendant(of: card, matching: find.byType(Switch));
    if (sw.evaluate().isNotEmpty &&
        !(sw.evaluate().first.widget as Switch).value) {
      await h.tapVisible(sw);
      await h.settle(2);
    }
    // Notification settings is a pushed FULLSCREEN-DIALOG screen (Flutter's
    // AppBar shows a CloseButton, never a BackButton, for those -- see
    // pWalkthrough_six_surface_test.dart's own note on this), not a
    // bottom-nav tab -- the "Today" tab isn't even rendered while it's on
    // top. Pop back to the main shell first (found live: without this,
    // every step below silently ran against whatever Notification settings
    // showed, since its own AppBar title text IS "Notification settings",
    // which made the next openTab('Today') look harmless while doing
    // nothing).
    await h.tapVisible(find.byType(CloseButton));
    await h.settle(2);
    await openTab('Today');
    await tester.pump(const Duration(seconds: 3));

    Future<List<PendingNotificationRequest>> mine() async {
      final all = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      return all.where((p) => (p.payload ?? '').contains(uid)).toList();
    }

    final beforeZone = NotificationService.instance.activeTimezoneId;
    final pendingBefore = await mine();
    final idsBefore = pendingBefore.map((p) => p.id).toSet();
    h.note(
      'Z before: zone=$beforeZone pending=${pendingBefore.length} '
      'distinct=${idsBefore.length}',
    );

    // ---- a check-in recorded BEFORE the change ----
    Future<bool> checkIn(String flowLabel) async {
      await h.scrollToTop();
      final yes = find.text('Yes');
      // Today's "Daily check-in" section, or the missed-day prompt.
      if (find.text('Add it').evaluate().isNotEmpty) {
        await h.tapVisible(find.text('Add it'));
        await h.settle(2);
      }
      if (find.text('Are you still bleeding today?').evaluate().isEmpty &&
          find.text('Daily check-in').evaluate().isNotEmpty) {
        await h.tapVisible(find.text('Daily check-in'), last: true);
        await h.settle(2);
      }
      if (yes.evaluate().isEmpty) return false;
      await h.tapVisible(yes.last);
      await h.settle(2);
      await h.tapVisible(find.text(flowLabel));
      final saved = await h.tapVisible(find.text('Save'), last: true);
      await tester.pump(const Duration(seconds: 4));
      await h.settle(2);
      return saved;
    }

    final obsBefore = await observations();
    final firstOk = await checkIn('Medium');
    final obsMid = await observations();
    final firstRow = obsMid.length > obsBefore.length ? obsMid.last : null;
    h.note(
      'Z first check-in ok=$firstOk tz=${firstRow?['timezone']} '
      'offset=${firstRow?['utc_offset_minutes']}',
    );

    // ---- pick a zone whose CURRENT local date differs from the current one ----
    final utc = DateTime.now().toUtc();
    final localDate = DateTime.now();
    String pick() {
      for (final z in const [
        ('Pacific/Kiritimati', 14),
        ('Pacific/Pago_Pago', -11),
      ]) {
        final t = utc.add(Duration(hours: z.$2));
        if (t.day != localDate.day) return z.$1;
      }
      return 'Pacific/Kiritimati';
    }

    final zone = pick();
    final offsetHours = zone == 'Pacific/Kiritimati' ? 14 : -11;
    h.note(
      'Z will move the device to $zone (UTC${offsetHours >= 0 ? '+' : ''}$offsetHours)',
    );
    final dayBefore = (await texts('Z Today before')).contains('Day 4');

    h.note('HOST SET TIMEZONE $zone');
    await tester.pump(const Duration(seconds: 6));
    h.note('HOST CYCLE APP');
    // The host presses HOME then relaunches; wait for the app to come back.
    await tester.pump(const Duration(seconds: 25));
    await tester.pump(const Duration(seconds: 5));

    final afterZone = NotificationService.instance.activeTimezoneId;
    final pendingAfter = await mine();
    final idsAfter = pendingAfter.map((p) => p.id).toSet();
    final noDuplicates = pendingAfter.length == idsAfter.length;
    final sameCount = idsAfter.length == idsBefore.length;
    h.note(
      'Z after: zone=$afterZone pending=${pendingAfter.length} '
      'distinct=${idsAfter.length} sameCount=$sameCount',
    );
    h.note('HOST VERIFY ALARMS $zone 18:00');
    await tester.pump(const Duration(seconds: 6));

    // ---- Today follows the device date; a new check-in carries the new zone ----
    final todayAfter = await texts('Z Today after zone change');
    final dayAdvanced =
        todayAfter.contains('Day 5') || todayAfter.contains('Day 4');
    final secondOk = await checkIn('Light');
    final obsEnd = await observations();
    final secondRow = obsEnd.length > obsMid.length ? obsEnd.last : null;
    final firstRowAfter = obsEnd
        .where((r) => r['id'] == firstRow?['id'])
        .firstOrNull;
    h.note(
      'Z second check-in ok=$secondOk tz=${secondRow?['timezone']} '
      'offset=${secondRow?['utc_offset_minutes']} first row now '
      'tz=${firstRowAfter?['timezone']} offset=${firstRowAfter?['utc_offset_minutes']}',
    );

    final crashed = tester.takeException() != null;
    final expectedOffset = offsetHours * 60;
    final pass =
        !crashed &&
        beforeZone == 'Asia/Riyadh' &&
        afterZone == zone &&
        pendingBefore.isNotEmpty &&
        noDuplicates &&
        sameCount &&
        firstOk &&
        firstRow?['timezone'] == 'Asia/Riyadh' &&
        firstRow?['utc_offset_minutes'] == 180 &&
        secondOk &&
        secondRow?['timezone'] == zone &&
        secondRow?['utc_offset_minutes'] == expectedOffset &&
        firstRowAfter?['timezone'] == 'Asia/Riyadh' &&
        firstRowAfter?['utc_offset_minutes'] == 180 &&
        dayBefore &&
        dayAdvanced;
    h.reportResult(
      PersonaResult(
        testId: 'Z',
        expectedOutcome:
            'After a real device time-zone change and an app pause/resume the '
            'app re-reads the zone, keeps the same distinct reminders (the host '
            'confirms they fire at 6:00 PM local in the new zone), stamps new '
            'check-ins with the new zone/offset and leaves the earlier one '
            'unchanged',
        actualOutcome:
            'crashed=$crashed zone $beforeZone->$afterZone pending '
            '${idsBefore.length}->${idsAfter.length} dupFree=$noDuplicates '
            'firstRow=${firstRow?['timezone']}/${firstRow?['utc_offset_minutes']} '
            'secondRow=${secondRow?['timezone']}/${secondRow?['utc_offset_minutes']} '
            'firstRowUnchanged=${firstRowAfter?['timezone']} '
            'dayAdvanced=$dayAdvanced',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'Z_Today.png',
      ),
    );
  });
}
