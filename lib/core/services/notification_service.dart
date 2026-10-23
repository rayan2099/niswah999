import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../errors/app_error_reporter.dart';
import '../utils/device_timezone.dart';
import '../utils/app_clock.dart';

/// New integrity finding — a caller must be able to distinguish these
/// outcomes rather than treating "the call returned without
/// throwing" as proof of anything. [accepted] means the OS scheduling
/// API itself acknowledged the call — it is NOT proof the notification
/// will actually be delivered or presented (a separate guarantee this
/// service cannot make and never claims to); callers must not name an
/// audit event "delivered" from this alone.
enum NotificationSchedulingOutcome {
  /// The platform scheduling API accepted the call. The only outcome
  /// that may be recorded as a successful "scheduled" audit event.
  accepted,

  /// Newer settings or an account change invalidated this operation.
  superseded,

  /// A local wall-clock reminder requires a resolved device timezone.
  timezoneUnavailable,

  /// The platform API was called and rejected/threw, or (for
  /// [NotificationService.cancel]) the cancellation call itself failed.
  failed,

  /// The non-prompting Android or iOS query reports OS permission denied.
  permissionUnavailable,

  /// [NotificationService.initialize] has not yet completed — nothing
  /// was attempted at all.
  uninitialized,
}

/// New critical finding (local notification reconciliation closure) — a
/// clean, structural view of one owned active-bleeding pending OS
/// request, decoded from Commit E7's own opaque payload shape (`type`,
/// `userId`, `episodeId`, `localDate` — never flow/Madhhab/notes/Fiqh
/// content). Deliberately never exposes the plugin's own
/// `PendingNotificationRequest` (which also carries the raw title/body
/// text) to any caller outside this file.
class PendingActiveBleedingReminder {
  const PendingActiveBleedingReminder({
    required this.id,
    required this.userId,
    required this.episodeId,
    required this.localDate,
  });

  final int id;
  final String userId;
  final String episodeId;

  /// `yyyy-MM-dd` — the logical local calendar day this reminder is
  /// about, exactly as [ActiveBleedingReminderScheduler.payloadFor]
  /// wrote it.
  final String localDate;
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
  Future<void>? _initializing;
  Future<void>? _operationTail;
  int _sessionGeneration = 0;
  bool _cleanupRequired = false;
  int get sessionGeneration => _sessionGeneration;
  static final _guardKey = Object();

  /// A refresh retains its authority across async reads. A later refresh or
  /// sign-out invalidates that authority before any platform side effect.
  Future<T> withWorkGuard<T>(
    bool Function() guard,
    Future<T> Function() work,
  ) => runZoned(work, zoneValues: {_guardKey: guard});

  bool get isWorkCurrent =>
      (Zone.current[_guardKey] as bool Function()?)?.call() ?? true;

