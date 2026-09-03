import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../entities/cycle_log.dart';

enum CycleSegmentId { haid, tahara1, fertile, tahara2, prePeriod, expected }

class CycleSegment extends Equatable {
  const CycleSegment({required this.id, required this.durationDays});
  final CycleSegmentId id;
  final int durationDays;

  @override
  List<Object?> get props => [id, durationDays];
}

class CycleSegmentPlan extends Equatable {
  const CycleSegmentPlan({required this.segments, required this.activeIndex});

  /// Filtered to durationDays > 0, in a fixed narrative order:
  /// haid → tahara1 → fertile → tahara2 → prePeriod → expected.
  final List<CycleSegment> segments;

  /// Index into [segments] of the segment considered "current" — always
  /// haid or a tahara segment (see [CycleSegmentPlanner] doc), never
  /// fertile/prePeriod/expected. Null only if [segments] is empty.
  final int? activeIndex;

  CycleSegment? get active =>
      activeIndex == null ? null : segments[activeIndex!];

  /// Sum of every visible segment's [CycleSegment.durationDays] — the
  /// angular denominator the ring painter and phase timeline should use,
  /// instead of the raw statistical cycle length. The two only diverge for
  /// an unusually short real cycle, where the fixed-size prePeriod/expected
  /// slices (and the placement floors below) no longer fit inside it; using
  /// this instead keeps every visible segment's arc summing to exactly one
  /// full circle so they never overlap or wrap past 360°.
  int get totalDays => segments.fold(0, (sum, segment) => sum + segment.durationDays);

  @override
  List<Object?> get props => [segments, activeIndex];
}

/// Splits a full cycle into 6 reference-style segments (haid, two purity
/// spans either side of the fertile window, the fertile window itself,
/// pre-period, and the single expected-start day), ported from the
/// reference web app's segment-duration formulas.
///
/// Deliberately does NOT decide "current phase" the way the reference
/// does (purely from statistical day-position, which could land on any of
/// the 6 segments). That would let a fertile-window day-position override
/// what's actually happening — the exact class of bug
/// [CycleStatusEngine] exists to prevent. Instead: [isBleedingNow] (real,
/// flow-derived) always wins. It can only ever select haid vs. tahara;
/// [cycleDayEstimate] (flow-blind) is used only to decide WHICH of the
/// two tahara instances is shown as current when not bleeding — i.e. to
/// position within "currently not bleeding", never to decide whether
/// she's bleeding.
class CycleSegmentPlanner {
  const CycleSegmentPlanner();

  static const prePeriodDuration = 3;
  static const expectedDuration = 1;

  CycleSegmentPlan plan({
    required int cycleLength,
    required int periodLength,
    required FertileWindow fertileWindow,
    required DateTime cycleStart,
    required bool isBleedingNow,
    required int? cycleDayEstimate,
  }) {
    int dayOffset(DateTime? date) =>
        date == null ? periodLength : date.difference(cycleStart).inDays + 1;

    var fertileStartOffset = dayOffset(fertileWindow.start);
    var fertileEndOffset = dayOffset(fertileWindow.end);
    fertileStartOffset = math.max(periodLength + 1, fertileStartOffset);
    fertileEndOffset = math.min(cycleLength - 4, fertileEndOffset);
    final fertileDuration = math.max(
      0,
      fertileEndOffset - fertileStartOffset + 1,
    );

    final tahara1Duration = math.max(0, fertileStartOffset - periodLength - 1);
    // The day immediately after the fertile window ends — where tahara2
    // begins, regardless of how long tahara1 or the fertile window were.
    final tahara2Start = fertileEndOffset + 1;
    final tahara2Duration = math.max(
      0,
      (cycleLength - prePeriodDuration - expectedDuration) - fertileEndOffset,
    );

    final allSegments = [
      CycleSegment(id: CycleSegmentId.haid, durationDays: periodLength),
      CycleSegment(id: CycleSegmentId.tahara1, durationDays: tahara1Duration),
      CycleSegment(id: CycleSegmentId.fertile, durationDays: fertileDuration),
      CycleSegment(id: CycleSegmentId.tahara2, durationDays: tahara2Duration),
      const CycleSegment(
        id: CycleSegmentId.prePeriod,
        durationDays: prePeriodDuration,
      ),
      const CycleSegment(
        id: CycleSegmentId.expected,
        durationDays: expectedDuration,
      ),
    ];
    // Never hide the segment representing what's actually happening right
    // now, even if its typical/average length isn't known yet (e.g. a
    // first-ever period with no completed episode to average).
    final segments = allSegments
        .where(
          (segment) =>
              segment.durationDays > 0 ||
              (isBleedingNow && segment.id == CycleSegmentId.haid),
        )
        .toList();

    if (segments.isEmpty) {
      return const CycleSegmentPlan(segments: [], activeIndex: null);
    }

    final wantedId = isBleedingNow
        ? CycleSegmentId.haid
        : (cycleDayEstimate ?? 1) < tahara2Start
        ? CycleSegmentId.tahara1
        : CycleSegmentId.tahara2;

    var activeIndex = segments.indexWhere((segment) => segment.id == wantedId);
    if (activeIndex == -1) {
      // The chosen tahara instance was filtered out (zero duration) —
      // fall back to whichever tahara segment does exist.
      activeIndex = segments.indexWhere(
        (segment) =>
            segment.id == CycleSegmentId.tahara1 ||
            segment.id == CycleSegmentId.tahara2,
      );
    }
    if (activeIndex == -1) {
      // No tahara segment at all (degenerate cycle) — fall back to haid.
      activeIndex = segments.indexWhere(
        (segment) => segment.id == CycleSegmentId.haid,
      );
    }

    return CycleSegmentPlan(
      segments: segments,
      activeIndex: activeIndex == -1 ? null : activeIndex,
    );
  }
}
