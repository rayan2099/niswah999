import 'package:equatable/equatable.dart';

import '../../../../core/utils/calendar_days.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../entities/pregnancy_profile.dart';

enum PregnancyMode { pregnant, postpartum, unknown }

/// The classical stages named in the hadith of Ibn Mas'ud (Sahih
/// al-Bukhari 3208, Sahih Muslim 2643). See
/// [PregnancyStatusEngine.classicalStageForGestationalDays].
enum ClassicalEmbryoStage { nutfah, alaqah, mudghah }

/// Result of [PregnancyStatusEngine.getStatus] — the exact shape fed into
/// the chat's [CONTEXT] block. Never cache this across a session; recompute
/// on every chat turn (and at least once daily) from the stored profile.
class PregnancyStatus extends Equatable {
  const PregnancyStatus.unknown()
    : mode = PregnancyMode.unknown,
      week = null,
      trimester = null,
      month = null,
      weeksToDue = null,
      daysPostpartum = null,
      phase = null;

  const PregnancyStatus.pregnant({
    required this.week,
    required this.trimester,
    required this.month,
    required this.weeksToDue,
  }) : mode = PregnancyMode.pregnant,
       daysPostpartum = null,
       phase = null;

  const PregnancyStatus.postpartum({
    required this.daysPostpartum,
    required this.phase,
  }) : mode = PregnancyMode.postpartum,
       week = null,
       trimester = null,
       month = null,
       weeksToDue = null;

  final PregnancyMode mode;
  final int? week;
  final int? trimester;
  final int? month;
  final int? weeksToDue;
  final int? daysPostpartum;
  final String? phase;

  @override
  List<Object?> get props => [
    mode,
    week,
    trimester,
    month,
    weeksToDue,
    daysPostpartum,
    phase,
  ];
}

/// Pure pregnancy-week/postpartum engine backing the "طبيبة" chat's
/// personalization. Never derives a week from vague phrasing — only from
/// the explicit dates/values stored on [PregnancyProfile]. Returns
/// [PregnancyStatus.unknown] whenever required data is missing rather than
/// guessing, so the chat backend knows to ask instead of assume.
class PregnancyStatusEngine {
  const PregnancyStatusEngine._();

  /// The nifas window every surface shows, for every madhhab (decided
  /// 2026-10-21 by the team at the owner's request; fiqh basis pending
  /// scholar confirmation): day 0 (the logged birth date) through day 40.
  /// 40 days is the majority position and the shorter maximum, so prayer
  /// is never treated as lifted beyond day 40 on the app's own authority.
  static const int nifasWindowDays = 40;

  /// The longer maximum the Shafi'i and Maliki schools allow (60 days). It
  /// is never shown as a window: see [needsPostNifasScholarAdvisory].
  static const int extendedNifasMaxDays = 60;
  static const int _fullTermWeeks = 40;

  /// The ONE shared pregnancy-week range (2026-10-21, proposed): the engine,
  /// the server mirror (`pregnancy_status.ts`, MAX_WEEK = 42) and the
  /// on-device dashboard ([PregnancyStatusController.currentWeek]) all clamp
  /// to this — previously the dashboard capped at 40 while the chat,
  /// reports and notifications went to 42.
  static const int minWeek = 1;
  static const int maxWeek = 42;
  static const double _weeksPerMonth = 4.345; // ~average weeks per month

  /// [PregnancyStatus.phase] while inside the nifas window
  /// ([nifasWindowDays], day 0..40 inclusive), and after it. Numbering
  /// (decided 2026-10-21): days are counted 0-based from the logged birth
  /// date — the birth date is day 0 ("Birth day"), then day 1 … day 40.
  static const String nifasPhase = 'نفاس';
  static const String postNifasPhase = 'ما بعد النفاس';

  /// Elapsed calendar days since the logged birth date (0 on that day).
  /// Calendar-day arithmetic (DST-safe) on purpose: `postpartum_start_date`
  /// is a calendar date, not an instant.
  static int daysPostpartumOn(DateTime birthDate, DateTime today) =>
      calendarDaysBetween(birthDate, today);

  /// The single shared "is this day still inside the nifas window"
  /// definition, used by the reports, the notifications and the dashboard.
  static bool isWithinNifasWindow(int daysPostpartum) =>
      daysPostpartum <= nifasWindowDays;

