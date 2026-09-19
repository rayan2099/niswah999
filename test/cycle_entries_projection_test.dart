import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/features/cycle_tracking/data/repositories/cycle_entries_projection.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

import 'support/secure_storage_test_support.dart';

/// Menstrual Data Integrity charter, Commit B: [CycleEntriesProjection] is
/// the one-directional bridge that lets legacy consumers
/// (`CycleCalculationService`, the dashboard) see a canonical
/// `bleeding_observations` fact without either rewriting those consumers
/// in this same pass, or letting `cycle_entries` become a second,
/// independently-writable authority.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
  });

  BleedingObservation observation({
    required ObservationFlow flow,
    DateTime? date,
    String id = 'obs-1',
  }) => BleedingObservation(
    id: id,
    userId: 'local-user',
    episodeId: 'episode-1',
    observedDate: date ?? DateTime(2026, 9, 10),
    precision: ObservationPrecision.dateOnly,
    flow: flow,
    source: ObservationSource.userObserved,
    timezone: 'UTC',
    utcOffsetMinutes: 0,
  );

  test(
    'a concrete flow observation is projected into a real cycle_entries row',
    () async {
      final projection = CycleEntriesProjection();
      final projected = await projection.project(
        observation(flow: ObservationFlow.medium),
      );

      expect(projected, isTrue);
      final logs = await CycleTrackingRepositoryImpl().getCycleLogs();
      expect(logs, hasLength(1));
      expect(logs.single.flow, FlowLevel.medium);
      expect(logs.single.date, DateTime(2026, 9, 10));
      expect(logs.single.dataProvenance, CycleEntryProvenance.userObserved);
    },
  );

  test('an uncertain ("I\'m not sure") observation is never projected — '
      'there is no factual flow value to invent', () async {
    final projection = CycleEntriesProjection();
    final projected = await projection.project(
      observation(flow: ObservationFlow.uncertain),
    );

    expect(projected, isFalse);
    final logs = await CycleTrackingRepositoryImpl().getCycleLogs();
    expect(
      logs,
      isEmpty,
      reason: 'no cycle_entries row may be fabricated for an uncertain answer',
    );
  });

  test('a historically-reported observation is projected with historical '
      'provenance, not user_observed', () async {
    final projection = CycleEntriesProjection();
    await projection.project(
      BleedingObservation(
        id: 'obs-2',
        userId: 'local-user',
        episodeId: 'episode-1',
        observedDate: DateTime(2026, 9, 1),
        precision: ObservationPrecision.dateOnly,
        flow: ObservationFlow.light,
        source: ObservationSource.userReportedHistorical,
        timezone: 'UTC',
        utcOffsetMinutes: 0,
      ),
    );

    final logs = await CycleTrackingRepositoryImpl().getCycleLogs();
    expect(
      logs.single.dataProvenance,
      CycleEntryProvenance.userReportedHistorical,
    );
  });

  test(
    'cycleDay is derived honestly from existing history, never hardcoded',
    () async {
      final projection = CycleEntriesProjection();
      await projection.project(
        observation(
          id: 'obs-a',
          date: DateTime(2026, 9, 1),
          flow: ObservationFlow.medium,
        ),
      );
      await projection.project(
        observation(
          id: 'obs-b',
          date: DateTime(2026, 9, 2),
          flow: ObservationFlow.light,
        ),
      );

      final logs = await CycleTrackingRepositoryImpl().getCycleLogs();
      final byDate = {for (final log in logs) log.date: log.cycleDay};
      expect(byDate[DateTime(2026, 9, 1)], 1);
      expect(byDate[DateTime(2026, 9, 2)], 2);
    },
  );
}
