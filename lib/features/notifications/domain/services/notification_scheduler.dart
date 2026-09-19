import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../../cycle_tracking/domain/entities/bleeding_episode.dart';
import '../../../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../../../pregnancy_profile/domain/entities/pregnancy_profile.dart';
import '../../../pregnancy_profile/domain/services/pregnancy_status_engine.dart';

/// What to schedule — pure data, no plugin dependency, easy to test.
class PlannedNotification extends Equatable {
  const PlannedNotification({
    required this.id,
    required this.fireAt,
    required this.titleAr,
    required this.bodyAr,
    required this.titleEn,
    required this.bodyEn,
    this.payload,
  });

  final int id;
  final DateTime fireAt;
  final String titleAr;
  final String bodyAr;
  final String titleEn;
  final String bodyEn;

  /// Commit E7 — opaque data carried through to a tap, letting the app
  /// route to the correct account/episode/day rather than merely
  /// reopening to whatever screen was last shown. Null for every
  /// notification type that predates tap-routing (cycle/pregnancy/nifas/
  /// wellbeing) — those still just open the app.
  final String? payload;

  @override
  List<Object?> get props => [
    id,
    fireAt,
    titleAr,
    bodyAr,
    titleEn,
    bodyEn,
    payload,
  ];
}

/// Pure planners — given real state (already fetched by the caller) and
/// "now", decide *what* notification should fire *when*, or nothing at
/// all. No side effects, no plugin calls — [NotificationRefreshCoordinator]
/// is what actually schedules these. Reuses the existing engines
/// ([CycleCalculationService], [PregnancyStatusEngine]) rather than
/// re-deriving cycle/pregnancy/nifas math.
class NotificationScheduler {
  const NotificationScheduler._();

  static const cycleNotificationId = 101;
  static const pregnancyNotificationId = 102;
  static const nifasNotificationId = 103;

  static const cycleLeadDays = 3;
  static const nifasWarningDay = 35;
  static const nifasWindowDays = 40;

  /// Predicted next period start = last haid start + average cycle length;
  /// plans a reminder [cycleLeadDays] before that, at 9am.
  static PlannedNotification? planCycleReminder({
    required CycleCalculationResult calculation,
    required DateTime now,
  }) {
    if (!calculation.hasSufficientHistory) return null;

    final predictedStart = calculation.lastHaidStart!.add(
      Duration(days: calculation.averageCycleLength!),
    );
    final fireDay = DateTime(
      predictedStart.year,
      predictedStart.month,
      predictedStart.day,
    ).subtract(const Duration(days: cycleLeadDays));
    final fireAt = fireDay.add(const Duration(hours: 9));

    if (!fireAt.isAfter(now)) return null;

    return PlannedNotification(
      id: cycleNotificationId,
      fireAt: fireAt,
      titleAr: 'اقترب موعد دورتكِ',
      bodyAr: 'دورتكِ الشهرية متوقعة خلال $cycleLeadDays أيام تقريباً.',
      titleEn: 'Your period may be approaching',
      bodyEn: 'Your next period is predicted in about $cycleLeadDays days.',
    );
  }

  /// Finds the next day (within a week) the pregnancy engine reports a
  /// higher week number than today, by probing the same engine forward
  /// day-by-day — reuses [PregnancyStatusEngine] as a black box rather
  /// than re-deriving which tracking basis maps to which date math.
  static PlannedNotification? planPregnancyMilestone({
    required PregnancyProfile? profile,
    required DateTime now,
  }) {
    final current = PregnancyStatusEngine.getStatus(profile, now);
    if (current.mode != PregnancyMode.pregnant || current.week == null) {
      return null;
    }

    final today = DateTime(now.year, now.month, now.day);
    for (var offset = 1; offset <= 7; offset++) {
      final candidateDay = today.add(Duration(days: offset));
      final candidateStatus = PregnancyStatusEngine.getStatus(
        profile,
        candidateDay,
      );
      if (candidateStatus.mode == PregnancyMode.pregnant &&
          candidateStatus.week != null &&
          candidateStatus.week! > current.week!) {
        final fireAt = candidateDay.add(const Duration(hours: 9));
        return PlannedNotification(
          id: pregnancyNotificationId,
          fireAt: fireAt,
          titleAr: 'مرحلة جديدة من الحمل',
          bodyAr: 'دخلتِ الأسبوع ${candidateStatus.week} من الحمل.',
          titleEn: 'A new pregnancy week',
          bodyEn: "You've entered week ${candidateStatus.week} of pregnancy.",
        );
      }
    }
    return null;
  }

