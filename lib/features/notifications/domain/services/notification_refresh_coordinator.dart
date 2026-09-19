import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/notification_log_controller.dart';
import '../../../../core/services/notification_service.dart';
import '../../../cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import '../../../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../../../cycle_tracking/domain/entities/bleeding_episode.dart';
import '../../../cycle_tracking/domain/entities/load_result.dart';
import '../../../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../data/local/notification_event_log_store.dart';
import '../../data/repositories/notification_repository_impl.dart';
import '../entities/notification_event.dart';
import '../entities/notification_preference.dart';
import 'notification_scheduler.dart';

/// The side-effecting glue between real app state and
/// [NotificationService] — loads preferences + real data, asks the pure
/// [NotificationScheduler] planners what should fire, and (re)schedules
/// accordingly. Call at natural trigger points (app start, app resume) —
/// once scheduled, the OS owns delivery, so no background polling is
/// needed here.
class NotificationRefreshCoordinator {
  const NotificationRefreshCoordinator._();

  static const wellbeingReminderId = 104;
  static const _wellbeingReminderHour = 20;

  /// New critical finding (notification continuity beyond 7 days) — an
  /// OS-native RECURRING reminder (see [NotificationService.scheduleDaily],
  /// already used for [wellbeingReminderId]): scheduled once, it re-fires
  /// every day at the preferred time indefinitely, without the app ever
  /// needing to reopen and re-plan — unlike the rolling window below, it
  /// only ever consumes a SINGLE slot of iOS's shared 64-pending-
  /// notification budget, no matter how long the episode lasts.
  ///
  /// This does not replace [_rollingWindowDays]'s own exact, per-day-
  /// aware reminders — it is a deliberately cruder long-horizon fallback
  /// for the specific case the rolling window cannot cover on its own:
  /// the app never being reopened for longer than the window. Two real
  /// limitations, both honestly disclosed rather than silently accepted
  /// as "full continuity": (1) the OS fires it regardless of whether
  /// that day's check-in is already done — it cannot consult app state
  /// (E6's per-day suppression only applies within the rolling window);
  /// (2) its payload cannot embed which specific date it will fire on
  /// (the OS re-delivers the same payload every day), so a tap always
  /// routes to whatever "today" genuinely is at the moment of the tap —
  /// see [recurringFallbackType]'s own doc comment and
  /// `DashboardScreen._consumeNotificationTap`.
  ///
  /// Exact supported horizon, stated plainly: per-day-aware reminders
  /// (skip-if-already-done, tap routes to that specific date) are
  /// guaranteed for [_rollingWindowDays] days without reopening. Beyond
  /// that, if still never reopened, a daily nudge continues indefinitely
  /// via this recurring fallback — but without the rolling window's own
  /// precision. This is NOT a claim of indefinite exact daily tracking —
  /// it is a bounded exact window plus an indefinite coarse nudge.
  static const activeBleedingRecurringFallbackId = 105;

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
  /// any [_rollingWindowDays]-day stretch — and, beyond that, the
  /// [activeBleedingRecurringFallbackId] mechanism above still delivers a
  /// daily nudge indefinitely (with the honestly-disclosed precision
  /// tradeoff its own doc comment states). A single shared constant
  /// ([ActiveBleedingReminderScheduler.defaultRollingWindowDays]) so
  /// every call site that must cancel a whole window's ids — not only
  /// the scheduling call site — stays in agreement about its size.
  static const _rollingWindowDays =
      ActiveBleedingReminderScheduler.defaultRollingWindowDays;