  /// Whether [madhhab] allows nifas beyond [nifasWindowDays], up to
  /// [extendedNifasMaxDays] (Shafi'i and Maliki). Pending scholar
  /// confirmation.
  static bool madhhabAllowsExtendedNifas(Madhhab? madhhab) =>
      madhhab == Madhhab.shafii || madhhab == Madhhab.maliki;

  /// Decided 2026-10-21 (fiqh basis pending scholar confirmation): for a
  /// Shafi'i or Maliki user who is bleeding on day 41..60 after the logged
  /// birth date, Niswah states NO ruling — neither "nifas continues" nor
  /// "tahara, pray" — and shows a "please consult a scholar" advisory
  /// instead. Her school may still count this bleeding as nifas, while the
  /// Haid engine would otherwise rule on it as ordinary bleeding. The app
  /// does not model whether the bleeding is continuous from the birth or
  /// resumed after a clean gap, so any bleeding in that range gets the
  /// advisory (the conservative reading: no ruling either way). Hanafi and
  /// Hanbali (40-day maximum) and an unselected madhhab are unchanged.
  /// [isBleeding] is whether she is bleeding now (an open episode); null
  /// (unverifiable) is never treated as bleeding here — the evidence-
  /// unresolved state already states no ruling.
  static bool needsPostNifasScholarAdvisory({
    required int daysPostpartum,
    required Madhhab? madhhab,
    required bool? isBleeding,
  }) =>
      isBleeding == true &&
      madhhabAllowsExtendedNifas(madhhab) &&
      daysPostpartum > nifasWindowDays &&
      daysPostpartum <= extendedNifasMaxDays;

  /// The advisory shown wherever [needsPostNifasScholarAdvisory] holds (the
  /// dashboard and the fiqh report). States no ruling either way.
  static const postNifasAdvisoryEn =
      "Bleeding is logged more than 40 days after the birth date you logged. In your madhhab, bleeding after birth may count as nifas for up to 60 days, so Niswah can't say whether this is nifas or whether prayer is due — please consult a scholar.";
  static const postNifasAdvisoryAr =
      'هناك دم مسجَّل بعد أكثر من 40 يوماً من تاريخ الولادة المسجّل. في مذهبكِ قد يُعدّ الدم بعد الولادة نفاساً حتى 60 يوماً، لذلك لا تستطيع نسواه أن تحدد هل هو نفاس أم تجب الصلاة — يُرجى استشارة أهل العلم.';

  /// Shown wherever ending pregnancy tracking WITHOUT a logged birth is
  /// confirmed (decided 2026-10-21; pending scholar confirmation). Ending
  /// tracking this way never starts nifas and states no ruling about any
  /// bleeding after it — this neutral note only points her to a scholar.
  static const trackingEndedWithoutBirthNoteEn =
      'Pregnancy tracking is off. If this follows a pregnancy loss: whether bleeding after a pregnancy loss counts as nifas depends on how far the pregnancy had developed, so please consult a scholar.';
  static const trackingEndedWithoutBirthNoteAr =
      'تم إيقاف تتبع الحمل. إن كان ذلك بعد فقدان الحمل: فكون الدم بعد فقدان الحمل نفاساً أو لا يتوقف على مدى تخلّق الحمل، لذلك يُرجى استشارة أهل العلم.';

  /// [needsPostNifasScholarAdvisory] for a logged [birthDate] (any time of
  /// day; only its calendar date counts) as of [today]. False with no
  /// birth date.
  static bool needsPostNifasScholarAdvisoryOn({
    required DateTime? birthDate,
    required DateTime today,
    required Madhhab? madhhab,
    required bool? isBleeding,
  }) =>
      birthDate != null &&
      needsPostNifasScholarAdvisory(
        daysPostpartum: daysPostpartumOn(birthDate, today),
        madhhab: madhhab,
        isBleeding: isBleeding,
      );