  /// Plans a single warning near the end of the typical nifas window
  /// ([nifasWarningDay] of [nifasWindowDays]) — not a reminder for every
  /// day, just the one heads-up.
  static PlannedNotification? planNifasCountdown({
    required PregnancyProfile? profile,
    required DateTime now,
  }) {
    final current = PregnancyStatusEngine.getStatus(profile, now);
    if (current.mode != PregnancyMode.postpartum ||
        current.daysPostpartum == null) {
      return null;
    }

    final days = current.daysPostpartum!;
    if (days >= nifasWarningDay) return null;

    final today = DateTime(now.year, now.month, now.day);
    final fireAt = today
        .add(Duration(days: nifasWarningDay - days))
        .add(const Duration(hours: 9));
    if (!fireAt.isAfter(now)) return null;

    return PlannedNotification(
      id: nifasNotificationId,
      fireAt: fireAt,
      titleAr: 'اقترب انتهاء فترة النفاس',
      bodyAr:
          'تبقّى تقريباً ${nifasWindowDays - nifasWarningDay} أيام على انتهاء فترة النفاس المعتادة.',
      titleEn: 'Nifas is nearing its end',
      bodyEn:
          'About ${nifasWindowDays - nifasWarningDay} days remain in the typical nifas window.',
    );
  }
}

/// Menstrual Data Integrity charter, Commit E — ACTIVE_BLEEDING_CHECKIN.
/// Deliberately separate from [NotificationScheduler]: this is not a
/// *prediction* reminder (cycle/pregnancy/nifas are all "here's what's
/// likely coming"), it is a recurring factual question tied to a real
/// open episode, with its own eligibility, identity, and satisfaction
/// rules. Pure — no plugin dependency, no I/O — easy to test.
class ActiveBleedingReminderScheduler {
  const ActiveBleedingReminderScheduler._();

  /// Commit E1 — eligibility: an ended episode (or no episode at all) is
  /// never eligible, regardless of [ContinuationCertainty] — "I'm not
  /// sure" (uncertain) is still an OPEN episode and still eligible, since
  /// the question "are you still bleeding" remains genuinely open.
  static bool isEligible(BleedingEpisode? episode) =>
      episode != null && episode.lifecycleStatus == LifecycleStatus.open;

  /// Commit E5 — logical reminder identity: stable across repeated
  /// scheduler refreshes (app start/resume) for the same
  /// user+episode+local-calendar-day, so rescheduling never creates a
  /// duplicate (`NotificationService.scheduleAt` replaces whatever was
  /// already scheduled under the same id) — a *different* day or a
  /// *different* episode always gets a different id. Deliberately NOT
  /// `String.hashCode` (the Dart language spec does not guarantee that
  /// stays stable across SDK versions/app reinstalls — this must remain
  /// stable across a real app restart, not merely within one process);
  /// FNV-1a is a small, explicit, fully-owned definition instead.
  static int reminderId({
    required String userId,
    required String episodeId,
    required DateTime localDay,
  }) {
    final key =
        '$userId:$episodeId:'
        '${localDay.year}-${localDay.month.toString().padLeft(2, '0')}-'
        '${localDay.day.toString().padLeft(2, '0')}';
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(key)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    // flutter_local_notifications ids are platform 32-bit signed ints;
    // masking into the positive range avoids ever handing the plugin a
    // negative id.
    return hash & 0x7fffffff;
  }

