import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/presentation/models/cycle_log_form_data.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';

import '../support/secure_storage_test_support.dart';

/// Logging/sync hardening — provenance written by the legacy log sheet
/// (dashboard ring tap, Calendar tab day tap, Insights) through
/// CycleTrackingViewModel.saveLog -> CycleLogFormData.toCycleLog.
/// docs/menstrual-data-integrity-contract.md §1 (taxonomy) and §5 (a
/// `legacy_unverified` row is never silently re-declared `user_observed`).
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

  final today = DateTime(2026, 10, 18, 9);

  test('editing a legacy_unverified row keeps it legacy_unverified', () {
    final resaved =
        CycleLogFormData(
          date: DateTime(2025, 3, 4),
          flow: FlowLevel.heavy,
          cycleDay: 2,
          notes: 'added a note',
        ).toCycleLog(
          userId: 'user-A',
          id: 'legacy-row-1',
          dataProvenance: CycleEntryProvenance.legacyUnverified,
          today: today,
        );
    expect(resaved.toJson()['data_provenance'], 'legacy_unverified');
  });

  test('a new manual log for a past day is user_reported_historical; a '
      'same-day one is user_observed', () {
    final past = CycleLogFormData(
      date: DateTime(2026, 9, 1),
      flow: FlowLevel.heavy,
      cycleDay: 1,
    ).toCycleLog(userId: 'user-A', today: today);
    final sameDay = CycleLogFormData(
      date: DateTime(2026, 10, 18),
      flow: FlowLevel.heavy,
      cycleDay: 1,
    ).toCycleLog(userId: 'user-A', today: today);
    expect(past.toJson()['data_provenance'], 'user_reported_historical');
    expect(sameDay.toJson()['data_provenance'], 'user_observed');
  });

  test(
    'the view model carries an existing row\'s provenance forward',
    () async {
      final repository = _RecordingRepository();
      final viewModel = CycleTrackingViewModel(
        repository: repository,
        canonicalEpisodeLoader: (_) async => const [],
        statedBaselineLoader: (_) async => null,
        canonicalMirrorChecker: (_) async => false,
      );
      final existing = CycleLog(
        id: 'legacy-row-1',
        userId: 'user-A',
        date: DateTime(2025, 3, 4),
        flow: FlowLevel.heavy,
        cycleDay: 2,
        dataProvenance: CycleEntryProvenance.legacyUnverified,
      );

      await viewModel.saveLog(
        CycleLogFormData(
          date: existing.date,
          flow: FlowLevel.medium,
          cycleDay: 2,
        ),
        existingLog: existing,
      );

      expect(
        repository.saved.single.dataProvenance,
        CycleEntryProvenance.legacyUnverified,
      );
    },
  );

  test('the legacy sheet never overwrites the cycle_entries mirror of a '
      'canonical bleeding observation', () async {
    final repository = _RecordingRepository();
    final viewModel = CycleTrackingViewModel(
      repository: repository,
      canonicalEpisodeLoader: (_) async => const [],
      statedBaselineLoader: (_) async => null,
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

    await expectLater(
      viewModel.saveLog(
        CycleLogFormData(date: mirror.date, flow: FlowLevel.light, cycleDay: 1),
        existingLog: mirror,
      ),
      throwsA(isA<CanonicalMirrorEditBlockedException>()),
    );
    expect(repository.saved, isEmpty);
  });
}
