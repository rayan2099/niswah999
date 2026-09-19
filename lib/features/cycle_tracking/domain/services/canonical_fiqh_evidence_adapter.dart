import '../entities/bleeding_episode.dart';
import '../entities/cycle_log.dart';

/// Menstrual Data Integrity charter, Closure Blocker 3 — the deterministic
/// Fiqh engine (`CycleStatusEngine`) still expects a `List<CycleLog>` (the
/// legacy, one-row-per-day shape). This adapter is the explicit, READ-ONLY
/// bridge from canonical `bleeding_episodes`/effective `bleeding_observations`
/// into that shape — `cycle_entries` is never read, never written, never
/// treated as authoritative by anything downstream of this adapter.
///
/// "Effective" (per the charter's own definition): for each revision
/// chain, only the current, non-superseded tip contributes. Raw/superseded
/// history is never deleted anywhere in this app — this adapter simply
/// never surfaces a row a correction has since replaced.
///
/// Nothing here invents a fact the canonical data doesn't already state.
/// Where the legacy `CycleLog`/`FlowLevel` shape genuinely cannot
/// represent something canonical data can (`ObservationFlow.uncertain`
/// has no `FlowLevel` equivalent — the legacy engine predates "I'm not
/// sure" as a first-class daily answer), that day is deliberately left
/// out of the adapted list entirely rather than mapped to an invented
/// flow value — see [_flowOrNull]'s own doc comment for the full
/// reasoning and its known, disclosed consequence.
class CanonicalFiqhEvidenceAdapter {
  const CanonicalFiqhEvidenceAdapter._();

  /// [observations] should be the user's full canonical history (every
  /// observation across every episode) — every observation the server
  /// ever accepted is already guaranteed (by the RPCs' own ownership
  /// checks) to belong to a real episode owned by the same user, so
  /// there is nothing further to cross-check against the episode list
  /// itself here. This function has no I/O and trusts the caller to have
  /// already resolved any [LoadResult] read failure before calling it
  /// (Closure Blocker 1: a read failure must never silently become "no
  /// evidence" here either — the caller must decide, honestly, what to
  /// do when the underlying read didn't succeed, not this pure function).
  static List<CycleLog> buildEffectiveLogs({
    required List<BleedingObservation> observations,
  }) {
    // A chain's tip is, by definition, the one row nothing else
    // supersedes — collecting every supersedes_id target and excluding
    // them is equivalent to (and simpler than) walking each chain
    // individually, and correctly handles a correction-of-correction:
    // only the final tip of a 3-deep chain ever survives this filter.
    final supersededIds = observations
        .map((o) => o.supersedesId)
        .whereType<String>()
        .toSet();
    final effective = observations.where((o) => !supersededIds.contains(o.id));

    // CycleLog is one row per calendar day; bleeding_observations is not
    // (Commit D2 — same-day multiple observations are a deliberate,
    // preserved feature). Deterministic, documented policy for
    // collapsing a day to the single row the legacy engine can consume:
    // whichever effective observation for that day has the latest
    // observed_time (falling back to reported_at when observed_time is
    // absent) — "the most recent thing she told us about this day,"
    // never an arbitrary/severity-based pick.
    final byDay = <DateTime, BleedingObservation>{};
    for (final observation in effective) {
      final day = DateTime(
        observation.observedDate.year,
        observation.observedDate.month,
        observation.observedDate.day,
      );
      final existing = byDay[day];
      if (existing == null || _isLaterReport(observation, existing)) {
        byDay[day] = observation;
      }
    }

    final logs = <CycleLog>[];
    for (final entry in byDay.entries) {
      final flow = _flowOrNull(entry.value.flow);
      // See class doc comment: an uncertain-flow day has no honest
      // FlowLevel to map to, so it is left out entirely rather than
      // fabricated as any specific level.
      if (flow == null) continue;
      logs.add(
        CycleLog(
          id: entry.value.id ?? '',
          userId: entry.value.userId,
          date: entry.key,
          flow: flow,
          notes: entry.value.notes,
          symptoms: entry.value.symptoms ?? const <String>[],
          dataProvenance: _mapProvenance(entry.value.source),
        ),
      );
    }
    logs.sort((a, b) => a.date.compareTo(b.date));
    return logs;
  }

  static bool _isLaterReport(
    BleedingObservation candidate,
    BleedingObservation current,
  ) {
    final candidateTime = candidate.observedTime ?? candidate.reportedAt;
    final currentTime = current.observedTime ?? current.reportedAt;
    if (candidateTime == null || currentTime == null) return false;
    return candidateTime.isAfter(currentTime);
  }

  /// Null for [ObservationFlow.uncertain] — deliberately, not a bug. The
  /// legacy `FlowLevel` enum (none/spotting/light/medium/heavy) predates
  /// "I'm not sure" as a first-class canonical answer (Section 15) and
  /// has no honest equivalent; every candidate mapping is a fabrication
  /// (`none` would silently claim "not bleeding," any other level would
  /// silently claim a specific severity she never reported). Excluding
  /// the day entirely is the doctrine-consistent choice ("UNKNOWN IS
  /// VALID DATA," "do not invent missing facts") even though it is a
  /// real, disclosed limitation: a run of "I'm not sure" days can appear
  /// as a gap to the legacy engine's own day-count continuity logic
  /// rather than as a real, present-but-unquantified bleeding day. Fully
  /// resolving this would require extending `CycleStatusEngine`/
  /// `FlowLevel` itself to a first-class "uncertain" day, which is out of
  /// this closure wave's scope (a Fiqh-engine change, not an adapter
  /// change) — recorded here, not silently worked around.
  static FlowLevel? _flowOrNull(ObservationFlow flow) => switch (flow) {
    ObservationFlow.uncertain => null,
    ObservationFlow.none => FlowLevel.none,
    ObservationFlow.spotting => FlowLevel.spotting,
    ObservationFlow.light => FlowLevel.light,
    ObservationFlow.medium => FlowLevel.medium,
    ObservationFlow.heavy => FlowLevel.heavy,
  };

  static CycleEntryProvenance _mapProvenance(ObservationSource source) =>
      switch (source) {
        ObservationSource.userObserved => CycleEntryProvenance.userObserved,
        ObservationSource.userReportedHistorical =>
          CycleEntryProvenance.userReportedHistorical,
      };
}
