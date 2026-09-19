import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../errors/app_error_reporter.dart';
import '../utils/device_timezone.dart';

/// New integrity finding — a caller must be able to distinguish these
/// four outcomes rather than treating "the call returned without
/// throwing" as proof of anything. [accepted] means the OS scheduling
/// API itself acknowledged the call — it is NOT proof the notification
/// will actually be delivered or presented (a separate guarantee this
/// service cannot make and never claims to); callers must not name an
/// audit event "delivered" from this alone.
enum NotificationSchedulingOutcome {
  /// The platform scheduling API accepted the call. The only outcome
  /// that may be recorded as a successful "scheduled" audit event.
  accepted,

  /// The platform API was called and rejected/threw, or (for
  /// [NotificationService.cancel]) the cancellation call itself failed.
  failed,

  /// Known, in advance of even attempting the call, that notifications
  /// are disabled at the OS level (checked where the platform exposes a
  /// non-prompting query API — Android's `areNotificationsEnabled()`
  /// today; iOS has no equivalent non-prompting check in the installed
  /// plugin version, so this outcome is never returned there — an iOS
  /// permission-caused failure surfaces as [failed] instead, honestly
  /// less precise rather than fabricating a distinction this plugin
  /// cannot actually make on that platform).
  permissionUnavailable,

  /// [NotificationService.initialize] has not yet completed — nothing
  /// was attempted at all.
  uninitialized,
}

