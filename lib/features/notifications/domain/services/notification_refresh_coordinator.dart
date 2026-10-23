import 'dart:async';
import 'dart:convert';

import '../../../cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import '../entities/notification_target.dart';
import '../../../../core/preferences/notification_delivery_preferences.dart';

import 'package:timezone/timezone.dart' as tz;

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/preferences/notification_log_controller.dart';
import '../../../../core/preferences/pregnancy_status_controller.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/calendar_days.dart';
import '../../../../core/preferences/prayer_location_controller.dart';
import '../../../cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import '../../../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../../../cycle_tracking/domain/entities/bleeding_episode.dart';
import '../../../cycle_tracking/domain/entities/load_result.dart';
import '../../../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../../pregnancy_profile/domain/entities/pregnancy_profile.dart';
import '../../../pregnancy_profile/domain/services/pregnancy_status_engine.dart';
import '../../data/local/notification_event_log_store.dart';
import '../../data/repositories/notification_repository_impl.dart';
import '../entities/notification_event.dart';
import '../entities/notification_preference.dart';
import 'notification_scheduler.dart';
import 'prayer_reminder_scheduler.dart';

/// The side-effecting glue between real app state and
/// [NotificationService] — loads preferences + real data, asks the pure
/// [NotificationScheduler] planners what should fire, and (re)schedules
/// accordingly. Call at natural trigger points (app start, app resume) —
/// once scheduled, the OS owns delivery, so no background polling is
/// needed here.
class NotificationRefreshCoordinator {
  const NotificationRefreshCoordinator._();

  static int _refreshGeneration = 0;
  static const wellbeingReminderId = 104;
  static const fertilityReminderId = 105;
  static const learningReminderId = 106;
  static const _wellbeingReminderHour = 20;

  /// The daily check-in reminder's default local time, used only until
  /// she customizes [NotificationPreference.preferredHour]/
  /// [NotificationPreference.preferredMinute] in Settings (Closure
  /// Blocker 7) — never itself the actual scheduled time once a real
  /// preference exists.
  static const _activeBleedingReminderHour = 18;
  static const _activeBleedingReminderMinute = 0;

  /// How many local days ahead (today included) are scheduled every
  /// refresh. Deliberately bounded, not "as many as the episode might
  /// last" — iOS enforces a hard, OS-wide 64-pending-notification
  /// ceiling shared across every notification type this app schedules
  /// (cycle, pregnancy, nifas, wellbeing, active-bleeding), so this
  /// window must stay modest rather than claim unlimited lookahead.
  /// Re-planned (and naturally extended forward) on every refresh, so an
  /// episode lasting longer than this window is never actually left
  /// without reminders as long as the app is opened at least once within
  /// any [_rollingWindowDays]-day stretch. See
  /// [ActiveBleedingReminderScheduler.defaultRollingWindowDays]'s own doc
  /// comment for why this is the SOLE scheduling mechanism (no separate
  /// recurring fallback layered on top) and why 30 days was chosen. A
  /// single shared constant so every call site that must cancel a whole
  /// window's ids — not only the scheduling call site — stays in
  /// agreement about its size.
  static const _rollingWindowDays =
      ActiveBleedingReminderScheduler.defaultRollingWindowDays;

