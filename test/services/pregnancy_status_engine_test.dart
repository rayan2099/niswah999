import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';

PregnancyProfile _profile({
  TrackingBasis? trackingBasis,
  DateTime? referenceDate,
  int? manualWeekValue,
  DateTime? manualWeekSetAt,
  bool isPostpartum = false,
  DateTime? postpartumStartDate,
}) {
  return PregnancyProfile(
    id: 'profile-1',
    userId: 'user-1',
    trackingBasis: trackingBasis,
    referenceDate: referenceDate,
    manualWeekValue: manualWeekValue,
    manualWeekSetAt: manualWeekSetAt,
    isPostpartum: isPostpartum,
    postpartumStartDate: postpartumStartDate,
  );
}

void main() {
  group('PregnancyStatusEngine — unknown mode', () {
    test('no profile at all', () {
      final status = PregnancyStatusEngine.getStatus(null, DateTime(2026, 1, 1));
      expect(status.mode, PregnancyMode.unknown);
    });

    test('tracking basis set but no reference date', () {
      final profile = _profile(trackingBasis: TrackingBasis.lmp);
      final status = PregnancyStatusEngine.getStatus(
        profile,
        DateTime(2026, 1, 1),
      );
      expect(status.mode, PregnancyMode.unknown);
    });

    test('manual_week without manual_week_set_at', () {
      final profile = _profile(
        trackingBasis: TrackingBasis.manualWeek,
        manualWeekValue: 10,
      );
      final status = PregnancyStatusEngine.getStatus(
        profile,
        DateTime(2026, 1, 1),
      );
      expect(status.mode, PregnancyMode.unknown);
    });

    test('postpartum flagged but no start date', () {
      final profile = _profile(isPostpartum: true);
      final status = PregnancyStatusEngine.getStatus(
        profile,
        DateTime(2026, 1, 1),
      );
      expect(status.mode, PregnancyMode.unknown);
    });
  });

  group('PregnancyStatusEngine — lmp basis', () {
    test('computes week/trimester/month/weeksToDue from LMP date', () {
      final lmp = DateTime(2025, 8, 1);
      final today = lmp.add(const Duration(days: 23 * 7 + 3));
      final profile = _profile(
        trackingBasis: TrackingBasis.lmp,
        referenceDate: lmp,
      );

      final status = PregnancyStatusEngine.getStatus(profile, today);

      expect(status.mode, PregnancyMode.pregnant);
      expect(status.week, 23);
      expect(status.trimester, 2);
      expect(status.weeksToDue, 17);
      expect(status.month, 6); // ceil(23 / 4.345)
    });
  });

  group('PregnancyStatusEngine — due_date basis', () {
    test('resolves due date to an effective LMP 280 days earlier', () {
      final lmp = DateTime(2025, 8, 1);
      final dueDate = lmp.add(const Duration(days: 280));
      final today = lmp.add(const Duration(days: 10 * 7));
      final profile = _profile(
        trackingBasis: TrackingBasis.dueDate,
        referenceDate: dueDate,
      );

      final status = PregnancyStatusEngine.getStatus(profile, today);

      expect(status.mode, PregnancyMode.pregnant);
      expect(status.week, 10);
      expect(status.trimester, 1);
    });
  });

  group('PregnancyStatusEngine — conception_date basis', () {
    test('resolves conception date to an effective LMP 14 days earlier', () {
      final lmp = DateTime(2025, 8, 1);
      final conceptionDate = lmp.add(const Duration(days: 14));
      final today = lmp.add(const Duration(days: 15 * 7));
      final profile = _profile(
        trackingBasis: TrackingBasis.conceptionDate,
        referenceDate: conceptionDate,
      );

      final status = PregnancyStatusEngine.getStatus(profile, today);

      expect(status.mode, PregnancyMode.pregnant);
      expect(status.week, 15);
      expect(status.trimester, 2);
    });
  });

  group('PregnancyStatusEngine — manual_week basis', () {
    test('recomputes week from elapsed days since manual_week_set_at', () {
      final setAt = DateTime(2026, 1, 1);
      final today = setAt.add(const Duration(days: 21)); // 3 weeks later
      final profile = _profile(
        trackingBasis: TrackingBasis.manualWeek,
        manualWeekValue: 10,
        manualWeekSetAt: setAt,
      );

      final status = PregnancyStatusEngine.getStatus(profile, today);

      expect(status.mode, PregnancyMode.pregnant);
      expect(status.week, 13);
    });

    test('same-day read returns the stated week unchanged', () {
      final setAt = DateTime(2026, 1, 1);
      final profile = _profile(
        trackingBasis: TrackingBasis.manualWeek,
        manualWeekValue: 10,
        manualWeekSetAt: setAt,
      );

      final status = PregnancyStatusEngine.getStatus(profile, setAt);

      expect(status.week, 10);
    });
  });

  group('PregnancyStatusEngine — clamping', () {
    test('clamps below week 1 up to 1', () {
      final lmp = DateTime(2026, 1, 1);
      final today = lmp.add(const Duration(days: 2)); // < 1 week elapsed
      final profile = _profile(
        trackingBasis: TrackingBasis.lmp,
        referenceDate: lmp,
      );

      final status = PregnancyStatusEngine.getStatus(profile, today);

      expect(status.week, 1);
    });

    test('clamps above week 42 down to 42', () {
      final lmp = DateTime(2025, 1, 1);
      final today = lmp.add(const Duration(days: 60 * 7)); // way overdue
      final profile = _profile(
        trackingBasis: TrackingBasis.lmp,
        referenceDate: lmp,
      );

      final status = PregnancyStatusEngine.getStatus(profile, today);

      expect(status.week, 42);
      expect(status.weeksToDue, 0);
    });
  });

  group('PregnancyStatusEngine — trimester boundaries', () {
    test('week 13 is trimester 1, week 14 is trimester 2', () {
      final lmp = DateTime(2026, 1, 1);
      final week13 = PregnancyStatusEngine.getStatus(
        _profile(trackingBasis: TrackingBasis.lmp, referenceDate: lmp),
        lmp.add(const Duration(days: 13 * 7)),
      );
      final week14 = PregnancyStatusEngine.getStatus(
        _profile(trackingBasis: TrackingBasis.lmp, referenceDate: lmp),
        lmp.add(const Duration(days: 14 * 7)),
      );

      expect(week13.trimester, 1);
      expect(week14.trimester, 2);
    });

    test('week 27 is trimester 2, week 28 is trimester 3', () {
      final lmp = DateTime(2026, 1, 1);
      final week27 = PregnancyStatusEngine.getStatus(
        _profile(trackingBasis: TrackingBasis.lmp, referenceDate: lmp),
        lmp.add(const Duration(days: 27 * 7)),
      );
      final week28 = PregnancyStatusEngine.getStatus(
        _profile(trackingBasis: TrackingBasis.lmp, referenceDate: lmp),
        lmp.add(const Duration(days: 28 * 7)),
      );

      expect(week27.trimester, 2);
      expect(week28.trimester, 3);
    });
  });

  group('PregnancyStatusEngine — postpartum mode', () {
    test('within 40 days is نفاس', () {
      final birth = DateTime(2026, 1, 1);
      final today = birth.add(const Duration(days: 39));
      final status = PregnancyStatusEngine.getStatus(
        _profile(isPostpartum: true, postpartumStartDate: birth),
        today,
      );

      expect(status.mode, PregnancyMode.postpartum);
      expect(status.daysPostpartum, 39);
      expect(status.phase, 'نفاس');
    });

    test('past 40 days is ما بعد النفاس', () {
      final birth = DateTime(2026, 1, 1);
      final today = birth.add(const Duration(days: 41));
      final status = PregnancyStatusEngine.getStatus(
        _profile(isPostpartum: true, postpartumStartDate: birth),
        today,
      );

      expect(status.mode, PregnancyMode.postpartum);
      expect(status.phase, 'ما بعد النفاس');
    });

    test('postpartum takes priority over any pregnancy tracking basis', () {
      final birth = DateTime(2026, 1, 1);
      final profile = PregnancyProfile(
        id: 'profile-1',
        userId: 'user-1',
        trackingBasis: TrackingBasis.lmp,
        referenceDate: DateTime(2025, 6, 1),
        isPostpartum: true,
        postpartumStartDate: birth,
      );

      final status = PregnancyStatusEngine.getStatus(
        profile,
        birth.add(const Duration(days: 5)),
      );

      expect(status.mode, PregnancyMode.postpartum);
    });
  });
}
