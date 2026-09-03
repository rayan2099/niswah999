import 'package:equatable/equatable.dart';

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
  static const int _minWeek = 1;
  static const int _maxWeek = 42;
  static const double _weeksPerMonth = 4.345; // ~average weeks per month

  static PregnancyStatus getStatus(PregnancyProfile? profile, DateTime today) {
    if (profile == null) return const PregnancyStatus.unknown();

    if (profile.isPostpartum) {
      final start = profile.postpartumStartDate;
      if (start == null) return const PregnancyStatus.unknown();

      final days = today.difference(start).inDays;
      return PregnancyStatus.postpartum(
        daysPostpartum: days,
        phase: days <= _postpartumWindowDays ? 'نفاس' : 'ما بعد النفاس',
      );
    }

    final week = _resolveWeek(profile, today);
    if (week == null) return const PregnancyStatus.unknown();

    final clampedWeek = week.clamp(_minWeek, _maxWeek);
    return PregnancyStatus.pregnant(
      week: clampedWeek,
      trimester: _trimesterForWeek(clampedWeek),
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

  static int _trimesterForWeek(int week) {
    if (week <= 13) return 1;
    if (week <= 27) return 2;
    return 3;
  }

  static int _monthForWeek(int week) {
    final month = (week / _weeksPerMonth).ceil();
    return month.clamp(1, 10);
  }
}
