import '../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

/// Single source of truth for the short, user-facing text describing each
/// madhhab's Haid duration rules. Built on top of
/// [MadhhabRuleEvaluator.minimumHaidFor]/[maximumHaidFor] — the exact
/// values the engine itself uses to classify a logged cycle — so this text
/// can never silently drift from what Niswah actually computes. Before
/// this file existed, onboarding, Settings, and the resolution screen each
/// hand-typed their own copy of these numbers independently, and two of
/// the three disagreed with the engine for Maliki (see git history: both
/// said "no minimum" while the engine enforces the same 24-hour minimum
/// as Shafi'i/Hanbali). This file does not change that engine behavior —
/// it only ensures the displayed text always matches it, whatever it is.
class MadhhabDescription {
  const MadhhabDescription({
    required this.madhhab,
    required this.nameEn,
    required this.nameAr,
    required this.shortRuleEn,
    required this.shortRuleAr,
    required this.longNoteEn,
    required this.longNoteAr,
  });

  final Madhhab madhhab;
  final String nameEn;
  final String nameAr;

  /// One short line, safe for a mobile grid tile — e.g. "24-hour min ·
  /// 15-day max". Never jurisprudential jargon.
  final String shortRuleEn;
  final String shortRuleAr;

  /// An extra sentence shown only on demand (e.g. via an "ⓘ" affordance),
  /// never on the grid itself — keeps the default view jargon-free per
  /// the UX requirement to avoid overwhelming users with Fiqh terminology.
  final String longNoteEn;
  final String longNoteAr;
}

/// Canonical display order for every Madhhab picker in the app. Onboarding
/// previously used Hanafi/Maliki/Shafii/Hanbali; Settings used Hanafi/
/// Shafii/Maliki/Hanbali. This order (Settings') is adopted as the single
/// standard because Settings' tile layout is the only one of the three
/// that was already fixed for 200%-text-scale overflow.
const List<Madhhab> kMadhhabDisplayOrder = [
  Madhhab.hanafi,
  Madhhab.shafii,
  Madhhab.maliki,
  Madhhab.hanbali,
];

/// Adversarial review, 2026-10-07: `<= 24` (not `< 24`) is deliberate —
/// an exactly-24-hour value (Shafi'i/Hanbali/Maliki's minimum) must stay
/// "24-hour", matching the established copy this file is meant to
/// unify toward, not silently become "1-day". Mathematically identical,
/// but "1-day min" is a readability regression nobody asked for; this
/// boundary is the one place that distinction is made, so every caller
/// gets it right without re-deriving it.
String _formatDuration(Duration d, {required bool arabic}) {
  if (d.inHours <= 24) {
    return arabic ? '${d.inHours} ساعة' : '${d.inHours}-hour';
  }
  final days = d.inHours / 24;
  final wholeDays = days.round();
  return arabic ? '$wholeDays يوماً' : '$wholeDays-day';
}

MadhhabDescription describeMadhhab(Madhhab madhhab) {
  final minimum = MadhhabRuleEvaluator.minimumHaidFor(madhhab);
  final maximum = MadhhabRuleEvaluator.maximumHaidFor(madhhab);
  final minEn = _formatDuration(minimum, arabic: false);
  final minAr = _formatDuration(minimum, arabic: true);
  final maxEn = _formatDuration(maximum, arabic: false);
  final maxAr = _formatDuration(maximum, arabic: true);

  final names = switch (madhhab) {
    Madhhab.hanafi => ('Hanafi', 'حنفي'),
    Madhhab.shafii => ("Shafi'i", 'شافعي'),
    Madhhab.maliki => ('Maliki', 'مالكي'),
    Madhhab.hanbali => ('Hanbali', 'حنبلي'),
  };

  final longNote = switch (madhhab) {
    Madhhab.maliki => (
      "Maliki also weighs your own typical ('āda) cycle pattern when "
          'classifying borderline days, alongside these general bounds.',
      'يأخذ المذهب المالكي أيضاً بعين الاعتبار عادتكِ المعتادة في الدورة '
          'عند تصنيف الأيام الحدّية، إلى جانب هذه الحدود العامة.',
    ),
    _ => (
      'These bounds decide whether bleeding counts as Haid for prayer '
          'and fasting rulings.',
      'تحدد هذه الحدود ما إذا كان النزيف يُحسب حيضاً لأحكام الصلاة والصيام.',
    ),
  };

  return MadhhabDescription(
    madhhab: madhhab,
    nameEn: names.$1,
    nameAr: names.$2,
    shortRuleEn: '$minEn min · $maxEn max',
    shortRuleAr: 'حد أدنى $minAr · حد أقصى $maxAr',
    longNoteEn: longNote.$1,
    longNoteAr: longNote.$2,
  );
}

const String kUnknownMadhhabLabelEn = "I don't know";
// The task's own text also accepts "غير متأكدة" as an equally valid
// Arabic label; "لا أعرف" is kept as the single canonical string so
// every screen renders identically, per Requirement 1.
const String kUnknownMadhhabLabelAr = 'لا أعرف';
