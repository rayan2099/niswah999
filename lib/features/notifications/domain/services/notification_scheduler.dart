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
    var fireAt = DateTime(
      today.year,
      today.month,
      today.day,
      leadHour,
      leadMinute,
    );
    if (!fireAt.isAfter(now)) {
      // Already past today's preferred time and nothing recorded yet —
      // still worth a prompt today, just fire close to now rather than
      // waiting until tomorrow's slot (tomorrow's own refresh will plan
      // tomorrow's reminder once today's obligation is settled one way
      // or another).
      fireAt = now.add(const Duration(minutes: 1));
    }

    return PlannedNotification(
      id: reminderId(
        userId: episode.userId,
        episodeId: episodeId,
        localDay: today,
      ),
      fireAt: fireAt,
      // Commit E3 — deliberately discreet: no "bleeding," no flow, no
      // Madhhab/Fiqh word appears in default lock-screen text.
      titleAr: 'نِسواه',
      bodyAr: 'حان وقت متابعتكِ اليومية.',
      titleEn: 'Niswah',
      bodyEn: 'Time for your daily check-in.',
      payload: payloadFor(
        userId: episode.userId,
        episodeId: episodeId,
        localDay: today,
      ),
    );
  }
}
