import 'package:equatable/equatable.dart';

import '../../../../core/utils/calendar_days.dart';
import '../entities/pregnancy_profile.dart';

enum PregnancyMode { pregnant, postpartum, unknown }

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

  static const int _postpartumWindowDays = 40;
  static const int _fullTermWeeks = 40;

  /// The ONE shared pregnancy-week range (2026-10-21, proposed): the engine,
  /// the server mirror (`pregnancy_status.ts`, MAX_WEEK = 42) and the
  /// on-device dashboard ([PregnancyStatusController.currentWeek]) all clamp
  /// to this — previously the dashboard capped at 40 while the chat,
  /// reports and notifications went to 42.
  static const int minWeek = 1;
  static const int maxWeek = 42;
  static const double _weeksPerMonth = 4.345; // ~average weeks per month

  /// [PregnancyStatus.phase] while inside the engine's existing postpartum
  /// window, and after it. The window itself (day 0..40 inclusive) and how
  /// a day is *numbered* on screen are open owner decisions — this only
  /// makes every surface read the same definition.
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
      daysPostpartum <= _postpartumWindowDays;

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