  static Future<void> refresh({
    required String? userId,
    CycleTrackingRepositoryImpl? cycleRepository,
    PregnancyProfileRepository? pregnancyRepository,
    NotificationRepositoryImpl? preferenceRepository,
    BleedingEpisodeRepositoryImpl? bleedingRepository,
  }) async {
    final preferences =
        await (preferenceRepository ?? NotificationRepositoryImpl())
            .loadPreferences();
    final now = DateTime.now();

    await _refreshCycle(
      preferences: preferences,
      cycleRepository: cycleRepository ?? CycleTrackingRepositoryImpl(),
      now: now,
    );
    await _refreshPregnancyAndNifas(
      preferences: preferences,
      userId: userId,
      pregnancyRepository: pregnancyRepository ?? PregnancyProfileRepository(),
      now: now,
    );
    await _refreshWellbeingDaily(preferences: preferences);
    await _refreshActiveBleeding(
      preferences: preferences,
      userId: userId,
      bleedingRepository: bleedingRepository ?? BleedingEpisodeRepositoryImpl(),
      now: now,
    );
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
    if (!enabled || userId == null) {
      // Cancel-on-disable/no-session: never leaves a stale reminder
      // scheduled for a state (opted out, signed out) it no longer
      // applies to. The specific per-day ids aren't known here without a
      // fetch, but [ActiveBleedingReminderScheduler.isEligible] already
      // returns false for a null episode, so simply not scheduling those
      // (rather than tracking every historical id to cancel) is
      // sufficient — the OS never fires an id that was never scheduled
      // this session, and Commit E9's explicit end/signout cancellation
      // (wired at the call sites that actually know the episode id)
      // covers the "was already scheduled, now must stop" case.
      //
      // The recurring fallback is different: it is a FIXED id (no
      // episode/day needed to compute it), and — being OS-native
      // recurring — it does not naturally stop like a one-off
      // notification does. It must be explicitly cancelled here.
      await NotificationService.instance.cancel(
        activeBleedingRecurringFallbackId,
      );
      return;
    }

    // Closure Blocker 1: a read failure must never be concluded as "no
    // open episode" — that would silently cancel/never-schedule a real,
    // still-open episode's reminder purely because the read hiccuped.
    // Leaving the refresh as a no-op (whatever was already scheduled
    // stays scheduled) is the honest response to "genuinely unknown" —
    // this includes the recurring fallback, left untouched here.
    final episodeResult = await bleedingRepository.getOpenEpisode(userId);
    if (episodeResult is LoadUnavailable<BleedingEpisode?>) return;
    final episode = episodeResult.dataOrNull;
    if (!ActiveBleedingReminderScheduler.isEligible(episode)) {
      await NotificationService.instance.cancel(
        activeBleedingRecurringFallbackId,
      );
      return;
    }

    final episodeId = episode!.id;
    if (episodeId == null) return;

    final utcOffsetMinutes = now.timeZoneOffset.inMinutes;
    final today = BleedingEpisodeRepositoryImpl.localToday(utcOffsetMinutes);
    final observationsResult = await bleedingRepository
        .getObservationsForEpisode(episodeId);
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

    // E6: if today's own obligation is already satisfied, the rolling
    // plan set above deliberately omits it (every other day the window
    // covers is still optimistically planned) — cancel today's own id
    // specifically, computed the same stable way it would have been
    // scheduled, so a check-in completed *after* today's reminder
    // already fired still cancels the (now-moot) notification rather
    // than leaving it dangling.
    final todaysId = ActiveBleedingReminderScheduler.reminderId(
      userId: userId,
      episodeId: episodeId,
      localDay: today,
    );
    final todaysPlanStillPending = plans.any((p) => p.id == todaysId);
    if (!todaysPlanStillPending) {
      // New integrity finding — a failed cancellation must never be
      // recorded as a successful one; the notification may still be
      // live, and the audit trail must say so honestly.
      final cancelled = await NotificationService.instance.cancel(todaysId);
      if (cancelled) {
        await _recordEventOnce(
          reminderId: todaysId.toString(),
          state: NotificationEventState.cancelled,
          userId: userId,
          episodeId: episodeId,
          logicalLocalDate: today,
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
      if (plan.id != todaysId) continue;
      final logEntryId = 'activeBleeding_${plan.id}';
      final alreadyLogged = NotificationLogController.instance.entries.any(
        (entry) => entry.id == logEntryId,
      );
      if (!alreadyLogged) {
        await NotificationLogController.instance.add(
          NotificationLogEntry(
            id: logEntryId,
            type: NotificationType.activeBleeding,
            titleAr: plan.titleAr,
            bodyAr: plan.bodyAr,
            titleEn: plan.titleEn,
            bodyEn: plan.bodyEn,
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    // New critical finding (notification continuity beyond 7 days) — the
    // long-horizon fallback: re-scheduling under the same fixed id every
    // refresh is idempotent (the OS replaces an unchanged recurring
    // schedule as a no-op), so this simply keeps the fallback aligned
    // with her current preferred time. Deliberately not routed through
    // [_recordEventOnce]/the structural audit log — that log's own
    // schema is keyed to one specific [logicalLocalDate] per event, which
    // this recurring, date-agnostic registration has no honest single
    // value for (see [ActiveBleedingReminderScheduler.recurringFallbackType]'s
    // own doc comment). Its correctness is instead covered directly by
    // this coordinator's own tests.
    await NotificationService.instance.scheduleDaily(
      id: activeBleedingRecurringFallbackId,
      title: AppLocaleController.instance.isArabic ? 'نِسواه' : 'Niswah',
      body: AppLocaleController.instance.isArabic
          ? 'حان وقت متابعتكِ اليومية.'
          : 'Time for your daily check-in.',
      hour: leadHour,
      minute: leadMinute,
      payload: ActiveBleedingReminderScheduler.recurringFallbackPayloadFor(
        userId: userId,
        episodeId: episodeId,
      ),
    );
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

  static Future<void> _refreshCycle({
    required Map<NotificationType, NotificationPreference> preferences,
    required CycleTrackingRepositoryImpl cycleRepository,
    required DateTime now,
  }) async {
    final enabled = preferences[NotificationType.cycle]?.enabled ?? false;
    if (!enabled) {
      await NotificationService.instance.cancel(
        NotificationScheduler.cycleNotificationId,
      );
      return;
    }

    final logs = await cycleRepository.getCycleLogs(limit: 1000);
    final calculation = const CycleCalculationService().calculate(
      logs,
      asOf: now,
    );
    final plan = NotificationScheduler.planCycleReminder(
      calculation: calculation,
      now: now,
    );
    await _apply(NotificationScheduler.cycleNotificationId, plan);
  }

  static Future<void> _refreshPregnancyAndNifas({
    required Map<NotificationType, NotificationPreference> preferences,
    required String? userId,
    required PregnancyProfileRepository pregnancyRepository,
    required DateTime now,
  }) async {
    final enabled = preferences[NotificationType.pregnancy]?.enabled ?? false;
    if (!enabled || userId == null) {
      await NotificationService.instance.cancel(
        NotificationScheduler.pregnancyNotificationId,
      );
      await NotificationService.instance.cancel(
        NotificationScheduler.nifasNotificationId,
      );
      return;
    }

    final profile = await pregnancyRepository.getForUser(userId);
    final pregnancyPlan = NotificationScheduler.planPregnancyMilestone(
      profile: profile,
      now: now,
    );
    await _apply(NotificationScheduler.pregnancyNotificationId, pregnancyPlan);

    final nifasPlan = NotificationScheduler.planNifasCountdown(
      profile: profile,
      now: now,
    );
    await _apply(NotificationScheduler.nifasNotificationId, nifasPlan);
  }

  static Future<void> _refreshWellbeingDaily({
    required Map<NotificationType, NotificationPreference> preferences,
  }) async {
    final enabled = preferences[NotificationType.wellbeing]?.enabled ?? false;
    if (!enabled) {
      await NotificationService.instance.cancel(wellbeingReminderId);
      return;
    }

    final isArabic = AppLocaleController.instance.isArabic;
    await NotificationService.instance.scheduleDaily(
      id: wellbeingReminderId,
      title: isArabic ? 'كيف حالكِ اليوم؟' : 'How are you feeling today?',
      body: isArabic
          ? 'خذي لحظة لتسجيل حالتكِ النفسية اليوم.'
          : 'Take a moment to log your wellbeing check-in today.',
      hour: _wellbeingReminderHour,
      minute: 0,
    );
  }

  static Future<void> _apply(int id, PlannedNotification? plan) async {
    if (plan == null) {
      await NotificationService.instance.cancel(id);
      return;
    }

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
    );
    if (outcome != NotificationSchedulingOutcome.accepted) return;

    // The same still-pending prediction gets rescheduled every refresh
    // (app start/resume) — that's fine for the OS scheduler (replacing a
    // notification under the same id is a no-op if unchanged), but it
    // must NOT re-add a log entry each time. The log-entry id embeds the
    // plan's fireAt, so an unchanged plan reuses the same id and this
    // simply skips re-adding.
    final logEntryId = '${id}_${plan.fireAt.millisecondsSinceEpoch}';
    final alreadyLogged = NotificationLogController.instance.entries.any(
      (entry) => entry.id == logEntryId,
    );
    if (alreadyLogged) return;

    final type = switch (id) {
      NotificationScheduler.cycleNotificationId => NotificationType.cycle,
      NotificationScheduler.nifasNotificationId ||
      NotificationScheduler.pregnancyNotificationId =>
        NotificationType.pregnancy,
      _ => NotificationType.wellbeing,
    };

    await NotificationLogController.instance.add(
      NotificationLogEntry(
        id: logEntryId,
        type: type,
        titleAr: plan.titleAr,
        bodyAr: plan.bodyAr,
        titleEn: plan.titleEn,
        bodyEn: plan.bodyEn,
        createdAt: DateTime.now(),
      ),
    );
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
