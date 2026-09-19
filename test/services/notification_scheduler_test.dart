import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

void main() {
  group('NotificationScheduler.planCycleReminder', () {
    test('insufficient history plans nothing', () {
      const calculation = CycleCalculationResult(
        haidStarts: [],
        currentCycleDay: null,
        averageCycleLength: null,
        cycleLengths: [],
      );

      final plan = NotificationScheduler.planCycleReminder(
        calculation: calculation,
        now: DateTime(2026, 1, 10),
      );

      expect(plan, isNull);
    });

    test('plans a reminder 3 days before the predicted next start', () {
      final calculation = CycleCalculationResult(
        haidStarts: [DateTime(2026, 1, 1), DateTime(2026, 1, 29)],
        currentCycleDay: 5,
        averageCycleLength: 28,
        cycleLengths: const [28],
      );

      final plan = NotificationScheduler.planCycleReminder(
        calculation: calculation,
        now: DateTime(2026, 1, 10),
      );

      // predicted next start = Jan 29 + 28 = Feb 26; lead day = Feb 23.
      expect(plan, isNotNull);
      expect(plan!.fireAt, DateTime(2026, 2, 23, 9));
    });

    test('a predicted date already in the past plans nothing', () {
      final calculation = CycleCalculationResult(
        haidStarts: [DateTime(2026, 1, 1), DateTime(2026, 1, 5)],
        currentCycleDay: 1,
        averageCycleLength: 4,
        cycleLengths: const [4],
      );

      final plan = NotificationScheduler.planCycleReminder(
        calculation: calculation,
        now: DateTime(2026, 6, 1),
      );

      expect(plan, isNull);
    });
  });

  group('NotificationScheduler.planPregnancyMilestone', () {
    test('not pregnant plans nothing', () {
      final plan = NotificationScheduler.planPregnancyMilestone(
        profile: null,
        now: DateTime(2026, 1, 10),
      );
      expect(plan, isNull);
    });

    test('finds the next weekly boundary within 7 days', () {
      // week = floor(daysSinceLmp / 7). lmp = Jan 1 => "now" Jan 10 is
      // 9 days in => week 1 (floor(9/7)=1). Week becomes 2 at day 14 =>
      // Jan 15, 4 days from "now".
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'u1',
        trackingBasis: TrackingBasis.lmp,
        referenceDate: DateTime(2026, 1, 1),
      );

      final plan = NotificationScheduler.planPregnancyMilestone(
        profile: profile,
        now: DateTime(2026, 1, 10),
      );

      expect(plan, isNotNull);
      expect(plan!.fireAt, DateTime(2026, 1, 15, 9));
      expect(plan.bodyAr, contains('2'));
    });

    test(
      'postpartum profile plans nothing here (handled by nifas planner)',
      () {
        final profile = PregnancyProfile(
          id: 'p1',
          userId: 'u1',
          isPostpartum: true,
          postpartumStartDate: DateTime(2026, 1, 1),
        );

        final plan = NotificationScheduler.planPregnancyMilestone(
          profile: profile,
          now: DateTime(2026, 1, 10),
        );

        expect(plan, isNull);
      },
    );
  });

  group('NotificationScheduler.planNifasCountdown', () {
    test('not postpartum plans nothing', () {
      final plan = NotificationScheduler.planNifasCountdown(
        profile: null,
        now: DateTime(2026, 1, 10),
      );
      expect(plan, isNull);
    });

    test('plans a warning for day 35 when currently before it', () {
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'u1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 1, 1),
      );

      // now (Jan 10) - start (Jan 1) = 9 days postpartum (date difference,
      // not calendar day count). 35 - 9 = 26 more days => Feb 5.
      final plan = NotificationScheduler.planNifasCountdown(
        profile: profile,
        now: DateTime(2026, 1, 10),
      );

      expect(plan, isNotNull);
      expect(plan!.fireAt, DateTime(2026, 2, 5, 9));
    });

    test('past the warning day plans nothing', () {
      final profile = PregnancyProfile(
        id: 'p1',
        userId: 'u1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 1, 1),
      );

      // day 38 postpartum — already past the day-35 warning threshold.
      final plan = NotificationScheduler.planNifasCountdown(
        profile: profile,
        now: DateTime(2026, 2, 7),
      );

      expect(plan, isNull);
    });
  });

  group('ActiveBleedingReminderScheduler (Commit E1/E5/E6/E7)', () {
    BleedingEpisode openEpisode({
      LifecycleStatus lifecycleStatus = LifecycleStatus.open,
      ContinuationCertainty? continuationCertainty =
          ContinuationCertainty.confirmed,
    }) => BleedingEpisode(
      id: 'episode-1',
      userId: 'user-1',
      lifecycleStatus: lifecycleStatus,
      continuationCertainty: continuationCertainty,
      startDate: DateTime(2026, 9, 10),
      startPrecision: ObservationPrecision.dateOnly,
      startSource: ObservationSource.userObserved,
      endDate: lifecycleStatus == LifecycleStatus.ended
          ? DateTime(2026, 9, 12)
          : null,
      endPrecision: lifecycleStatus == LifecycleStatus.ended
          ? ObservationPrecision.dateOnly
          : null,
      endSource: lifecycleStatus == LifecycleStatus.ended
          ? ObservationSource.userObserved
          : null,
    );

    group('isEligible (E1)', () {
      test('an open, confirmed episode is eligible', () {
        expect(
          ActiveBleedingReminderScheduler.isEligible(openEpisode()),
          isTrue,
        );
      });

      test('an open, uncertain episode is still eligible', () {
        expect(
          ActiveBleedingReminderScheduler.isEligible(
            openEpisode(continuationCertainty: ContinuationCertainty.uncertain),
          ),
          isTrue,
        );
      });

      test('an ended episode is never eligible', () {
        expect(
          ActiveBleedingReminderScheduler.isEligible(
            openEpisode(
              lifecycleStatus: LifecycleStatus.ended,
              continuationCertainty: null,
            ),
          ),
          isFalse,
        );
      });

      test('no episode at all is never eligible', () {
        expect(ActiveBleedingReminderScheduler.isEligible(null), isFalse);
      });
    });

    group('reminderId (E5 — logical identity)', () {
      test('is stable for the same user+episode+day across calls', () {
        final first = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: DateTime(2026, 9, 15),
        );
        final second = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: DateTime(2026, 9, 15),
        );
        expect(first, second);
      });

      test('differs for a different local day', () {
        final day15 = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: DateTime(2026, 9, 15),
        );
        final day16 = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: DateTime(2026, 9, 16),
        );
        expect(day15, isNot(day16));
      });

      test('differs for a different episode (same user, same day)', () {
        final episodeA = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-A',
          localDay: DateTime(2026, 9, 15),
        );
        final episodeB = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-B',
          localDay: DateTime(2026, 9, 15),
        );
        expect(episodeA, isNot(episodeB));
      });

      test('differs for a different user (same episode id, same day)', () {
        final userA = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-A',
          episodeId: 'episode-1',
          localDay: DateTime(2026, 9, 15),
        );
        final userB = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-B',
          episodeId: 'episode-1',
          localDay: DateTime(2026, 9, 15),
        );
        expect(userA, isNot(userB));
      });

      test('is always a valid non-negative platform notification id', () {
        final id = ActiveBleedingReminderScheduler.reminderId(
          userId: 'user-1',
          episodeId: 'episode-1',
          localDay: DateTime(2026, 9, 15),
        );
        expect(id, greaterThanOrEqualTo(0));
      });
    });

    group('planDailyCheckin (E1/E3/E6/E7)', () {
      test('ineligible episode plans nothing', () {
        final plan = ActiveBleedingReminderScheduler.planDailyCheckin(
          episode: openEpisode(
            lifecycleStatus: LifecycleStatus.ended,
            continuationCertainty: null,
          ),
          todaysObservationCount: 0,
          now: DateTime(2026, 9, 15, 10),
          leadHour: 18,
          leadMinute: 0,
        );
        expect(plan, isNull);
      });

      test("E6: today's obligation already satisfied plans nothing, even "
          'though a second manual observation later that day would still '
          'be allowed by the write path itself', () {
        final plan = ActiveBleedingReminderScheduler.planDailyCheckin(
          episode: openEpisode(),
          todaysObservationCount: 1,
          now: DateTime(2026, 9, 15, 10),
          leadHour: 18,
          leadMinute: 0,
        );
        expect(plan, isNull);
      });

      test(
        'plans at the preferred local time when that time is still ahead',
        () {
          final plan = ActiveBleedingReminderScheduler.planDailyCheckin(
            episode: openEpisode(),
            todaysObservationCount: 0,
            now: DateTime(2026, 9, 15, 10, 0),
            leadHour: 18,
            leadMinute: 0,
          );
          expect(plan, isNotNull);
          expect(plan!.fireAt, DateTime(2026, 9, 15, 18, 0));
        },
      );

      test('Closure Blocker 7: a genuinely custom preferred time (not the '
          '18:00 default) is honored exactly — proves this is a real, '
          'user-choosable preference the scheduler actually reads, not a '
          'hardcoded constant', () {
        final plan = ActiveBleedingReminderScheduler.planDailyCheckin(
          episode: openEpisode(),
          todaysObservationCount: 0,
          now: DateTime(2026, 9, 15, 6, 0),
          leadHour: 7,
          leadMinute: 45,
        );
        expect(plan, isNotNull);
        expect(plan!.fireAt, DateTime(2026, 9, 15, 7, 45));
      });

      test('still plans something today (soon) rather than skipping to '
          'tomorrow when the preferred time has already passed and '
          "nothing is recorded yet — a missed reminder time is not the "
          'same as a satisfied obligation', () {
        final now = DateTime(2026, 9, 15, 20, 0);
        final plan = ActiveBleedingReminderScheduler.planDailyCheckin(
          episode: openEpisode(),
          todaysObservationCount: 0,
          now: now,
          leadHour: 18,
          leadMinute: 0,
        );
        expect(plan, isNotNull);
        expect(plan!.fireAt.isAfter(now), isTrue);
        expect(
          plan.fireAt.year == now.year &&
              plan.fireAt.month == now.month &&
              plan.fireAt.day == now.day,
          isTrue,
          reason: 'still today, not deferred to tomorrow',
        );
      });

      test(
        'E3: the default copy never mentions bleeding, flow, or Fiqh terms',
        () {
          final plan = ActiveBleedingReminderScheduler.planDailyCheckin(
            episode: openEpisode(),
            todaysObservationCount: 0,
            now: DateTime(2026, 9, 15, 10),
            leadHour: 18,
            leadMinute: 0,
          )!;
          for (final text in [
            plan.titleEn,
            plan.bodyEn,
            plan.titleAr,
            plan.bodyAr,
          ]) {
            expect(text.toLowerCase(), isNot(contains('bleeding')));
            expect(text.toLowerCase(), isNot(contains('flow')));
            expect(text.toLowerCase(), isNot(contains('haid')));
            expect(text.toLowerCase(), isNot(contains('fiqh')));
          }
        },
      );

      test('E7: the payload carries a routable user+episode+day, decodable '
          'back to exactly those values', () {
        final plan = ActiveBleedingReminderScheduler.planDailyCheckin(
          episode: openEpisode(),
          todaysObservationCount: 0,
          now: DateTime(2026, 9, 15, 10),
          leadHour: 18,
          leadMinute: 0,
        )!;
        final decoded = jsonDecode(plan.payload!) as Map<String, dynamic>;
        expect(decoded['type'], 'activeBleedingCheckin');
        expect(decoded['userId'], 'user-1');
        expect(decoded['episodeId'], 'episode-1');
        expect(decoded['localDate'], '2026-09-15');
      });
    });
  });
}
