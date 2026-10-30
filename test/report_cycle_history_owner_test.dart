import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/doctor_report/domain/entities/report_source_status.dart';

import 'logging_sync_hardening/support/fake_supabase.dart';

CycleLog privateEntry() => CycleLog(
  id: 'private-a',
  userId: 'owner-a',
  date: DateTime(2026, 10, 1),
  flow: FlowLevel.light,
  notes: 'synthetic private notes',
);

class HeldReportCache extends LocalCycleTrackingDataSource {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<CycleLog>> loadLogs() async {
    entered.complete();
    await release.future;
    return [privateEntry()];
  }
}

void main() {
  setUp(() => SecureLocalStore.debugUserIdOverride = 'owner-a');
  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  test('report rejects account change during local read before fetching remote data', () async {
    final fake = FakeSupabase((_, __) async => jsonResponse({}));
    await fake.signIn('owner-a');
    var requests = 0;
    fake.onTable = (_) async {
      requests++;
      return jsonResponse([]);
    };
    final cache = HeldReportCache();
    final future = CycleTrackingRepositoryImpl(
      client: fake.client,
      localDataSource: cache,
    ).getCycleLogsForReport();
    await cache.entered.future;
    await fake.signIn('owner-b');
    cache.release.complete();
    final result = await future;
    expect(result.status, ReportSourceStatus.failed);
    expect(result.data, isEmpty);
    expect(requests, 0);
  });

  for (final failure in [false, true]) {
    test(
      'report discards stale remote ${failure ? 'failure fallback' : 'success'}',
      () async {
        final fake = FakeSupabase((_, __) async => jsonResponse({}));
        await fake.signIn('owner-a');
        final token = fake.client.auth.currentSession!.accessToken;
        final entered = Completer<void>();
        final release = Completer<void>();
        fake.onTable = (request) async {
          expect(request.headers['authorization'], 'Bearer $token');
          expect(request.url.queryParameters['user_id'], 'eq.owner-a');
          entered.complete();
          await release.future;
          return failure
              ? pgError('42501', 'synthetic denial', 403)
              : jsonResponse([privateEntry().toJson()]);
        };
        final cache = HeldReportCache()..release.complete();
        final future = CycleTrackingRepositoryImpl(
          client: fake.client,
          localDataSource: cache,
        ).getCycleLogsForReport();
        await entered.future;
        await fake.signIn('owner-b');
        release.complete();
        final result = await future;
        expect(result.status, ReportSourceStatus.failed);
        expect(result.data, isEmpty);
      },
    );
  }

  test(
    'stable-account remote failure retains its own honest local fallback',
    () async {
      final fake = FakeSupabase((_, __) async => jsonResponse({}));
      await fake.signIn('owner-a');
      fake.onTable = (_) async => pgError('42501', 'synthetic denial', 403);
      final cache = HeldReportCache()..release.complete();
      final result = await CycleTrackingRepositoryImpl(
        client: fake.client,
        localDataSource: cache,
      ).getCycleLogsForReport();
      expect(result.status, ReportSourceStatus.failed);
      expect(result.data.single.userId, 'owner-a');
      expect(result.data.single.notes, 'synthetic private notes');
    },
  );
}
