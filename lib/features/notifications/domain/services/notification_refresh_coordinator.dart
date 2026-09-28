import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/notification_log_controller.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/utils/app_clock.dart';
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
  }) async {
    // New critical finding (notification cancellation closure, Finding 3)
    // — every call site that recomputes/reschedules must trust a *fresh*
    // device zone, not whatever `tz.local` happened to be set to last.
    // Previously only `main.dart`'s own app-resume handler did this
    // itself before calling refresh(); the dashboard's contextual-consent
    // call site and this wave's new Settings-toggle call site did not,
    // leaving them exposed to exactly the stale-zone bug
    // `DeviceTimezone`'s own doc comment warns about. Centralizing it
    // here means every current and future caller gets it uniformly.
    await NotificationService.instance.refreshLocalTimezone(forceRefresh: true);

    final preferences =
        await (preferenceRepository ?? NotificationRepositoryImpl())
            .loadPreferences();
    // Fix 6 (regression-baseline reconciliation) — this previously read
    // the raw wall clock directly, which is exactly what made
    // notification_multi_day_continuity_test.dart's own expected-id
    // computation (necessarily also real-clock-based, with no way to
    // inject a fixed value) racy around a real local-midnight boundary.
    // AppClock is this codebase's own established test-injection point
    // for "now" everywhere else; this was the one outlier.
    final now = AppClock.now();

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
    final utcOffsetMinutes = now.timeZoneOffset.inMinutes;
    final today = BleedingEpisodeRepositoryImpl.localToday(utcOffsetMinutes);

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
    final episodeResult = await bleedingRepository.getOpenEpisode(userId);
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
        .pendingActiveBleedingReminders();
    final desiredIds = plans.map((p) => p.id).toSet();
    for (final owned in pending) {
      if (owned.userId != userId || owned.episodeId != episodeId) continue;
      if (desiredIds.contains(owned.id)) continue;
      // New integrity finding — a failed cancellation must never be
      // recorded as a successful one; the notification may still be
      // live, and the audit trail must say so honestly, leaving it
      // visible for a later retry rather than a false "cancelled".
      final cancelled = await NotificationService.instance.cancel(owned.id);
      if (cancelled) {
        await _recordEventOnce(
          reminderId: owned.id.toString(),
          state: NotificationEventState.cancelled,
          userId: userId,
          episodeId: episodeId,
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
            createdAt: AppClock.now(),
          ),
        );
      }
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
        createdAt: AppClock.now(),
      ),
    );
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
