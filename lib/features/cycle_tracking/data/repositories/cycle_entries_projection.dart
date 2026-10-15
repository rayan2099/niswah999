import '../../domain/entities/bleeding_episode.dart';
import '../../domain/entities/cycle_log.dart';
import '../../domain/services/cycle_calculation_service.dart';
import 'cycle_tracking_repository_impl.dart';

/// One-directional compatibility bridge (menstrual-data-integrity
/// charter, Commit B; documented in
/// docs/menstrual-data-integrity-contract.md §2): mirrors a new
/// [BleedingObservation] into a `cycle_entries` row so every existing
/// consumer that has not yet migrated onto `bleeding_episodes`/
/// `bleeding_observations` directly (`CycleCalculationService`, the
/// dashboard, the AI/Fiqh advisor context) keeps working without a
/// rewrite. `bleeding_episodes`/`bleeding_observations` remain the
/// canonical source of truth — this projection is read-compatibility
/// only, never a second independent place the user's raw fact is
/// authored.
///
/// A [ObservationFlow.uncertain] observation ("I'm not sure" on a daily
/// check-in) is deliberately never projected: there is no factual flow
/// value to represent in the flat legacy model, and inventing one — even
/// a neutral-seeming default — is exactly the fabrication the charter's
/// central doctrine forbids. The uncertainty itself only lives in the
/// canonical `bleeding_observations` row.
class CycleEntriesProjection {
  CycleEntriesProjection({
    CycleTrackingRepositoryImpl? repository,
    CycleCalculationService? calculationService,
  }) : _repository = repository ?? CycleTrackingRepositoryImpl(),
       _calculationService =
           calculationService ?? const CycleCalculationService();

  final CycleTrackingRepositoryImpl _repository;
  final CycleCalculationService _calculationService;

  /// Returns true if a `cycle_entries` row was written, false if the
  /// observation was intentionally not projectable (uncertain flow).
  /// [observation] must already be persisted (a real, non-null `id`) —
  /// this projects an existing fact, it does not create one.
  Future<bool> project(BleedingObservation observation) async {
    assert(
      observation.id != null,
      'project() requires an already-persisted observation',
    );
    final flow = _toFlowLevel(observation.flow);
    if (flow == null) return false;

    final existingLogs = await _repository.getCycleLogs();
    final cycleDay = _calculationService.computeCycleDayForNewEntry(
      existingLogs: existingLogs,
      date: observation.observedDate,
      flow: flow,
    );

    await _repository.saveCycleLog(
      CycleLog(
        id: observation.id!,
        userId: observation.userId,
        date: observation.observedDate,
        flow: flow,
        notes: observation.notes,
        cycleDay: cycleDay,
        symptoms: observation.symptoms ?? const [],
        dataProvenance: observation.source == ObservationSource.userObserved
            ? CycleEntryProvenance.userObserved
            : CycleEntryProvenance.userReportedHistorical,
      ),
    );
    return true;
  }

  /// Acceptance-test finding — a correction supersedes an earlier
  /// observation, but [project] alone leaves the SUPERSEDED
  /// observation's own prior `cycle_entries` row in place (it was
  /// written under that observation's own id, never touched again).
  /// The legacy flat model has no revision-chain concept at all, so a
  /// consumer reading it would show both the pre-correction and
  /// post-correction flow as if they were two independent same-day
  /// reports — exactly as wrong as never projecting the correction in
  /// the first place, just a different flavor of it. [correctedFlow]
  /// null (an uncertain correction) still removes the superseded row:
  /// once corrected away, the old value must not keep surfacing either.
  Future<bool> projectCorrection(
    BleedingObservation corrected, {
    required String supersededObservationId,
  }) async {
    final projected = await project(corrected);
    await _repository.deleteCycleLog(supersededObservationId);
    return projected;
  }

  static FlowLevel? _toFlowLevel(ObservationFlow flow) => switch (flow) {
    ObservationFlow.uncertain => null,
    ObservationFlow.none => FlowLevel.none,
    ObservationFlow.spotting => FlowLevel.spotting,
    ObservationFlow.light => FlowLevel.light,
    ObservationFlow.medium => FlowLevel.medium,
    ObservationFlow.heavy => FlowLevel.heavy,
  };
}
