import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_evidence_adapter.dart';

BleedingObservation _obs({
  required String id,
  required DateTime observedDate,
  DateTime? observedTime,
  DateTime? reportedAt,
  required ObservationFlow flow,
  ObservationSource source = ObservationSource.userObserved,
  String? supersedesId,
}) => BleedingObservation(
  id: id,
  userId: 'user-1',
  episodeId: 'episode-1',
  observedDate: observedDate,
  observedTime: observedTime,
  reportedAt: reportedAt,
  precision: ObservationPrecision.dateOnly,
  flow: flow,
  source: source,
  utcOffsetMinutes: 180,
  supersedesId: supersedesId,
);

/// Menstrual Data Integrity charter, Closure Blocker 3 — the pure
/// evidence adapter that bridges canonical `bleeding_observations` into
/// the legacy `CycleLog` shape the deterministic Fiqh engine consumes.
/// Proves the required adversarial chain: a correction changes which row
/// is "effective," and this adapter's output changes accordingly —
/// entirely independent of `cycle_entries`/the projection, which this
/// file never touches at all.
void main() {
  group('CanonicalFiqhEvidenceAdapter.buildEffectiveLogs', () {
    test('a plain observation with no correction maps straight through', () {
      final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: [
          _obs(
            id: 'obs-1',
            observedDate: DateTime(2026, 9, 1),
            flow: ObservationFlow.medium,
          ),
        ],
      );
      expect(logs, hasLength(1));
      expect(logs.single.flow, FlowLevel.medium);
      expect(logs.single.date, DateTime(2026, 9, 1));
    });

    test('Closure Blocker 3 required proof: a correction changes the '
        'effective evidence — the original (superseded) row is excluded, '
        'only the correction (the new tip) contributes', () {
      final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: [
          _obs(
            id: 'v1',
            observedDate: DateTime(2026, 9, 1),
            flow: ObservationFlow.medium,
          ),
          _obs(
            id: 'v2',
            observedDate: DateTime(2026, 9, 1),
            flow: ObservationFlow.spotting,
            supersedesId: 'v1',
          ),
        ],
      );
      expect(logs, hasLength(1));
      expect(
        logs.single.flow,
        FlowLevel.spotting,
        reason:
            'the correction (v2) is the effective value, not the '
            'original (v1) it superseded',
      );
    });

    test('correction-of-correction: only the final tip of a 3-deep chain '
        'survives', () {
      final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: [
          _obs(
            id: 'v1',
            observedDate: DateTime(2026, 9, 1),
            flow: ObservationFlow.medium,
          ),
          _obs(
            id: 'v2',
            observedDate: DateTime(2026, 9, 1),
            flow: ObservationFlow.spotting,
            supersedesId: 'v1',
          ),
          _obs(
            id: 'v3',
            observedDate: DateTime(2026, 9, 1),
            flow: ObservationFlow.light,
            supersedesId: 'v2',
          ),
        ],
      );
      expect(logs, hasLength(1));
      expect(logs.single.flow, FlowLevel.light);
    });

    test('Commit D2: same-day multiple observations collapse to the '
        'latest-reported one for that day, by observed_time', () {
      final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: [
          _obs(
            id: 'morning',
            observedDate: DateTime(2026, 9, 1),
            observedTime: DateTime(2026, 9, 1, 8),
            flow: ObservationFlow.spotting,
          ),
          _obs(
            id: 'evening',
            observedDate: DateTime(2026, 9, 1),
            observedTime: DateTime(2026, 9, 1, 21),
            flow: ObservationFlow.heavy,
          ),
        ],
      );
      expect(logs, hasLength(1));
      expect(
        logs.single.flow,
        FlowLevel.heavy,
        reason: 'the 21:00 report is the later one, so it wins',
      );
    });

    test('an uncertain-flow day is excluded entirely, never fabricated as '
        'any specific FlowLevel', () {
      final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: [
          _obs(
            id: 'obs-1',
            observedDate: DateTime(2026, 9, 1),
            flow: ObservationFlow.uncertain,
          ),
        ],
      );
      expect(logs, isEmpty);
    });

    test('provenance maps 1:1, never fabricated', () {
      final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: [
          _obs(
            id: 'obs-1',
            observedDate: DateTime(2026, 9, 1),
            flow: ObservationFlow.medium,
            source: ObservationSource.userReportedHistorical,
          ),
        ],
      );
      expect(
        logs.single.dataProvenance,
        CycleEntryProvenance.userReportedHistorical,
      );
    });

    test('logs are sorted by date ascending regardless of input order', () {
      final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: [
          _obs(
            id: 'obs-2',
            observedDate: DateTime(2026, 9, 5),
            flow: ObservationFlow.light,
          ),
          _obs(
            id: 'obs-1',
            observedDate: DateTime(2026, 9, 1),
            flow: ObservationFlow.medium,
          ),
        ],
      );
      expect(logs.map((l) => l.date), [
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 5),
      ]);
    });

    test('empty input produces an empty, never fabricated, result', () {
      final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: const [],
      );
      expect(logs, isEmpty);
    });
  });
}