  static PregnancyStatus getStatus(PregnancyProfile? profile, DateTime today) {
    if (profile == null) return const PregnancyStatus.unknown();

    if (profile.isPostpartum) {
      final start = profile.postpartumStartDate;
      if (start == null) return const PregnancyStatus.unknown();

      final days = daysPostpartumOn(start, today);
      return PregnancyStatus.postpartum(
        daysPostpartum: days,
        phase: isWithinNifasWindow(days) ? nifasPhase : postNifasPhase,
      );
    }

    final week = _resolveWeek(profile, today);
    if (week == null) return const PregnancyStatus.unknown();

    final clampedWeek = week.clamp(minWeek, maxWeek);
    return PregnancyStatus.pregnant(
      week: clampedWeek,
      trimester: trimesterForWeek(clampedWeek),
      month: _monthForWeek(clampedWeek),
      weeksToDue: (_fullTermWeeks - clampedWeek) < 0
          ? 0
          : _fullTermWeeks - clampedWeek,
    );
  }

  static int? _resolveWeek(PregnancyProfile profile, DateTime today) {
    if (profile.trackingBasis == TrackingBasis.manualWeek) {
      final baseWeek = profile.manualWeekValue;
      final setAt = profile.manualWeekSetAt;
      if (baseWeek == null || setAt == null) return null;

      final elapsedDays = today.difference(setAt).inDays;
      return baseWeek + (elapsedDays / 7).floor();
    }

    final lmpDate = _resolveToLmp(profile);
    if (lmpDate == null) return null;

    return (today.difference(lmpDate).inDays / 7).floor();
  }

  /// Converts whichever date the user actually gave us into an effective
  /// LMP date, so the rest of the engine only has one date math path.
  static DateTime? _resolveToLmp(PregnancyProfile profile) {
    final referenceDate = profile.referenceDate;
    if (referenceDate == null) return null;

    return switch (profile.trackingBasis) {
      TrackingBasis.lmp => referenceDate,
      TrackingBasis.dueDate => referenceDate.subtract(
        const Duration(days: 280),
      ),
      TrackingBasis.conceptionDate => referenceDate.subtract(
        const Duration(days: 14),
      ),
      TrackingBasis.manualWeek || null => null,
    };
  }

  /// Gestational age (counted from the LMP) minus this is the number of
  /// days since conception — the usual obstetric convention (conception
  /// about two weeks after the LMP).
  static const int conceptionOffsetDays = 14;

  /// Length of each classical stage, in days since conception.
  static const int classicalStageLengthDays = 40;

  /// The ONE mapping from gestational age to the classical
  /// Nutfah/Alaqah/Mudghah stage label.
  ///
  /// Source: the hadith of Ibn Mas'ud — "Each of you is gathered in his
  /// mother's womb for forty days, then he is a clot (alaqah) like that,
  /// then a lump (mudghah) like that…" (Sahih al-Bukhari 3208, Sahih
  /// Muslim 2643), commonly read as three consecutive 40-day stages
  /// counted from conception.
  ///
  /// Mapping (decided 2026-10-21 by the team at the owner's request as a
  /// conservative default — PROPOSED, PENDING SCHOLAR CONFIRMATION; not a
  /// settled ruling): days since conception = [gestationalDays] −
  /// [conceptionOffsetDays]; Nutfah 0–40, Alaqah 41–80, Mudghah 81–120.
  /// Before conception (negative) and after day 120 there is no classical
  /// label (null) — the trimester alone is shown. Replaces the former
  /// ≤4 / ≤8 / ≤12 gestational-week mapping, which had no documented basis
  /// and counted gestational rather than conception age.
  static ClassicalEmbryoStage? classicalStageForGestationalDays(
    int gestationalDays,
  ) {
    final sinceConception = gestationalDays - conceptionOffsetDays;
    if (sinceConception < 0) return null;
    if (sinceConception <= classicalStageLengthDays) {
      return ClassicalEmbryoStage.nutfah;
    }
    if (sinceConception <= 2 * classicalStageLengthDays) {
      return ClassicalEmbryoStage.alaqah;
    }
    if (sinceConception <= 3 * classicalStageLengthDays) {
      return ClassicalEmbryoStage.mudghah;
    }
    return null;
  }

  /// ACOG-aligned trimester for a completed-weeks value: 1 through week
  /// 13, 2 through week 27, 3 from week 28. Shared with the dashboard's
  /// trimester label so the two can never disagree.
  static int trimesterForWeek(int week) {
    if (week <= 13) return 1;
    if (week <= 27) return 2;
    return 3;
  }

  static int _monthForWeek(int week) {
    final month = (week / _weeksPerMonth).ceil();
    return month.clamp(1, 10);
  }
}