  static Future<void> refresh({
    required String? userId,
    CycleTrackingRepositoryImpl? cycleRepository,
    PregnancyProfileRepository? pregnancyRepository,
    NotificationRepositoryImpl? preferenceRepository,
    BleedingEpisodeRepositoryImpl? bleedingRepository,
    Future<List<CanonicalEpisodeTiming>?> Function(String userId)?
    cycleHistoryLoader,
    Future<CycleBaseline?> Function(String userId)? statedBaselineLoader,
  }) async {
    final generation = ++_refreshGeneration;
    final service = NotificationService.instance;
    // Signed-out refreshes only invalidate and clear; they must not start
    // timezone/plugin initialization or any account-scoped reads.
    if (userId == null) {
      await service.cancelAll();
      return;
    }
    final session = service.sessionGeneration;
    bool current() =>
        generation == _refreshGeneration &&
        session == service.sessionGeneration;
    await service.withWorkGuard(current, () async {
      await service.initialize();
      if (!current()) return;
      if (!await service.finishPendingAccountCleanup() || !current()) return;
      await NotificationDeliveryPreferences.instance.load();
      await service.refreshLocalTimezone(forceRefresh: true);
      if (!current()) return;
      final preferences =
          await (preferenceRepository ?? NotificationRepositoryImpl())
              .loadPreferences();
      if (!current()) return;
      final now = service.activeTimezoneId == null
          ? AppClock.now()
          : tz.TZDateTime.from(AppClock.now(), tz.local);

      if (!(preferences[NotificationType.fertility]?.enabled ?? false)) {
        await _apply(fertilityReminderId, null);
      }
      await _stage(
        () => _refreshLearning(preferences: preferences, userId: userId),
      );
      // Local opt-outs take effect before any network read. Each later
      // platform operation retains this refresh's guard across async waits.
      if (!(preferences[NotificationType.cycle]?.enabled ?? false)) {
        await _apply(NotificationScheduler.cycleNotificationId, null);
      }
      if (!(preferences[NotificationType.pregnancy]?.enabled ?? false)) {
        await _apply(NotificationScheduler.pregnancyNotificationId, null);
        await _apply(NotificationScheduler.nifasNotificationId, null);
      }
      if (!(preferences[NotificationType.activeBleeding]?.enabled ?? false)) {
        await _cancelAllOwnedActiveBleedingReminders(userId: userId, now: now);
      }
      if (!current()) return;
      await _stage(
        () => _refreshWellbeingDaily(preferences: preferences, userId: userId),
      );
      await _stage(
        () =>
            _refreshPrayers(preferences: preferences, userId: userId, now: now),
      );
      if (!current()) return;
      await Future.wait([
        _stage(
          () => _refreshActiveBleeding(
            preferences: preferences,
            userId: userId,
            bleedingRepository:
                bleedingRepository ?? BleedingEpisodeRepositoryImpl(),
            now: now,
          ),
        ),
        _stage(() async {
          final needsProfile =
              (preferences[NotificationType.cycle]?.enabled ?? false) ||
              (preferences[NotificationType.fertility]?.enabled ?? false) ||
              (preferences[NotificationType.pregnancy]?.enabled ?? false);
          final profileRead = needsProfile
              ? await _loadProfile(
                  pregnancyRepository ?? PregnancyProfileRepository(),
                  userId,
                )
              : const _ProfileRead.none();
          if (!current()) return;
          await _stage(
            () => _refreshCycle(
              preferences: preferences,
              userId: userId,
              cycleRepository: cycleRepository ?? CycleTrackingRepositoryImpl(),
              cycleHistoryLoader: cycleHistoryLoader ?? _loadCycleHistory,
              statedBaselineLoader: statedBaselineLoader ?? _loadStatedBaseline,
              profileRead: profileRead,
              now: now,
            ),
          );
          if (!current()) return;
          await _refreshPregnancyAndNifas(
            preferences: preferences,
            userId: userId,
            profileRead: profileRead,
            now: now,
          );
        }),
      ]);
    });
  }

