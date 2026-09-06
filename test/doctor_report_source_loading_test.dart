import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/doctor_report/domain/entities/report_source_status.dart';

import 'support/secure_storage_test_support.dart';

/// `getCycleLogsForReport` (Doctor's Report Data Completeness +
/// Truthfulness wave, 2026-09-06 — PJ-006) is the report-consuming
/// variant of `getCycleLogs` that surfaces whether the remote fetch
/// actually succeeded, rather than silently falling back to local-only
/// data. The "no Supabase client configured" branch (offline/local-only)
/// is directly testable here; the "remote fetch throws" branch requires a
/// live/mocked SupabaseClient this suite does not have a harness for —
/// covered instead by `computeReportCompleteness`/`analyze`'s own tests,
/// which exercise the resulting `ReportSourceStatus.failed` classification
/// directly regardless of which repository produced it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = 'report-user';
  });

  tearDown(() {
    SecureLocalStore.debugUserIdOverride = null;
  });

  group('CycleTrackingRepositoryImpl.getCycleLogsForReport', () {
    test(
      'no Supabase client configured, no local logs → empty, not failed '
      '— a genuinely empty account must never be reported as a load '
      'failure',
      () async {
        final repository = CycleTrackingRepositoryImpl();

        final result = await repository.getCycleLogsForReport();

        expect(result.status, ReportSourceStatus.empty);
        expect(result.data, isEmpty);
        expect(result.isUsable, isTrue);
      },
    );

    test(
      'no Supabase client configured, real local logs exist → available, '
      'the logs are still surfaced (local-authoritative)',
      () async {
        final localSource = LocalCycleTrackingDataSource();
        await localSource.upsert(
          CycleLog(
            id: 'c1',
            userId: 'report-user',
            date: DateTime(2026, 8, 1),
            flow: FlowLevel.medium,
          ),
        );

        final repository = CycleTrackingRepositoryImpl(
          localDataSource: localSource,
        );

        final result = await repository.getCycleLogsForReport();

        expect(result.status, ReportSourceStatus.available);
        expect(result.data, hasLength(1));
        expect(result.isUsable, isTrue);
      },
    );
  });
}
