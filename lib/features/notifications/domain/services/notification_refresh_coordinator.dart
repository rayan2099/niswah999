import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/notification_log_controller.dart';
import '../../../../core/services/notification_service.dart';
import '../../../cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import '../../../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../../../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../data/repositories/notification_repository_impl.dart';
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

  /// Commit E — a fixed default local time for the daily check-in
  /// reminder. A per-user preferred time is out of scope for this pass
  /// (the existing [NotificationPreference] model has no time-of-day
  /// field for any reminder type); documented here as a known,
  /// deliberately narrow gap rather than silently assumed richer.
  static const _activeBleedingReminderHour = 18;
  static const _activeBleedingReminderMinute = 0;

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
    final enabled =
        preferences[NotificationType.activeBleeding]?.enabled ?? false;
    if (!enabled || userId == null) {
      // Cancel-on-disable/no-session: never leaves a stale reminder
      // scheduled for a state (opted out, signed out) it no longer
      // applies to. The specific per-episode id isn't known here without
      // a fetch, but a disabled/no-session refresh has nothing eligible
      // to schedule regardless — [ActiveBleedingReminderScheduler.isEligible]
      // already returns false for a null episode, so simply not
      // scheduling (rather than tracking every historical id to cancel)
      // is sufficient: the OS never fires an id that was never scheduled
      // this session, and Commit E9's explicit end/signout cancellation
      // (wired at the call sites that actually know the episode id)
      // covers the "was already scheduled, now must stop" case.
      return;
    }

    final episode = await bleedingRepository.getOpenEpisode(userId);
    if (!ActiveBleedingReminderScheduler.isEligible(episode)) return;

    final episodeId = episode!.id;
    if (episodeId == null) return;

    final utcOffsetMinutes = now.timeZoneOffset.inMinutes;
    final today = BleedingEpisodeRepositoryImpl.localToday(utcOffsetMinutes);
    final observations = await bleedingRepository.getObservationsForEpisode(
      episodeId,
    );
    final todaysObservationCount = observations
        .where((o) => o.observedDate.isAtSameMomentAs(today))
        .length;

    final plan = ActiveBleedingReminderScheduler.planDailyCheckin(
      episode: episode,
      todaysObservationCount: todaysObservationCount,
      now: now,
      leadHour: _activeBleedingReminderHour,
      leadMinute: _activeBleedingReminderMinute,
    );

    if (plan == null) {
      // E6: today's obligation is already satisfied (or otherwise
      // ineligible) — cancel today's own id specifically, computed the
      // same stable way it would have been scheduled, so a check-in
      // completed *after* today's reminder already fired still cancels
      // the (now-moot) notification rather than leaving it dangling.
      final todaysId = ActiveBleedingReminderScheduler.reminderId(
        userId: userId,
        episodeId: episodeId,
        localDay: today,
      );
      await NotificationService.instance.cancel(todaysId);
      return;
    }

    await NotificationService.instance.scheduleAt(
      id: plan.id,
      title: AppLocaleController.instance.isArabic
          ? plan.titleAr
          : plan.titleEn,
      body: AppLocaleController.instance.isArabic ? plan.bodyAr : plan.bodyEn,
      when: plan.fireAt,
      payload: plan.payload,
    );

    // Commit E8 — event audit: scheduled. Mirrors [_apply]'s own
    // dedupe-by-id logic, and — like every other entry this controller
    // logs — never persists the notification body text as a *tracking*
    // record (the log entry above already needs body text to display
    // itself in the feed, which is an existing, accepted product
    // surface; this comment documents that no *additional*, hidden
    // tracking field carries anything more sensitive, e.g. flow/Madhhab).
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
    await NotificationService.instance.scheduleAt(
      id: id,
      title: isArabic ? plan.titleAr : plan.titleEn,
      body: isArabic ? plan.bodyAr : plan.bodyEn,
      when: plan.fireAt,
    );

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
}
