// Pregnancy/notifications hardening (2026-10-21) — regression test for
// finding 6: the dashboard's trimester label follows the engine's ACOG
// rule (≤13 / ≤27). The Nutfah/Alaqah/Mudghah labels for weeks 1–12 are
// deliberately unchanged (flagged for scholar review).
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';

void main() {
  const labels = {
    1: 'First trimester',
    2: 'Second trimester',
    3: 'Third trimester',
  };

  test('every week from 13 to 42 matches the engine trimester', () {
    for (var week = 13; week <= 42; week++) {
      expect(
        pregnancyStageFor(week, isArabic: false).$1,
        labels[PregnancyStatusEngine.trimesterForWeek(week)],
        reason: 'week $week',
      );
    }
  });

  test('ACOG boundaries', () {
    expect(pregnancyStageFor(13, isArabic: false).$1, 'First trimester');
    expect(pregnancyStageFor(14, isArabic: false).$1, 'Second trimester');
    expect(pregnancyStageFor(27, isArabic: false).$1, 'Second trimester');
    expect(pregnancyStageFor(28, isArabic: false).$1, 'Third trimester');
    expect(pregnancyStageFor(14, isArabic: true).$1, 'الثلث الثاني');
  });

  test('weeks 1-12 stage labels and the size buckets are unchanged', () {
    expect(pregnancyStageFor(4, isArabic: false), (
      'Nutfah stage',
      'Size of a poppy seed',
    ));
    expect(pregnancyStageFor(8, isArabic: false).$1, 'Alaqah stage');
    expect(pregnancyStageFor(12, isArabic: true).$1, 'مرحلة المضغة');
    expect(pregnancyStageFor(16, isArabic: false).$2, 'Size of an avocado');
    expect(pregnancyStageFor(27, isArabic: false).$2, 'Size of a watermelon');
  });
}
