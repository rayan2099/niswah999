// Pregnancy/notifications hardening (2026-10-21) — regression test for
// finding 6: the dashboard's trimester label follows the engine's ACOG
// rule (≤13 / ≤27). The Nutfah/Alaqah/Mudghah labels follow the classical
// stage mapping (three 40-day stages from conception; decided 2026-10-21,
// pending scholar confirmation — see classical_stage_mapping_test.dart),
// so the trimester label shows only once those stages are over.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';

void main() {
  const labels = {
    1: 'First trimester',
    2: 'Second trimester',
    3: 'Third trimester',
  };

  test(
    'every week after the classical stages matches the engine trimester',
    () {
      // Week 20 starts at gestational day 140 = conception day 126 (> 120).
      for (var week = 20; week <= 42; week++) {
        expect(
          pregnancyStageFor(week, isArabic: false).$1,
          labels[PregnancyStatusEngine.trimesterForWeek(week)],
          reason: 'week $week',
        );
      }
    },
  );

  test('ACOG boundaries', () {
    // Weeks 13/14 are inside the classical Alaqah/Mudghah stages now, so
    // the 13/14 boundary is checked on the engine directly.
    expect(PregnancyStatusEngine.trimesterForWeek(13), 1);
    expect(PregnancyStatusEngine.trimesterForWeek(14), 2);
    expect(pregnancyStageFor(27, isArabic: false).$1, 'Second trimester');
    expect(pregnancyStageFor(28, isArabic: false).$1, 'Third trimester');
    expect(pregnancyStageFor(20, isArabic: true).$1, 'الثلث الثاني');
  });

  test('size buckets are unchanged', () {
    expect(pregnancyStageFor(4, isArabic: false).$2, 'Size of a poppy seed');
    expect(pregnancyStageFor(16, isArabic: false).$2, 'Size of an avocado');
    expect(pregnancyStageFor(27, isArabic: false).$2, 'Size of a watermelon');
  });
}