  ({int generation, bool Function()? guard}) _captureLease() => (
    generation: _sessionGeneration,
    guard: Zone.current[_guardKey] as bool Function()?,
  );
  bool _isCurrent(({int generation, bool Function()? guard}) lease) =>
      lease.generation == _sessionGeneration && (lease.guard?.call() ?? true);

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    final running = (_operationTail ?? Future<void>.value()).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    _operationTail = running;
    running.then((_) {
      if (identical(_operationTail, running)) _operationTail = null;
    });
    return result.future;
  }

  Future<bool> finishPendingAccountCleanup() => _serialize(() async {
    if (!_initialized) return false;
    return _retryCleanup();
  });

  Future<bool> _retryCleanup() async {
    if (!_cleanupRequired) return true;
    try {
      await _plugin.cancelAll();
      _cleanupRequired = false;
      return true;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.accountCleanup',
      );
      return false;
    }
  }

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

  /// Resolved device IANA zone, or null when wall-clock scheduling must wait.
  String? get activeTimezoneId => _activeTimezoneId;
  String? _activeTimezoneId;

  /// Registers the plugin and creates the Android channel. No permission
  /// prompt here — call once from app startup.
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializing ??= _initialize().catchError((
      Object error,
      StackTrace stack,
    ) {
      _initializing = null;
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.initialize',
      );
    });
  }

  Future<void> _initialize() async {
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

    final initialized = await _plugin.initialize(
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

    if (initialized == false) {
      throw StateError('Notification plugin initialization rejected');
    }

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
  /// Unknown zones retain UTC only as an internal fallback. Wall-clock
  /// scheduling is refused until a real device zone resolves.
  Future<void> refreshLocalTimezone({bool forceRefresh = false}) async {
    final lease = _captureLease();
    final iana = await DeviceTimezone.currentId(forceRefresh: forceRefresh)
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    if (!_isCurrent(lease)) return;
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

    try {
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

      return false;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.requestPermission',
      );
      return false;
    }
  }

  /// Whether the OS currently lets this app show notifications, read WITHOUT
  /// prompting (Android `areNotificationsEnabled`, iOS `checkPermissions`).
  /// `null` when the platform cannot say or the service is not initialised —
  /// unknown, never asserted as "enabled" or "blocked". On iOS `false` also
  /// covers "never asked yet": either way a reminder cannot appear.
  Future<bool?> areNotificationsEnabled() async {
    if (!_initialized) return null;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) return await android.areNotificationsEnabled();
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) return (await ios.checkPermissions())?.isEnabled;
    } catch (_) {
      // The query itself failed — unknown, not a confirmed problem.
    }
    return null;
  }

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) {
    final lease = _captureLease();
    return _serialize(() async {
      if (!_isCurrent(lease)) return;

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
      if (!await _retryCleanup() || !_isCurrent(lease)) return;
      try {
        await _plugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: _details(),
        );
        if (!_isCurrent(lease)) await _plugin.cancel(id: id);
      } catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'NotificationService.showNow',
        );
      }
    });
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
  }) {
    final lease = _captureLease();
    return _serialize(() async {
      if (!_isCurrent(lease)) return NotificationSchedulingOutcome.superseded;

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
      if (!when.isAfter(AppClock.now())) {
        return NotificationSchedulingOutcome.failed;
      }
      if (_activeTimezoneId == null && !when.isUtc) {
        return NotificationSchedulingOutcome.timezoneUnavailable;
      }
      if (!await _retryCleanup()) return NotificationSchedulingOutcome.failed;
      if (!_isCurrent(lease)) return NotificationSchedulingOutcome.superseded;
      final permissionOutcome = await _checkKnownPermissionUnavailable();
      if (permissionOutcome != null) return permissionOutcome;
      if (!_isCurrent(lease)) return NotificationSchedulingOutcome.superseded;
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
        if (!_isCurrent(lease)) {
          await _plugin.cancel(id: id);
          return NotificationSchedulingOutcome.superseded;
        }
        return NotificationSchedulingOutcome.accepted;
      } catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'NotificationService.scheduleAt',
        );
        return NotificationSchedulingOutcome.failed;
      }
    });
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
  }) {
    final lease = _captureLease();
    return _serialize(() async {
      if (!_isCurrent(lease)) return NotificationSchedulingOutcome.superseded;

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
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return NotificationSchedulingOutcome.failed;
      }
      if (_activeTimezoneId == null) {
        return NotificationSchedulingOutcome.timezoneUnavailable;
      }
      if (!await _retryCleanup()) return NotificationSchedulingOutcome.failed;
      if (!_isCurrent(lease)) return NotificationSchedulingOutcome.superseded;
      final permissionOutcome = await _checkKnownPermissionUnavailable();
      if (permissionOutcome != null) return permissionOutcome;

      final now = tz.TZDateTime.from(AppClock.now(), tz.local);
      var firstFire = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (!firstFire.isAfter(now)) {
        // Calendar-day arithmetic (2026-10-21): `add(Duration(days: 1))`
        // added 24 absolute hours, so on a DST-change eve the first
        // occurrence landed an hour off the requested wall-clock time.
        firstFire = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day + 1,
          hour,
          minute,
        );
      }

      if (!_isCurrent(lease)) return NotificationSchedulingOutcome.superseded;
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
        if (!_isCurrent(lease)) {
          await _plugin.cancel(id: id);
          return NotificationSchedulingOutcome.superseded;
        }
        return NotificationSchedulingOutcome.accepted;
      } catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'NotificationService.scheduleDaily',
        );
        return NotificationSchedulingOutcome.failed;
      }
    });
  }

  /// Unknown platform permission remains unknown; only explicit denial blocks.
  Future<NotificationSchedulingOutcome?>
  _checkKnownPermissionUnavailable() async {
    final enabled = await areNotificationsEnabled();
    if (enabled == false) {
      return NotificationSchedulingOutcome.permissionUnavailable;
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
  Future<bool> cancel(int id) {
    final lease = _captureLease();
    return _serialize(() async {
      if (!_isCurrent(lease)) return false;

      if (!_initialized) return false;
      try {
        await _plugin.cancel(id: id);
        return _isCurrent(lease);
      } catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'NotificationService.cancel',
        );
        return false;
      }
    });
  }

  /// New critical finding (local notification reconciliation closure) —
  /// the OS's own actual pending-request set is the sole authority for
  /// what an active-bleeding reconciliation pass should cancel, not this
  /// app's own inferred guess (derived from episode history, which in
  /// turn required a Supabase read that could itself be offline). This
  /// call is purely local — `pendingNotificationRequests()` talks only
  /// to the platform plugin, never Supabase — so it works correctly in
  /// airplane mode, during a backend outage, or with an expired session.
  ///
  /// Filters to only `type: 'activeBleedingCheckin'` payloads with all
  /// three required fields present as strings; a different notification
  /// type, a payload that isn't valid JSON, or one missing a required
  /// field is silently excluded rather than crashing the whole sweep
  /// over one bad entry. A genuine platform-channel failure here returns
  /// an empty list — "unknown," never "confirmed nothing pending" — so
  /// a caller must treat an empty result from a failed read the same
  /// honest way Closure Blocker 1 already treats any other unknown: as
  /// nothing to safely act on, not as verified-empty. Scheduling a replacement
  /// window uses [throwOnFailure] so unknown reads cannot admit overlapping plans.
  Future<List<PendingActiveBleedingReminder>> pendingActiveBleedingReminders({
    bool throwOnFailure = false,
  }) async {
    if (!_initialized) {
      if (throwOnFailure) {
        throw StateError('Notification service not initialized');
      }
      return const [];
    }
    List<PendingNotificationRequest> requests;
    try {
      requests = await _plugin.pendingNotificationRequests();
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationService.pendingActiveBleedingReminders',
      );
      if (throwOnFailure) rethrow;
      return const [];
    }

    final owned = <PendingActiveBleedingReminder>[];
    for (final request in requests) {
      final payload = request.payload;
      if (payload == null) continue;
      Map<String, dynamic>? decoded;
      try {
        final parsed = jsonDecode(payload);
        if (parsed is Map<String, dynamic>) decoded = parsed;
      } catch (_) {
        // Malformed payload (not valid JSON, or not a JSON object) —
        // ignored safely, never aborts the sweep over the rest.
      }
      if (decoded == null) continue;
      if (decoded['type'] != 'activeBleedingCheckin') continue;
      final userId = decoded['userId'];
      final episodeId = decoded['episodeId'];
      final localDate = decoded['localDate'];
      if (userId is! String || episodeId is! String || localDate is! String) {
        // Missing/malformed required field — never treated as owned.
        continue;
      }
      owned.add(
        PendingActiveBleedingReminder(
          id: request.id,
          userId: userId,
          episodeId: episodeId,
          localDate: localDate,
        ),
      );
    }
    return owned;
  }

  /// Commit E9 — account signout/switch: every reminder scheduled belongs
  /// to whoever was signed in when it was computed (the active-bleeding
  /// one especially so, since its very identity — Commit E5 — is scoped
  /// to a specific user+episode). Signing out must not leave any of them
  /// live for a next, different account on the same device to see. Also
  /// discards any still-pending tap payload — a stale one is never
  /// re-checked against a later, different sign-in.
  Future<void> cancelAll() {
    _sessionGeneration++;
    _pendingTapPayload = null;
    _cleanupRequired = true;
    return _serialize(() async {
      if (_initialized) await _retryCleanup();
    });
  }

  NotificationDetails _details() => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(),
  );
}
