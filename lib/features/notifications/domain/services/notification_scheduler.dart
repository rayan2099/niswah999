import 'package:equatable/equatable.dart';

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
  });

  final int id;
  final DateTime fireAt;
  final String titleAr;
  final String bodyAr;
  final String titleEn;
  final String bodyEn;

  @override
  List<Object?> get props => [id, fireAt, titleAr, bodyAr, titleEn, bodyEn];
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