  /// Commit E7 — an opaque payload the tap handler can parse to route to
  /// the correct account/episode/day, without needing to encode/decode
  /// anything Fiqh- or flow-related (Commit E3: the notification itself,
  /// and by extension this payload, carries no sensitive content).
  static String payloadFor({
    required String userId,
    required String episodeId,
    required DateTime localDay,
  }) => jsonEncode({
    'type': 'activeBleedingCheckin',
    'userId': userId,
    'episodeId': episodeId,
    'localDate':
        '${localDay.year}-${localDay.month.toString().padLeft(2, '0')}-'
        '${localDay.day.toString().padLeft(2, '0')}',
  });

  /// Commits E1/E2/E3/E5/E6: null when ineligible (E1), when the
  /// preference is disabled (checked by the caller before calling this —
  /// consistent with every other planner in this file, which only plans,
  /// never gates on consent itself), or when today's check-in obligation
  /// is already satisfied (E6 — [todaysObservationCount] > 0; a second
  /// manual observation later remains allowed, it just no longer needs a
  /// *reminder*). [leadHour]/[leadMinute] is the user's own preferred
  /// local time (falls back to a sensible default the caller supplies).
  static PlannedNotification? planDailyCheckin({
    required BleedingEpisode? episode,
    required int todaysObservationCount,
    required DateTime now,
    required int leadHour,
    required int leadMinute,
  }) {
    if (!isEligible(episode)) return null;
    if (todaysObservationCount > 0) return null;

    final episodeId = episode!.id;
    if (episodeId == null) return null;

    final today = DateTime(now.year, now.month, now.day);
    return _planForDay(
      userId: episode.userId,
      episodeId: episodeId,
      localDay: today,
      now: now,
      leadHour: leadHour,
      leadMinute: leadMinute,
    );
  }

  /// New critical finding — multi-day notification continuity. A client-
  /// only scheduler cannot rely on the app being reopened daily to plan
  /// each day's reminder one at a time (the prior architecture's own
  /// real gap: an active episode spanning several days with the app
  /// never reopened silently stopped getting reminders after the first
  /// day). This plans a BOUNDED rolling window of [daysAhead] local days
  /// — today through today + [daysAhead] - 1 — each as its own genuine,
  /// independently-scheduled, independently-cancellable OS notification
  /// (Commit E5's own per-day logical identity already made this
  /// possible; it was simply never exploited for more than one day at a
  /// time). Re-planned on every refresh (app start/resume): scheduling
  /// again under an unchanged id is a no-op replacement, so calling this
  /// repeatedly only ever extends the window forward, never duplicates.
  ///
  /// Only [todaysObservationCount] is ever known in advance — a future
  /// day's own obligation cannot be known before that day arrives, so
  /// every future day is optimistically scheduled; the next refresh that
  /// happens to occur once that day is "today" re-evaluates it exactly
  /// like any other day (and correctly omits/cancels it if by then it
  /// turns out to already be satisfied). This is the explicitly
  /// documented, honest limitation of a client-only scheduler: it cannot
  /// know a woman completed her check-in on a *different* device while
  /// this one stayed offline the whole window — cross-device
  /// instantaneous cancellation is not claimed.
  /// The single source of truth for how many local days ahead a rolling
  /// refresh plans, shared by [NotificationRefreshCoordinator] and every
  /// call site that must cancel a *whole* window's worth of ids (not
  /// just today's) — see [rollingWindowReminderIds].
  static const int defaultRollingWindowDays = 7;

  static List<PlannedNotification> planRollingDailyCheckins({
    required BleedingEpisode? episode,
    required int todaysObservationCount,
    required DateTime now,
    required int leadHour,
    required int leadMinute,
    int daysAhead = defaultRollingWindowDays,
  }) {
    if (!isEligible(episode)) return const [];
    final episodeId = episode!.id;
    if (episodeId == null) return const [];

    final today = DateTime(now.year, now.month, now.day);
    final plans = <PlannedNotification>[];
    for (var offset = 0; offset < daysAhead; offset++) {
      // E6 — only today's own obligation can actually be known yet.
      if (offset == 0 && todaysObservationCount > 0) continue;
      final localDay = today.add(Duration(days: offset));
      final plan = _planForDay(
        userId: episode.userId,
        episodeId: episodeId,
        localDay: localDay,
        now: now,
        leadHour: leadHour,
        leadMinute: leadMinute,
      );
      if (plan != null) plans.add(plan);
    }
    return plans;
  }