  static Future<void> _stage(Future<void> Function() action) async {
    if (!NotificationService.instance.isWorkCurrent) return;
    try {
      await action();
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationRefreshCoordinator.refresh',
        feature: 'notifications',
      );
    }
  }

  static Future<void> _refreshPrayers({
    required Map<NotificationType, NotificationPreference> preferences,
    required String userId,
    required DateTime now,
  }) async {
    final preference = preferences[NotificationType.prayer];
    final settings = PrayerLocationController.instance;
    final plans = preference?.enabled == true
        ? PrayerReminderScheduler.plan(
            userId: userId,
            location: settings.selectedOrNull,
            now: now,
            method: settings.method,
            hanafiAsr: settings.hanafiAsr,
            leadMinutes: preference!.leadTimeMinutes,
            ramadanAdjustmentUntil: settings.ramadanAdjustmentUntil,
          )
        : const <PlannedNotification>[];
    final desired = plans.map((p) => p.id).toSet();
    for (final id in PrayerReminderScheduler.ids) {
      if (!desired.contains(id)) await NotificationService.instance.cancel(id);
    }
    for (final plan in plans) {
      await _apply(
        plan.id,
        plan,
        userId: userId,
        destinationOverride: NotificationDestination.prayer,
        typeOverride: NotificationType.prayer,
      );
    }
  }

  /// Commit E — the recurring daily check-in reminder, tied to a real
  /// open episode rather than a prediction. E4: recomputed from scratch
  /// on every refresh (app start/resume), so a timezone/offset change
  /// picked up by [DeviceTimezone.invalidateCache] (see `main.dart`'s
  /// resume handler, which calls this refresh right after) is reflected
  /// immediately — nothing here caches a stale `now`/offset across calls.
  static Future<void> _refreshActiveBleeding({
    required Map<NotificationType, NotificationPreference> preferences,
    required String? userId,
    required BleedingEpisodeRepositoryImpl bleedingRepository,
    required DateTime now,
  }) async {
    final activeBleedingPreference =
        preferences[NotificationType.activeBleeding];
    final enabled = activeBleedingPreference?.enabled ?? false;
    final today = calendarDay(now);

    if (!enabled || userId == null) {
      // New critical finding (local notification reconciliation closure,
      // Finding 1) — an explicit local opt-out must take effect locally
      // even with Supabase offline/unreachable, airplane mode, or an
      // expired/refreshing session: this must NEVER go through
      // `getEpisodesForUser` (a Supabase read) to decide what to cancel.
      // The OS's own actual pending-request set is the sole authority
      // here. No session at all (signed out) has nothing further to do
      // — Commit E9's own `cancelAll()` at sign-out already covers that
      // case, broader by explicit design.
      if (userId != null) {
        await _cancelAllOwnedActiveBleedingReminders(userId: userId, now: now);
      }
      return;
    }

    // Closure Blocker 1: a read failure must never be concluded as "no
    // open episode" — that would silently cancel/never-schedule a real,
    // still-open episode's reminder purely because the read hiccuped.
    // Leaving the refresh as a no-op (whatever was already scheduled
    // stays scheduled) is the honest response to "genuinely unknown."
    final episodeResult = await bleedingRepository
        .getOpenEpisode(userId)
        .timeout(const Duration(seconds: 10));
    if (!NotificationService.instance.isWorkCurrent) return;
    if (episodeResult is LoadUnavailable<BleedingEpisode?>) return;
    final episode = episodeResult.dataOrNull;
    if (!ActiveBleedingReminderScheduler.isEligible(episode)) {
      // New critical finding (local notification reconciliation closure,
      // Finding 2) — a *verified* absence of an open episode (as opposed
      // to a read failure, handled above — `getOpenEpisode` returning a
      // clean `null` is VERIFIED, never inferred) covers both "she ended
      // it here" and "it ended on a different device." No second
      // `getEpisodesForUser` read is needed to discover what to cancel —
      // the OS pending set already says exactly what is live. Only
      // reached once this device's own next successful refresh confirms
      // it — never claimed instantaneous while offline or never
      // reopened.
      await _cancelAllOwnedActiveBleedingReminders(userId: userId, now: now);
      return;
    }

    final episodeId = episode!.id;
    if (episodeId == null) return;

    final observationsResult = await bleedingRepository
        .getObservationsForEpisode(episodeId)
        .timeout(const Duration(seconds: 10));
    if (!NotificationService.instance.isWorkCurrent) return;
    if (observationsResult is LoadUnavailable<List<BleedingObservation>>) {
      return;
    }
    final observations = observationsResult.dataOrNull ?? const [];
    final todaysObservationCount = observations
        .where((o) => o.observedDate.isAtSameMomentAs(today))
        .length;

    // New critical finding — multi-day notification continuity: a
    // client-only scheduler cannot rely on the app being reopened daily,
    // so every refresh plans a BOUNDED rolling window of future local
    // days at once (today through today + _rollingWindowDays - 1), not
    // only today's. Re-planning the same window on every refresh is
    // idempotent (an unchanged plan reschedules under the same id, a
    // no-op replacement) — it only ever extends the window forward,
    // never duplicates. Closure Blocker 7's own real, persisted,
    // user-choosable time is still the basis for every day in the
    // window; the defaults below are only ever used before she has
    // customized it.
    final leadHour =
        activeBleedingPreference?.preferredHour ?? _activeBleedingReminderHour;
    final leadMinute =
        activeBleedingPreference?.preferredMinute ??
        _activeBleedingReminderMinute;
    final plans = ActiveBleedingReminderScheduler.planRollingDailyCheckins(
      episode: episode,
      todaysObservationCount: todaysObservationCount,
      now: now,
      leadHour: leadHour,
      leadMinute: leadMinute,
      daysAhead: _rollingWindowDays,
    );

    // New critical finding (local notification reconciliation closure,
    // Finding 2/set reconciliation) — `desiredIds` is exactly the set of
    // ids the current 30-day plan wants scheduled (E6: today's own id is
    // already absent here when today's obligation is satisfied). Rather
    // than trying to infer what MAY have been scheduled by scanning
    // episode history (the prior approach — fragile under a timezone
    // shift, and blind to a rejected cancel that silently left an id
    // live), this reconciles against what ACTUALLY is registered with
    // the OS for this exact user+episode right now:
    // `actualOwnedPendingIds - desiredIds` is cancelled; every desired id
    // is (re)scheduled below regardless, an idempotent replace for one
    // already correct. This one pass alone covers stale same-day ids
    // (today satisfied), stale past-day ids (day-forward progression), a
    // stale far-future id left behind by a timezone shift, and a stale
    // id left behind by a preferred-time change — all without needing
    // separate bespoke sweeps for each cause, and without depending on
    // `episode.startDate` to bound a guess.
    final pending = await NotificationService.instance
        .pendingActiveBleedingReminders(throwOnFailure: true);
    final desiredIds = plans.map((p) => p.id).toSet();
    for (final owned in pending) {
      if (owned.userId != userId) continue;
      if (owned.episodeId == episodeId && desiredIds.contains(owned.id)) {
        continue;
      }
      // New integrity finding — a failed cancellation must never be
      // recorded as a successful one; the notification may still be
      // live, and the audit trail must say so honestly, leaving it
      // visible for a later retry rather than a false "cancelled".
      final cancelled = await NotificationService.instance.cancel(owned.id);
      // Do not expand the window while a stale request remains live. A
      // later refresh retries cleanup before admitting replacement requests.
      if (!cancelled) return;
      if (cancelled) {
        await NotificationLogController.instance.removePending(
          'activeBleeding_${owned.id}',
        );
        await _recordEventOnce(
          reminderId: owned.id.toString(),
          state: NotificationEventState.cancelled,
          userId: userId,
          episodeId: owned.episodeId,
          logicalLocalDate: _parseIsoDate(owned.localDate) ?? today,
          now: now,
        );
      }
    }

    for (final plan in plans) {
      // New integrity finding — the scheduling audit event (and, for
      // today's own plan, the display-feed entry below) may only ever be
      // recorded once the OS scheduling API has actually acknowledged
      // the call; a caught exception previously still fell through to
      // logging "scheduled" regardless.
      final schedulingOutcome = await NotificationService.instance.scheduleAt(
        id: plan.id,
        title: AppLocaleController.instance.isArabic
            ? plan.titleAr
            : plan.titleEn,
        body: AppLocaleController.instance.isArabic ? plan.bodyAr : plan.bodyEn,
        when: plan.fireAt,
        payload: plan.payload,
      );
      if (schedulingOutcome == NotificationSchedulingOutcome.quietHours) {
        await NotificationLogController.instance.removePending(
          'activeBleeding_${plan.id}',
        );
      }
      if (schedulingOutcome != NotificationSchedulingOutcome.accepted) {
        continue;
      }

      // Closure Blocker 13 — the actual structural scheduling-audit
      // event, distinct from the display-feed entry below. Recorded for
      // every day in the window (the full audit trail), once per
      // reminder id.
      await _recordEventOnce(
        reminderId: plan.id.toString(),
        state: NotificationEventState.scheduled,
        userId: userId,
        episodeId: episodeId,
        logicalLocalDate: DateTime(
          plan.fireAt.year,
          plan.fireAt.month,
          plan.fireAt.day,
        ),
        now: now,
      );

      // Commit E8 — event audit / display feed: deliberately restricted
      // to *today's own* plan only — she does not need her feed telling
      // her "a reminder exists 6 days from now" every time she opens the
      // app; the structural audit event above already records every
      // day's own scheduling honestly, this is purely the user-facing
      // surface. Mirrors [_apply]'s own dedupe-by-id logic, and — like
      // every other entry this controller logs — never persists the
      // notification body text as a *tracking* record (the log entry
      // itself already needs body text to display in the feed, an
      // existing, accepted product surface; this comment documents that
      // no *additional*, hidden tracking field carries anything more
      // sensitive, e.g. flow/Madhhab).
      final isTodaysPlan =
          plan.fireAt.year == today.year &&
          plan.fireAt.month == today.month &&
          plan.fireAt.day == today.day;
      if (!isTodaysPlan) continue;
      // Pregnancy/nifas hardening (2026-10-21): logged with its fireAt,
      // so the feed shows it only once it has fired (never "just now"
      // hours early); upsertScheduled never adds the same id twice.
      final logEntryId = 'activeBleeding_${plan.id}';
      await NotificationLogController.instance.upsertScheduled(
        logEntryId,
        NotificationLogEntry(
          id: logEntryId,
          type: NotificationType.activeBleeding,
          titleAr: plan.feedTitleAr,
          bodyAr: plan.feedBodyAr,
          titleEn: plan.feedTitleEn,
          bodyEn: plan.feedBodyEn,
          createdAt: AppClock.now(),
          fireAt: plan.fireAt,
        ),
      );
    }
  }

  /// New critical finding (local notification reconciliation closure,
  /// Findings 1/2) — cancels every active-bleeding reminder the OS
  /// itself currently has pending for [userId], across every episode
  /// (an ended episode's own stray ids are just as much "not wanted
  /// anymore" as a still-open one's, once we've determined nothing
  /// should currently be scheduled at all). Deliberately reads
  /// [NotificationService.pendingActiveBleedingReminders] — the OS's own
  /// actual pending set — rather than `getEpisodesForUser` (a Supabase
  /// read): an explicit local opt-out, or a verified episode end, must
  /// take effect purely locally, correctly even with Supabase
  /// offline/unreachable, airplane mode, or an expired/refreshing
  /// session. Called only when this refresh has genuinely determined
  /// nothing should currently be scheduled (the preference is off, or a
  /// canonical read confirms no open episode exists) — never on a mere
  /// read failure, which stays honestly unresolved rather than
  /// triggering a destructive sweep. One rejected cancel never stops the
  /// rest from being attempted, and is never recorded as a false
  /// "cancelled" audit event.
  static Future<void> _cancelAllOwnedActiveBleedingReminders({
    required String userId,
    required DateTime now,
  }) async {
    final pending = await NotificationService.instance
        .pendingActiveBleedingReminders();
    for (final owned in pending) {
      // Account isolation — only ever cancel requests the payload
      // itself structurally attributes to this signed-in user.
      if (owned.userId != userId) continue;
      final cancelled = await NotificationService.instance.cancel(owned.id);
      if (cancelled) {
        await NotificationLogController.instance.removePending(
          'activeBleeding_${owned.id}',
        );
        await _recordEventOnce(
          reminderId: owned.id.toString(),
          state: NotificationEventState.cancelled,
          userId: userId,
          episodeId: owned.episodeId,
          logicalLocalDate: _parseIsoDate(owned.localDate) ?? now,
          now: now,
        );
      }
    }
  }

  /// Parses the `yyyy-MM-dd` string
  /// [ActiveBleedingReminderScheduler.payloadFor] itself writes back into
  /// a [DateTime] — null on anything malformed (defensive only; this app
  /// always writes a well-formed value itself).
  static DateTime? _parseIsoDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  /// Records one structural audit event unless an event of that same
  /// [state] already exists for this [reminderId] — the shared dedupe
  /// every scheduled/cancelled recording site above needs, extracted so
  /// the rolling window's per-day loop doesn't repeat it inline.
  /// [logicalLocalDate] is the specific local day this one reminder is
  /// actually about (each day in the rolling window gets its own, real
  /// value here — never fabricated as "today" for a different day).
  static Future<void> _recordEventOnce({
    required String reminderId,
    required NotificationEventState state,
    required String userId,
    required String episodeId,
    required DateTime logicalLocalDate,
    required DateTime now,
  }) async {
    final priorEvents = await NotificationEventLogStore.loadForReminder(
      reminderId,
    );
    if (!NotificationService.instance.isWorkCurrent) return;
    final alreadyRecorded = priorEvents.any((e) => e.state == state);
    if (alreadyRecorded) return;
    await NotificationEventLogStore.record(
      NotificationEvent(
        reminderId: reminderId,
        notificationType: NotificationType.activeBleeding.name,
        state: state,
        eventTimestamp: now,
        userId: userId,
        episodeId: episodeId,
        logicalLocalDate: _isoDate(logicalLocalDate),
      ),
    );
  }

  /// Canonical episode timing for the cycle reminder. Its own repository
  /// instance, so the active-bleeding reconciliation's repository is never
  /// asked for a `getEpisodesForUser` read on its behalf. An unavailable
  /// read falls back to logs only, exactly as before this history was
  /// used; a degraded one (rows quarantined) returns null so no reminder
  /// is planned from history known to be incomplete.
  static Future<List<CanonicalEpisodeTiming>?> _loadCycleHistory(
    String userId,
  ) async {
    final result = await BleedingEpisodeRepositoryImpl().getEpisodesForUser(
      userId,
    );
    if (result is LoadDegraded<List<BleedingEpisode>>) return null;
    return [
      for (final episode in result.dataOrNull ?? const <BleedingEpisode>[])
        CanonicalEpisodeTiming(
          startDate: episode.startDate,
          endDate: episode.endDate,
        ),
    ];
  }

  /// Her onboarding estimate, so the reminder lands on the same date the
  /// app shows (which blends it in while history is short). A failed read
  /// is just "no estimate".
  static Future<CycleBaseline?> _loadStatedBaseline(String userId) async {
    try {
      return await CycleBaselineRepositoryImpl().getBaseline(userId);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _refreshCycle({
    required Map<NotificationType, NotificationPreference> preferences,
    required String? userId,
    required CycleTrackingRepositoryImpl cycleRepository,
    required Future<List<CanonicalEpisodeTiming>?> Function(String userId)
    cycleHistoryLoader,
    required Future<CycleBaseline?> Function(String userId)
    statedBaselineLoader,
    required _ProfileRead profileRead,
    required DateTime now,
  }) async {
    final cycleEnabled = preferences[NotificationType.cycle]?.enabled ?? false;
    final fertilityEnabled =
        preferences[NotificationType.fertility]?.enabled ?? false;
    final enabled = cycleEnabled || fertilityEnabled;
    if (!enabled) {
      await _apply(NotificationScheduler.cycleNotificationId, null);
      await _apply(fertilityReminderId, null);
      return;
    }

    // No "period approaching" while pregnant or in nifas — per the synced
    // profile or this device's own flags (either is enough).
    final pregnancyController = PregnancyStatusController.instance;
    if (NotificationScheduler.suppressesCycleReminder(
      pregnancy: profileRead.profile == null
          ? null
          : PregnancyStatusEngine.getStatus(profileRead.profile, now),
      locallyPregnant: pregnancyController.isPregnant,
      locallyInNifas: pregnancyController.isNifasActive,
    )) {
      await _apply(NotificationScheduler.cycleNotificationId, null);
      await _apply(fertilityReminderId, null);
      return;
    }

    // A failed profile read leaves pregnancy status unknown (nothing on
    // this device says pregnant or nifas either): keep the cycle slot as
    // it is rather than planning from history as if not pregnant.
    if (profileRead.failed) return;

    final logs = await cycleRepository
        .getCycleLogs(limit: CycleCalculationService.historyLogLimit)
        .timeout(const Duration(seconds: 10));
    if (!NotificationService.instance.isWorkCurrent) return;

    // The same canonical episode history (e.g. periods reported during
    // onboarding) the dashboard predicts from — without it the reminder
    // could be missing, or land on a different date than the app shows.
    final canonicalEpisodes = userId == null || userId == 'local-user'
        ? const <CanonicalEpisodeTiming>[]
        : await cycleHistoryLoader(userId).timeout(const Duration(seconds: 10));
    if (!NotificationService.instance.isWorkCurrent) return;
    if (canonicalEpisodes == null) {
      // Known-incomplete history (an episode was quarantined): the
      // calendar refuses to predict from it, so no reminder may either.
      await _apply(NotificationScheduler.cycleNotificationId, null);
      await _apply(fertilityReminderId, null);
      return;
    }
    final statedBaseline = userId == null || userId == 'local-user'
        ? null
        : await statedBaselineLoader(userId)
              .timeout(const Duration(seconds: 10));
    if (!NotificationService.instance.isWorkCurrent) return;
    final calculation = const CycleCalculationService().calculate(
      logs,
      asOf: now,
      canonicalEpisodes: canonicalEpisodes,
      statedBaseline: statedBaseline,
    );
    final plan = !cycleEnabled
        ? null
        : NotificationScheduler.planCycleReminder(
            calculation: calculation,
            now: now,
            reminderHour:
                preferences[NotificationType.cycle]?.preferredHour ?? 9,
            reminderMinute:
                preferences[NotificationType.cycle]?.preferredMinute ?? 0,
          );
    await _apply(
      NotificationScheduler.cycleNotificationId,
      plan,
      userId: userId,
    );
    final summary = const CycleTrackingController().summarizeCalculation(
      calculation,
      today: now,
    );
    final start = summary.fertileWindow.start;
    PlannedNotification? fertilePlan;
    if (fertilityEnabled && start != null) {
      final pref = preferences[NotificationType.fertility];
      final fireAt = now is tz.TZDateTime
          ? tz.TZDateTime(
              now.location,
              start.year,
              start.month,
              start.day,
              pref?.preferredHour ?? 9,
              pref?.preferredMinute ?? 0,
            )
          : DateTime(
              start.year,
              start.month,
              start.day,
              pref?.preferredHour ?? 9,
              pref?.preferredMinute ?? 0,
            );
      if (fireAt.isAfter(now)) {
        fertilePlan = PlannedNotification(
          id: fertilityReminderId,
          fireAt: fireAt,
          titleAr: NotificationScheduler.discreetTitleAr,
          bodyAr: NotificationScheduler.discreetBodyAr,
          titleEn: NotificationScheduler.discreetTitleEn,
          bodyEn: NotificationScheduler.discreetBodyEn,
          feedTitleAr: 'نافذة الخصوبة التقديرية',
          feedBodyAr: 'راجعي التقديرات في التقويم؛ الإباضة غير مؤكدة.',
          feedTitleEn: 'Estimated fertile window',
          feedBodyEn:
              'Review the estimates in Calendar; ovulation is not confirmed.',
        );
      }
    }
    await _apply(fertilityReminderId, fertilePlan, userId: userId);
  }

  static Future<void> _refreshPregnancyAndNifas({
    required Map<NotificationType, NotificationPreference> preferences,
    required String? userId,
    required _ProfileRead profileRead,
    required DateTime now,
  }) async {
    final enabled = preferences[NotificationType.pregnancy]?.enabled ?? false;
    if (!enabled || userId == null) {
      await _apply(NotificationScheduler.pregnancyNotificationId, null);
      await _apply(NotificationScheduler.nifasNotificationId, null);
      return;
    }

    // A birth logged on this device (nifas active) ends the pregnancy-week
    // slot whatever the server says: the row may still read pregnant (its
    // postpartum write failed) or be unreadable right now.
    final locallyInNifas = PregnancyStatusController.instance.isNifasActive;
    if (locallyInNifas) {
      await _apply(NotificationScheduler.pregnancyNotificationId, null);
    }

    // A failed profile read is "unknown": leave whatever is scheduled as
    // it is (it previously threw out of the whole refresh).
    if (profileRead.failed) return;

    final profile = profileRead.profile;
    final pregnancyPlan = locallyInNifas
        ? null
        : NotificationScheduler.planPregnancyMilestone(
            profile: profile,
            now: now,
            reminderHour:
                preferences[NotificationType.pregnancy]?.preferredHour ?? 9,
            reminderMinute:
                preferences[NotificationType.pregnancy]?.preferredMinute ?? 0,
          );
    await _apply(
      NotificationScheduler.pregnancyNotificationId,
      pregnancyPlan,
      userId: userId,
    );

    final nifasPlan = NotificationScheduler.planNifasCountdown(
      profile: profile,
      now: now,
      reminderHour: preferences[NotificationType.pregnancy]?.preferredHour ?? 9,
      reminderMinute:
          preferences[NotificationType.pregnancy]?.preferredMinute ?? 0,
    );
    await _apply(
      NotificationScheduler.nifasNotificationId,
      nifasPlan,
      userId: userId,
    );
  }

  static Future<_ProfileRead> _loadProfile(
    PregnancyProfileRepository repository,
    String userId,
  ) async {
    try {
      return _ProfileRead.loaded(
        await repository
            .getForUser(userId)
            .timeout(const Duration(seconds: 10)),
      );
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationRefreshCoordinator._loadProfile',
        feature: 'notifications',
      );
      return const _ProfileRead.failed();
    }
  }

  static Future<void> _refreshWellbeingDaily({
    required Map<NotificationType, NotificationPreference> preferences,
    required String userId,
  }) async {
    final enabled = preferences[NotificationType.wellbeing]?.enabled ?? false;
    if (!enabled) {
      await NotificationService.instance.cancel(wellbeingReminderId);
      return;
    }

    final isArabic = AppLocaleController.instance.isArabic;
    await NotificationService.instance.scheduleDaily(
      id: wellbeingReminderId,
      title: isArabic
          ? NotificationScheduler.discreetTitleAr
          : NotificationScheduler.discreetTitleEn,
      body: isArabic
          ? NotificationScheduler.discreetBodyAr
          : NotificationScheduler.discreetBodyEn,
      hour:
          preferences[NotificationType.wellbeing]?.preferredHour ??
          _wellbeingReminderHour,
      minute: preferences[NotificationType.wellbeing]?.preferredMinute ?? 0,
      payload: jsonEncode(
        NotificationTarget(
          destination: NotificationDestination.wellbeing,
          userId: userId,
        ).toJson(),
      ),
    );
  }

  static Future<void> _refreshLearning({
    required Map<NotificationType, NotificationPreference> preferences,
    required String userId,
  }) async {
    final pref = preferences[NotificationType.learning];
    if (pref?.enabled != true) {
      await NotificationService.instance.cancel(learningReminderId);
      return;
    }
    await NotificationService.instance.scheduleDaily(
      id: learningReminderId,
      title: NotificationScheduler.discreetTitleEn,
      body: AppLocaleController.instance.isArabic
          ? NotificationScheduler.discreetBodyAr
          : NotificationScheduler.discreetBodyEn,
      hour: pref!.preferredHour ?? 20,
      minute: pref.preferredMinute ?? 0,
      payload: jsonEncode(
        NotificationTarget(
          destination: NotificationDestination.learning,
          userId: userId,
        ).toJson(),
      ),
    );
  }

  static Future<void> _apply(
    int id,
    PlannedNotification? plan, {
    String? userId,
    NotificationDestination? destinationOverride,
    NotificationType? typeOverride,
  }) async {
    if (plan == null) {
      final cancelled = await NotificationService.instance.cancel(id);
      // A cancelled reminder must never surface in the feed later.
      if (cancelled) {
        await NotificationLogController.instance.removePending('$id');
      }
      return;
    }

    final destination =
        destinationOverride ??
        (id == NotificationScheduler.cycleNotificationId ||
                id == fertilityReminderId
            ? NotificationDestination.calendar
            : NotificationDestination.pregnancy);
    final target = userId == null
        ? null
        : NotificationTarget(destination: destination, userId: userId);
    final isArabic = AppLocaleController.instance.isArabic;
    // New integrity finding — the display-feed log entry below must not
    // be recorded unless the OS scheduling API actually accepted the
    // call; otherwise the feed could tell her a reminder exists when it
    // does not.
    final outcome = await NotificationService.instance.scheduleAt(
      id: id,
      title: isArabic ? plan.titleAr : plan.titleEn,
      body: isArabic ? plan.bodyAr : plan.bodyEn,
      when: plan.fireAt,
      payload: target == null ? null : jsonEncode(target.toJson()),
    );
    if (outcome == NotificationSchedulingOutcome.quietHours) {
      await NotificationLogController.instance.removePending('$id');
    }
    if (outcome != NotificationSchedulingOutcome.accepted ||
        !NotificationService.instance.isWorkCurrent) {
      return;
    }

    // Pregnancy/nifas hardening (2026-10-21, proposed): the feed entry
    // carries the plan's fireAt and stays hidden until then — it used to
    // appear as "Just now" the moment the reminder was SCHEDULED (e.g.
    // "about 5 days remain in nifas" on the birth day). The entry id
    // still embeds fireAt, and upsertScheduled replaces this slot's
    // not-yet-fired entry, so neither an unchanged plan nor a reschedule
    // adds a second entry. Fired entries are history and stay.
    final logEntryId = '${id}_${plan.fireAt.millisecondsSinceEpoch}';
    final type =
        typeOverride ??
        switch (id) {
          fertilityReminderId => NotificationType.fertility,
          NotificationScheduler.cycleNotificationId => NotificationType.cycle,
          NotificationScheduler.nifasNotificationId ||
          NotificationScheduler.pregnancyNotificationId =>
            NotificationType.pregnancy,
          _ => NotificationType.wellbeing,
        };

    await NotificationLogController.instance.upsertScheduled(
      '$id',
      NotificationLogEntry(
        id: logEntryId,
        type: type,
        titleAr: plan.feedTitleAr,
        bodyAr: plan.feedBodyAr,
        titleEn: plan.feedTitleEn,
        bodyEn: plan.feedBodyEn,
        createdAt: AppClock.now(),
        fireAt: plan.fireAt,
        target: target,
      ),
    );
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// The synced `pregnancy_profile` read for one refresh: [failed] means the
/// read itself failed ("unknown"), distinct from a verified absent row.
class _ProfileRead {
  const _ProfileRead.none() : profile = null, failed = false;
  const _ProfileRead.loaded(this.profile) : failed = false;
  const _ProfileRead.failed() : profile = null, failed = true;

  final PregnancyProfile? profile;
  final bool failed;
}
