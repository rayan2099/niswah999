import 'dart:convert';

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

/// REM-03 — a REAL notification, tapped on a REAL emulator, routes correctly.
/// Android emulator only, driven by scripts/run_android_device_persona.sh
/// (which taps the notification in the system shade; a Flutter test cannot).
///
///  1. A woman with an open episode and no check-in today enables the daily
///     check-in reminder in Notification settings and sets it for a few
///     minutes from now. The OS posts the notification.
///  2. Tapping it opens the daily check-in sheet ("Are you still bleeding
///     today?") for the right episode; answering saves a real observation.
///  3. A second notification carrying ANOTHER account's payload is tapped:
///     the app must open nothing (never expose someone else's journey).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('REM-03: notification tap routing on the emulator', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('N')) return;
    if (!h.isAndroid) {
      h.reportResult(
        PersonaResult(
          testId: 'N',
          expectedOutcome: 'A real notification tap routes correctly',
          actualOutcome:
              'Not runnable here: a Flutter test cannot press an iOS local '
              'notification; iOS tap routing needs a physical device (E4).',
          status: PersonaStatus.blocked,
        ),
      );
      return;
    }
    final f = Flows(h);
    final email = await f.newAccountHanafiStillBleeding('N');
    h.note('LOOKUP_EMAIL=$email');
    final client = NiswahSupabase.clientOrNull!;
    final uid = client.auth.currentUser!.id;

    Future<int> observationCount() async => (await client
            .from('bleeding_observations')
            .select('id')
            .eq('user_id', uid))
        .length;
    final obsBefore = await observationCount();

    Future<void> openTab(String label) async {
      await h.scrollToTop();
      await h.tapVisible(find.text(label), last: true);
      await h.settle(2);
    }

    // ---- enable the reminder and set it for ~3 minutes from now ----
    await openTab('Profile');
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
    final enabled = sw.evaluate().isNotEmpty &&
        (sw.evaluate().first.widget as Switch).value;

    // The reminder is scheduled at this HH:MM as a daily time-of-day: if
    // "now" has already passed HH:MM by the time this is actually SAVED
    // (real risk on a slow machine -- the picker interaction below can
    // itself take real minutes), the scheduler correctly rolls it to
    // TOMORROW rather than firing something stale -- which would then
    // never arrive within this test's own wait window. Rather than a fixed
    // lead time, this sets the time, then CONFIRMS the buffer that's
    // actually left before it's due once the real UI interaction is done,
    // retrying with a fresh, later target if too little is left.
    var leadMinutes = 8;
    late DateTime target;
    late int hour12;
    for (var attempt = 0; attempt < 3; attempt++) {
      target = DateTime.now().add(Duration(minutes: leadMinutes));
      hour12 = target.hour % 12 == 0 ? 12 : target.hour % 12;
      await h.tapVisible(find.text('Change').first);
      await h.settle(2);
      final toggle = find.byIcon(Icons.keyboard_outlined);
      if (toggle.evaluate().isNotEmpty) {
        await h.tapVisible(toggle);
        await h.settle(1);
        final fields = find.byType(TextField);
        if (fields.evaluate().length >= 2) {
          await tester.enterText(fields.at(0), '$hour12');
          await tester.enterText(fields.at(1), target.minute.toString());
          await tester.pump(const Duration(milliseconds: 300));
        }
        await h.tapVisible(find.text(target.hour < 12 ? 'AM' : 'PM'));
      }
      await h.tapVisible(find.text('OK'));
      await h.settle(2);
      final bufferLeft = target.difference(DateTime.now());
      h.note(
        'N reminder time set to ${target.hour}:${target.minute} '
        '(attempt ${attempt + 1}, buffer left ${bufferLeft.inSeconds}s)',
      );
      if (bufferLeft.inMinutes >= 3) break;
      // Too little of the lead time survived the UI interaction -- redo
      // with a longer one, informed by how slow this attempt actually was.
      leadMinutes = (leadMinutes * 2).clamp(8, 20);
    }
    h.dumpTexts('N settings after choosing ${target.hour}:${target.minute}');
    final wantedLabel =
        '$hour12:${target.minute.toString().padLeft(2, '0')} ${target.hour < 12 ? 'AM' : 'PM'}';
    final timeShown = h.notes.last.contains(wantedLabel);
    h.note('N reminder enabled=$enabled timeShown=$timeShown ($wantedLabel)');

    // ---- the OS holds a pending notification for today ----
    final pending =
        await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
    final mine = pending.where((p) {
      try {
        return (jsonDecode(p.payload ?? '{}') as Map)['userId'] == uid;
      } catch (_) {
        return false;
      }
    }).toList();
    h.note('N pending notifications for this account: ${mine.length}');

    // ---- a second, foreign-payload notification (must be ignored on tap) ----
    final foreign = jsonEncode({
      'type': 'activeBleedingCheckin',
      'userId': '00000000-0000-0000-0000-00000000dead',
      'episodeId': '00000000-0000-0000-0000-00000000beef',
      'localDate': '2026-01-01',
    });
    await NotificationService.instance.scheduleAt(
      id: 424242,
      title: 'Foreign payload test',
      body: 'Tapping this must open nothing.',
      when: DateTime.now().add(const Duration(seconds: 20)),
      payload: foreign,
    );

    // ---- go back to Today and wait for the real notification ----
    await openTab('Today');
    h.note('HOST TAP NOTIFICATION Time for your daily check-in.');
    var sheetOpened = false;
    for (var i = 0; i < 1500 && !sheetOpened; i++) {
      await tester.pump(const Duration(seconds: 1));
      sheetOpened = find.text('Are you still bleeding today?').evaluate().isNotEmpty;
    }
    h.note('N tap routed to the check-in sheet: $sheetOpened');
    await h.shot('N', 'checkin_sheet_after_notification_tap');

    // ---- answer it: a real observation is saved ----
    var answered = false;
    if (sheetOpened) {
      await h.tapVisible(find.text('Yes'));
      await h.settle(2);
      await h.tapVisible(find.text('Medium'));
      answered = await h.tapVisible(find.text('Save'), last: true);
      await tester.pump(const Duration(seconds: 4));
      await h.settle(2);
    }
    final obsAfter = await observationCount();
    h.note('N answered=$answered observations $obsBefore -> $obsAfter');

    // ---- the foreign payload must open nothing ----
    h.note('HOST TAP NOTIFICATION Tapping this must open nothing.');
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final foreignOpenedNothing =
        find.text('Are you still bleeding today?').evaluate().isEmpty;
    h.note('N foreign payload opened nothing: $foreignOpenedNothing');

    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        enabled &&
        timeShown &&
        mine.isNotEmpty &&
        sheetOpened &&
        answered &&
        obsAfter == obsBefore + 1 &&
        foreignOpenedNothing;
    h.reportResult(
      PersonaResult(
        testId: 'N',
        expectedOutcome:
            'A real notification posted by the OS and tapped in the shade '
            'opens the daily check-in for the right episode and saving it '
            'writes one observation; a notification with another account\'s '
            'payload opens nothing',
        actualOutcome:
            'crashed=$crashed enabled=$enabled timeShown=$timeShown '
            'pending=${mine.length} routed=$sheetOpened answered=$answered '
            'observations=$obsBefore->$obsAfter foreignIgnored=$foreignOpenedNothing',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'N_checkin_sheet_after_notification_tap.png',
      ),
    );
  });
}
