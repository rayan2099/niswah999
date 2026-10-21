// Scholar-review item (a), decided 2026-10-21 by the team at the owner's
// request as a conservative default — PENDING SCHOLAR CONFIRMATION. The
// Nutfah/Alaqah/Mudghah labels follow the hadith of Ibn Mas'ud (Bukhari
// 3208, Muslim 2643), read as three 40-day stages from conception:
// days since conception = gestational days − 14; Nutfah 0–40, Alaqah
// 41–80, Mudghah 81–120; no classical label otherwise (trimester only).
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';

ClassicalEmbryoStage? _stage(int gestationalDays) =>
    PregnancyStatusEngine.classicalStageForGestationalDays(gestationalDays);

void main() {
  test('boundaries in gestational days (conception day + 14)', () {
    expect(_stage(13), isNull, reason: 'before conception');
    expect(_stage(14), ClassicalEmbryoStage.nutfah, reason: 'conception 0');
    expect(_stage(54), ClassicalEmbryoStage.nutfah, reason: 'conception 40');
    expect(_stage(55), ClassicalEmbryoStage.alaqah, reason: 'conception 41');
    expect(_stage(94), ClassicalEmbryoStage.alaqah, reason: 'conception 80');
    expect(_stage(95), ClassicalEmbryoStage.mudghah, reason: 'conception 81');
    expect(_stage(134), ClassicalEmbryoStage.mudghah, reason: 'conception 120');
    expect(_stage(135), isNull, reason: 'conception 121: trimester only');
  });

  test('dashboard labels at the boundaries', () {
    String label(int days, {bool ar = false}) =>
        pregnancyStageFor(days ~/ 7, isArabic: ar, gestationalDays: days).$1;
    expect(label(13), 'First trimester');
    expect(label(14), 'Nutfah stage');
    expect(label(54), 'Nutfah stage');
    expect(label(55), 'Alaqah stage');
    expect(label(94), 'Alaqah stage');
    expect(label(95), 'Mudghah stage');
    expect(label(134), 'Mudghah stage');
    expect(label(135), 'Second trimester'); // week 19
    expect(label(54, ar: true), 'مرحلة النطفة');
    expect(label(55, ar: true), 'مرحلة العلقة');
    expect(label(95, ar: true), 'مرحلة المضغة');
  });

  test('without a precise age the first day of the week is used', () {
    // Week 4 = day 28 = conception day 14; week 8 = day 56 = conception 42.
    expect(pregnancyStageFor(4, isArabic: false).$1, 'Nutfah stage');
    expect(pregnancyStageFor(8, isArabic: false).$1, 'Alaqah stage');
    expect(pregnancyStageFor(12, isArabic: false).$1, 'Alaqah stage');
    expect(pregnancyStageFor(14, isArabic: false).$1, 'Mudghah stage');
    expect(pregnancyStageFor(19, isArabic: false).$1, 'Mudghah stage');
    expect(pregnancyStageFor(20, isArabic: false).$1, 'Second trimester');
  });
}
