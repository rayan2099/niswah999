// Round-2 hardening (2026-10-21, proposed). The screens workstream routes
// ALL symptom/notes logging to the legacy sheet (log_day_entry_router.dart)
// while the logging/sync workstream made that sheet refuse to save over a
// canonical mirror row, and the sheet saved a placeholder `flow: none` for a
// day with no row. Both failed on fix/tracking-hardening (d77cd14).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/presentation/models/cycle_log_form_data.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';

import '../support/secure_storage_test_support.dart';

class _RecordingRepository implements CycleTrackingRepository {
  final saved = <CycleLog>[];

  @override
  Future<SyncStatus> saveCycleLog(CycleLog log) async {
    saved.add(log);
    return SyncStatus.synced;
  }

  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async => saved;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = 'user-A';
  });
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  test(
    'adding cramps/notes to a day she logged through the canonical '
    'sheets (its cycle_entries row is the projection mirror) saves',
    () async {
      final repository = _RecordingRepository();
      final viewModel = CycleTrackingViewModel(
        repository: repository,
        canonicalEpisodeLoader: (_) async => const [],
        statedBaselineLoader: (_) async => null,
        // CycleEntriesProjection writes the row under the observation id,
        // so isCanonicalObservationId answers true for it.
        canonicalMirrorChecker: (id) async => id == 'observation-1',
      );
      final mirror = CycleLog(
        id: 'observation-1',
        userId: 'user-A',
        date: DateTime(2026, 10, 18),
        flow: FlowLevel.heavy,
        cycleDay: 1,
        dataProvenance: CycleEntryProvenance.userObserved,
      );

      // What the symptoms-only sheet submits for that day: the SAME flow
      // (initState keeps existing.flow), only symptoms/notes added.
      await viewModel.saveLog(
        CycleLogFormData(
          date: mirror.date,
          flow: mirror.flow,
          cycleDay: 1,
          notes: 'cramps',
          symptoms: const ['cramps:3'],
        ),
        existingLog: mirror,
      );
      expect(repository.saved, isNotEmpty);
    },
  );

  test('symptoms logged on a bleeding day before the day\'s check-in do '
      'not split one period into two in the legacy statistics', () {
    const service = CycleCalculationService();
    final logs = <CycleLog>[
      // Canonical mirrors of days 1-3 (check-ins), midnight-dated.
      CycleLog(
        id: 'o1',
        userId: 'u',
        date: DateTime(2026, 10, 1),
        flow: FlowLevel.medium,
        cycleDay: 1,
      ),
      CycleLog(
        id: 'o2',
        userId: 'u',
        date: DateTime(2026, 10, 2),
        flow: FlowLevel.medium,
        cycleDay: 2,
      ),
      CycleLog(
        id: 'o3',
        userId: 'u',
        date: DateTime(2026, 10, 3),
        flow: FlowLevel.medium,
        cycleDay: 3,
      ),
    ];
    // Day 3, 08:00, before today's check-in: Today ring -> "Symptoms &
    // notes". With no row for today yet, the sheet saves the placeholder
    // flow `none` WITH CycleLog.symptomsOnlyMarker (symptoms_only_sheet_
    // marker_test.dart proves the sheet adds it).
    final symptomsRow = CycleLogFormData(
      date: DateTime(2026, 10, 3, 8),
      flow: FlowLevel.none,
      cycleDay: 3,
      symptoms: const ['cramps:3', CycleLog.symptomsOnlyMarker],
    ).toCycleLog(userId: 'u', id: 'symptoms-row', today: DateTime(2026, 10, 3));
    logs.add(symptomsRow);
    // Day 4: check-in "still bleeding" -> mirror projected.
    final day4 = DateTime(2026, 10, 4);
    logs.add(
      CycleLog(
        id: 'o4',
        userId: 'u',
        date: day4,
        flow: FlowLevel.medium,
        cycleDay: service.computeCycleDayForNewEntry(
          existingLogs: logs,
          date: day4,
          flow: FlowLevel.medium,
        ),
      ),
    );

    final result = service.calculate(logs, asOf: DateTime(2026, 10, 4, 12));
    expect(
      result.haidStarts,
      [DateTime(2026, 10, 1)],
      reason:
          'one period (Oct 1-4); the symptoms-only row\'s flow none '
          'ended it on Oct 3 and Oct 4 became a second "cycle start"',
    );
  });
}