  /// New critical finding (notification continuity beyond 7 days) —
  /// every reminder id the rolling window *could* currently have
  /// scheduled, today through today + [daysAhead] - 1, regardless of
  /// whether each one actually got a [PlannedNotification] this refresh
  /// (a day already satisfied is skipped by [planRollingDailyCheckins]
  /// but may still be scheduled from an *earlier* refresh, before that
  /// day's own check-in existed). An explicit episode end must cancel
  /// the *entire* window it could have left behind, not only today's id
  /// — otherwise days 2-7's already-scheduled reminders would still
  /// fire for an episode that has since ended.
  static List<int> rollingWindowReminderIds({
    required String userId,
    required String episodeId,
    required DateTime today,
    int daysAhead = defaultRollingWindowDays,
  }) => List.generate(
    daysAhead,
    (offset) => reminderId(
      userId: userId,
      episodeId: episodeId,
      localDay: today.add(Duration(days: offset)),
    ),
  );

  /// New critical finding (notification continuity beyond 7 days) — the
  /// distinct payload for the OS-native recurring fallback (see
  /// [NotificationRefreshCoordinator.activeBleedingRecurringFallbackId]'s
  /// own doc comment for the full design). Deliberately carries no
  /// `localDate`: unlike [payloadFor], this same payload is handed to
  /// the OS once and re-delivered by the OS itself every day thereafter
  /// — there is no single date to bake in ahead of time. The tap
  /// handler must treat this type as always meaning "today," resolved
  /// at the moment of the tap, never compared against a stale embedded
  /// date the way [payloadFor]'s `localDate` is (Closure Blocker 9).
  static const String recurringFallbackType =
      'activeBleedingCheckinRecurringFallback';

  static String recurringFallbackPayloadFor({
    required String userId,
    required String episodeId,
  }) => jsonEncode({
    'type': recurringFallbackType,
    'userId': userId,
    'episodeId': episodeId,
  });

  static PlannedNotification? _planForDay({
    required String userId,
    required String episodeId,
    required DateTime localDay,
    required DateTime now,
    required int leadHour,
    required int leadMinute,
  }) {
    var fireAt = DateTime(
      localDay.year,
      localDay.month,
      localDay.day,
      leadHour,
      leadMinute,
    );
    if (!fireAt.isAfter(now)) {
      // New critical finding — this catch-up point must be STABLE
      // across repeated calls on the same day, derived only from the
      // preferred time itself, never from `now`: the prior
      // `now.add(const Duration(minutes: 1))` recomputed a fresh, later
      // value on every single refresh, so a woman who opened (or the OS
      // resumed) the app more than once after her preferred time had
      // already passed would see the same reminder pushed later and
      // later, potentially never actually firing. A fixed, generous
      // buffer past the preferred time — not a fixed clock hour, which
      // could itself precede an unusually late preferred time — keeps
      // "still worth a same-day prompt" true while every repeated call
      // on the same day computes the exact same value. Only ever applies
      // to "today" (a future day's own preferred time is always still
      // ahead of `now`, so this branch never triggers for one).
      fireAt = fireAt.add(const Duration(hours: 3));
      if (!fireAt.isAfter(now)) {
        // Even the fixed catch-up point is already behind real `now`
        // (very late in the day) — no further same-day reminder; the
        // next local day's own already-rolling-scheduled reminder (see
        // [planRollingDailyCheckins]) is the genuine next touchpoint,
        // not another invented "soon" time for a day that's nearly over.
        return null;
      }
    }

    return PlannedNotification(
      id: reminderId(userId: userId, episodeId: episodeId, localDay: localDay),
      fireAt: fireAt,
      // Commit E3 — deliberately discreet: no "bleeding," no flow, no
      // Madhhab/Fiqh word appears in default lock-screen text.
      titleAr: 'نِسواه',
      bodyAr: 'حان وقت متابعتكِ اليومية.',
      titleEn: 'Niswah',
      bodyEn: 'Time for your daily check-in.',
      payload: payloadFor(
        userId: userId,
        episodeId: episodeId,
        localDay: localDay,
      ),
    );
  }
}