/// Thin wrapper around `flutter_local_notifications` — the only file in
/// this app that touches the plugin directly. Real OS-level notifications:
/// once scheduled, the OS owns delivery even if the app is killed, so
/// callers just need to (re)compute *what* to schedule at sensible
/// trigger points (app start/resume, relevant data changes) rather than
/// running any background polling themselves.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _channelId = 'niswah_reminders';
  static const _channelName = 'Niswah reminders';
  static const _channelDescription =
      'Cycle, pregnancy, nifas, wellbeing, and chat-safety reminders';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Commit E7 — tap routing. A tapped notification's payload (if any) is
  // captured here rather than acted on immediately: at tap time there is
  // no guarantee the app's own auth/routing state is ready yet
  // (especially the terminated-launch case), so the payload waits for a
  // deliberate `consumePendingTapPayload()` call once the app is ready to
  // safely decide "does this belong to whoever is signed in right now."
  String? _pendingTapPayload;

  /// Closure Blocker 9 — background/foreground notification tap routing.
  /// `onDidReceiveNotificationResponse` fires whenever she taps a
  /// notification while the process is alive, regardless of whether the
  /// app was foregrounded, backgrounded, or already showing a mounted
  /// screen — [consumePendingTapPayload] alone only covers a caller that
  /// happens to check *after* the tap (e.g. a screen's own `initState`,
  /// which never re-runs for an already-mounted screen). A listener on
  /// this stream is notified immediately instead, in addition to the
  /// payload still being available via [consumePendingTapPayload] for a
  /// terminated-launch caller that was not listening yet when the tap
  /// happened.
  final _tapController = StreamController<String>.broadcast();
  Stream<String> get onTap => _tapController.stream;

  /// Closure Blocker 6 — the real IANA zone `tz.local` is currently set
  /// to, or null if resolution has ever failed and the safe UTC fallback
  /// is active instead. Exposed only for tests/diagnostics; scheduling
  /// code should never branch on this — it should just call
  /// [refreshLocalTimezone] before scheduling and trust `tz.local`.
  String? get activeTimezoneId => _activeTimezoneId;
  String? _activeTimezoneId;

  /// Registers the plugin and creates the Android channel. No permission
  /// prompt here — call once from app startup.
  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    await refreshLocalTimezone(forceRefresh: true);

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload == null) return;
        _pendingTapPayload = payload;
        _tapController.add(payload);
      },
    );

    // The terminated-launch case (E7: "terminated-launch code path where
    // automated infrastructure permits") — the app process was not
    // running at all when she tapped, so `onDidReceiveNotificationResponse`
    // above never fires for this specific launch; the plugin surfaces the
    // same payload through this separate API instead.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null) _pendingTapPayload = payload;
    }

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// Closure Blocker 6 — resolves the device's real current IANA zone and
  /// applies it to `tz.local` (every `tz.TZDateTime`/`zonedSchedule` call
  /// in this file interprets a wall-clock time against whatever `tz.local`
  /// currently is). Previously this file only ever did
  /// `tz.setLocalLocation(tz.local)` — a no-op that re-applies whatever
  /// `tz.local` already was (UTC, since it is never otherwise set) and
  /// never actually reads the device's real zone at all.
  ///
  /// Call again on every app resume, [forceRefresh]d, *before* any
  /// reminder is (re)computed/(re)scheduled — the device's zone may have
  /// genuinely changed while backgrounded (travel, or a manual change),
  /// and a reminder computed against a stale zone would fire at the wrong
  /// wall-clock local time. Historical observations are never affected —
  /// this only ever feeds future scheduling.
  ///
  /// Never throws: an unresolvable id (the platform channel failed, or —
  /// unexpectedly — returned an id the bundled tzdata does not recognize)
  /// falls back to UTC, a safe, documented, predictable default rather
  /// than leaving `tz.local` unset or crashing scheduling over it.
  Future<void> refreshLocalTimezone({bool forceRefresh = false}) async {
    final iana = await DeviceTimezone.currentId(forceRefresh: forceRefresh);
    if (iana == null) {
      tz.setLocalLocation(tz.UTC);
      _activeTimezoneId = null;
      return;
    }
    try {
      tz.setLocalLocation(tz.getLocation(iana));
      _activeTimezoneId = iana;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.refreshLocalTimezone',
      );
      tz.setLocalLocation(tz.UTC);
      _activeTimezoneId = null;
    }
  }

  /// Contextual permission request — call this when the user actually
  /// interacts with notifications (enabling a preference, opening the
  /// feed), not unconditionally at cold start.
  Future<bool> requestPermission() async {
    if (!_initialized) return false;

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    return true;
  }

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) {
      AppErrorReporter.report(
        StateError(
          'NotificationService.showNow called before initialize() succeeded',
        ),
        StackTrace.current,
        context: 'NotificationService.showNow',
      );
      return;
    }
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _details(),
      );
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.showNow',
      );
    }
  }

  /// One-shot, fires at [when] even if the app isn't running. Scheduling
  /// again with the same [id] replaces any previous notification under
  /// that id (callers use a fixed id per notification "slot").
  /// [payload] (Commit E7) is opaque data returned on tap — never
  /// sensitive content itself (Commit E3), just enough to route.
  ///
  /// New integrity finding — returns [NotificationSchedulingOutcome]
  /// rather than `void`: a caller that previously assumed "didn't throw"
  /// meant "the OS actually scheduled this" had no way to notice a
  /// silently-swallowed failure before recording a "scheduled" audit
  /// event that never happened. [NotificationSchedulingOutcome.accepted]
  /// is the only outcome honestly recordable as such.
  Future<NotificationSchedulingOutcome> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (!_initialized) {
      AppErrorReporter.report(
        StateError(
          'NotificationService.scheduleAt called before initialize() succeeded',
        ),
        StackTrace.current,
        context: 'NotificationService.scheduleAt',
      );
      return NotificationSchedulingOutcome.uninitialized;
    }
    final permissionOutcome = await _checkKnownPermissionUnavailable();
    if (permissionOutcome != null) return permissionOutcome;
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details(),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return NotificationSchedulingOutcome.accepted;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.scheduleAt',
      );
      return NotificationSchedulingOutcome.failed;
    }
  }

  /// Repeats daily at the given local time (e.g. the wellbeing check-in
  /// reminder) until [cancel]led. See [scheduleAt]'s own doc comment for
  /// why this returns [NotificationSchedulingOutcome].
  Future<NotificationSchedulingOutcome> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (!_initialized) {
      AppErrorReporter.report(
        StateError(
          'NotificationService.scheduleDaily called before initialize() succeeded',
        ),
        StackTrace.current,
        context: 'NotificationService.scheduleDaily',
      );
      return NotificationSchedulingOutcome.uninitialized;
    }
    final permissionOutcome = await _checkKnownPermissionUnavailable();
    if (permissionOutcome != null) return permissionOutcome;

    final now = tz.TZDateTime.now(tz.local);
    var firstFire = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (firstFire.isBefore(now)) {
      firstFire = firstFire.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: firstFire,
        notificationDetails: _details(),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return NotificationSchedulingOutcome.accepted;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.scheduleDaily',
      );
      return NotificationSchedulingOutcome.failed;
    }
  }

  /// Android-only, non-prompting permission query — see
  /// [NotificationSchedulingOutcome.permissionUnavailable]'s own doc
  /// comment for why no iOS equivalent exists here. Returns null (no
  /// known permission problem) rather than [NotificationSchedulingOutcome.
  /// permissionUnavailable] whenever the platform can't answer the
  /// question at all (iOS, or the query itself failing) — silence here
  /// is "unknown," never asserted as "unavailable."
  Future<NotificationSchedulingOutcome?>
  _checkKnownPermissionUnavailable() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return null;
    try {
      final enabled = await androidPlugin.areNotificationsEnabled();
      if (enabled == false) {
        return NotificationSchedulingOutcome.permissionUnavailable;
      }
    } catch (_) {
      // Query itself failed — treat as unknown, not as a confirmed
      // permission problem; the scheduling attempt below will surface
      // its own honest failed/accepted outcome regardless.
    }
    return null;
  }

  /// Commit E7 — returns and clears whatever tap payload is currently
  /// pending, or null if none. Consuming (not merely peeking) means a
  /// payload that turns out to belong to a different account than the
  /// one currently signed in is discarded outright rather than being
  /// re-checked against a later, different sign-in — "if wrong user,
  /// cancel/ignore safely" (E7) applies to a stale payload too.
  String? consumePendingTapPayload() {
    final payload = _pendingTapPayload;
    _pendingTapPayload = null;
    return payload;
  }

  /// New integrity finding — returns whether the cancellation actually
  /// succeeded. A failed cancellation must never be recorded as a
  /// successful "cancelled" audit event; `false` here is the caller's
  /// signal to not record one (the notification may still be live).
  Future<bool> cancel(int id) async {
    if (!_initialized) return false;
    try {
      await _plugin.cancel(id: id);
      return true;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.cancel',
      );
      return false;
    }
  }

  /// Commit E9 — account signout/switch: every reminder scheduled belongs
  /// to whoever was signed in when it was computed (the active-bleeding
  /// one especially so, since its very identity — Commit E5 — is scoped
  /// to a specific user+episode). Signing out must not leave any of them
  /// live for a next, different account on the same device to see. Also
  /// discards any still-pending tap payload — a stale one is never
  /// re-checked against a later, different sign-in.
  Future<void> cancelAll() async {
    _pendingTapPayload = null;
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.cancelAll',
      );
    }
  }

  NotificationDetails _details() => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );
}
