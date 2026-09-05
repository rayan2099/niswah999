import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/errors/app_error_reporter.dart';
import 'package:niswah/core/storage/local_sensitive_data_cleanup.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/prayer_tracking/data/datasources/local_prayer_tracking_data_source.dart';
import 'package:niswah/features/prayer_tracking/domain/entities/prayer_entry.dart';

import 'support/secure_storage_test_support.dart';

/// Privacy/Compliance remediation — LOCAL SENSITIVE STORAGE + ACCOUNT
/// DELETION CLEANUP wave. Covers the 11 required scenarios: plaintext ->
/// encrypted migration, semantic equality, idempotency, failure-preserves-
/// original-data, cycle/prayer data survival, pending sync state survival,
/// account-deletion local cleanup, logout cross-user isolation (mandatory),
/// corrupted-payload behavior, and AppErrorReporter evidence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    SecureLocalStore.debugUserIdOverride = null;
  });

  tearDown(() {
    SecureLocalStore.debugUserIdOverride = null;
    AppErrorReporter.onReport = null;
  });

  group('SecureLocalStore.migrateLegacyIfNeeded', () {
    test(
      'migrates legacy plaintext into secure storage, verifies semantic '
      'equality, and only then removes the plaintext copy',
      () async {
        final prefs = await SharedPreferences.getInstance();
        const legacyJson = '[{"a":1}]';
        await prefs.setString('legacy_key', legacyJson);

        await SecureLocalStore.migrateLegacyIfNeeded(
          legacyKey: 'legacy_key',
          category: 'test_category',
          isValid: (json) => jsonDecode(json) is List,
        );

        final migrated = await SecureLocalStore.read('test_category');
        expect(
          migrated,
          legacyJson,
          reason: 'read-back must exactly match the original (semantic equality)',
        );
        expect(
          prefs.getString('legacy_key'),
          isNull,
          reason: 'plaintext copy removed only after verified migration',
        );
      },
    );

    test(
      'is idempotent — re-running does not duplicate, erase, or recreate data',
      () async {
        final prefs = await SharedPreferences.getInstance();
        const legacyJson = '[{"a":1},{"a":2}]';
        await prefs.setString('legacy_key', legacyJson);

        Future<void> migrate() => SecureLocalStore.migrateLegacyIfNeeded(
          legacyKey: 'legacy_key',
          category: 'test_category',
          isValid: (json) => jsonDecode(json) is List,
        );

        await migrate();
        await migrate();
        await migrate();

        expect(await SecureLocalStore.read('test_category'), legacyJson);
        expect(prefs.getString('legacy_key'), isNull);
      },
    );

    test(
      'a migration failure preserves the original plaintext, writes no '
      'partial encrypted copy, and reports via AppErrorReporter',
      () async {
        final prefs = await SharedPreferences.getInstance();
        const legacyJson = '[{"a":1}]';
        await prefs.setString('legacy_key', legacyJson);

        Object? reportedError;
        AppErrorReporter.onReport =
            (error, stack, {context, feature, retryAttempt, recordId}) {
              reportedError = error;
            };

        await SecureLocalStore.migrateLegacyIfNeeded(
          legacyKey: 'legacy_key',
          category: 'test_category',
          isValid: (_) => false, // simulates a validation failure
        );

        expect(
          prefs.getString('legacy_key'),
          legacyJson,
          reason: 'original plaintext must survive a failed migration',
        );
        expect(
          await SecureLocalStore.read('test_category'),
          isNull,
          reason: 'no partial/corrupt encrypted write left behind',
        );
        expect(
          reportedError,
          isNotNull,
          reason: 'AppErrorReporter must receive migration failures',
        );
      },
    );

    test('nothing to migrate is a silent, reportable-free no-op', () async {
      Object? reportedError;
      AppErrorReporter.onReport =
          (error, stack, {context, feature, retryAttempt, recordId}) {
            reportedError = error;
          };

      await SecureLocalStore.migrateLegacyIfNeeded(
        legacyKey: 'never_written_key',
        category: 'test_category',
        isValid: (json) => jsonDecode(json) is List,
      );

      expect(await SecureLocalStore.read('test_category'), isNull);
      expect(reportedError, isNull);
    });
  });

  group('Cycle tracking — migration and data survival', () {
    test(
      'existing legacy cycle logs (including pending sync state) survive '
      'migration and remain fully readable afterward',
      () async {
        final legacyLogs = [
          CycleLog(
            id: 'c1',
            userId: 'user-1',
            date: DateTime(2026, 9, 1),
            flow: FlowLevel.medium,
            syncStatus: SyncStatus.pending,
          ),
          CycleLog(
            id: 'c2',
            userId: 'user-1',
            date: DateTime(2026, 9, 2),
            flow: FlowLevel.heavy,
            syncStatus: SyncStatus.synced,
          ),
        ];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'niswah_cycle_tracking_logs',
          jsonEncode(legacyLogs.map((l) => l.toJson()).toList()),
        );

        final source = LocalCycleTrackingDataSource();
        final loaded = await source.loadLogs();

        expect(loaded.length, 2);
        expect(loaded.map((l) => l.id).toSet(), {'c1', 'c2'});
        expect(
          loaded.firstWhere((l) => l.id == 'c1').syncStatus,
          SyncStatus.pending,
          reason: 'pending sync state must survive migration unchanged',
        );
        expect(
          loaded.firstWhere((l) => l.id == 'c2').syncStatus,
          SyncStatus.synced,
        );
        expect(prefs.getString('niswah_cycle_tracking_logs'), isNull);
      },
    );
  });

  group('Prayer tracking — migration and data survival', () {
    test(
      'existing legacy prayer entries survive migration and remain fully '
      'readable afterward',
      () async {
        final legacyEntries = [
          PrayerEntry(
            id: 'p1',
            userId: 'user-1',
            prayerName: PrayerName.fajr,
            date: DateTime(2026, 9, 1),
            scheduledTime: const TimeOfDay(hour: 5, minute: 10),
            status: PrayerStatus.completed,
          ),
          PrayerEntry(
            id: 'p2',
            userId: 'user-1',
            prayerName: PrayerName.asr,
            date: DateTime(2026, 9, 1),
            scheduledTime: const TimeOfDay(hour: 15, minute: 30),
            status: PrayerStatus.missed,
          ),
        ];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'niswah_prayer_tracking_logs',
          jsonEncode(legacyEntries.map((e) => e.toJson()).toList()),
        );

        final source = LocalPrayerTrackingDataSource();
        final loaded = await source.loadLogs();

        expect(loaded.length, 2);
        expect(
          loaded.firstWhere((e) => e.id == 'p1').status,
          PrayerStatus.completed,
        );
        expect(
          loaded.firstWhere((e) => e.id == 'p2').status,
          PrayerStatus.missed,
        );
        expect(prefs.getString('niswah_prayer_tracking_logs'), isNull);
      },
    );
  });

  group('Corrupted encrypted payload behavior (Phase H)', () {
    test(
      'a corrupted stored payload degrades to no-data rather than crashing '
      'the caller, and is reported via AppErrorReporter',
      () async {
        // No migration involved here — simulates an already-corrupted
        // value found directly in secure storage (the scenario Phase H
        // asks to be tested independently of the migration path).
        await SecureLocalStore.write('cycle_tracking_logs', 'not-json{{{');

        Object? reportedError;
        AppErrorReporter.onReport =
            (error, stack, {context, feature, retryAttempt, recordId}) {
              reportedError = error;
            };

        final source = LocalCycleTrackingDataSource();
        final result = await source.loadLogs();

        expect(
          result,
          isEmpty,
          reason: 'user-safe degrade: empty result, not an uncaught crash',
        );
        expect(
          reportedError,
          isNotNull,
          reason: 'AppErrorReporter must receive decode failures',
        );
      },
    );
  });

  group('Account deletion local cleanup (Phase F)', () {
    test(
      'clears the deleted user\'s cycle and prayer data, leaving nothing '
      'behind on-device',
      () async {
        SecureLocalStore.debugUserIdOverride = 'user-deleted';

        final cycleSource = LocalCycleTrackingDataSource();
        await cycleSource.upsert(
          CycleLog(
            id: 'c1',
            userId: 'user-deleted',
            date: DateTime(2026, 9, 1),
            flow: FlowLevel.light,
          ),
        );

        final prayerSource = LocalPrayerTrackingDataSource();
        await prayerSource.upsert(
          PrayerEntry(
            id: 'p1',
            userId: 'user-deleted',
            prayerName: PrayerName.isha,
            date: DateTime(2026, 9, 1),
            scheduledTime: const TimeOfDay(hour: 20, minute: 0),
            status: PrayerStatus.pending,
          ),
        );

        expect(await cycleSource.loadLogs(), isNotEmpty);
        expect(await prayerSource.loadLogs(), isNotEmpty);

        await cleanUpLocalSensitiveDataForDeletedAccount('user-deleted');

        expect(await cycleSource.loadLogs(), isEmpty);
        expect(await prayerSource.loadLogs(), isEmpty);
      },
    );

    test(
      'a partial cleanup failure is reported, not silently treated as '
      'success',
      () async {
        Object? reportedError;
        String? reportedFeature;
        AppErrorReporter.onReport =
            (error, stack, {context, feature, retryAttempt, recordId}) {
              reportedError = error;
              reportedFeature = feature;
            };

        await SecureLocalStore.runAccountDeletionCleanup(
          userId: 'user-x',
          cleanupTasks: {
            'cycle_tracking': (_) async {}, // succeeds
            'prayer_tracking': (_) async {
              throw StateError('simulated cleanup failure');
            },
          },
        );

        expect(reportedError, isNotNull);
        expect(reportedFeature, 'prayer_tracking');
      },
    );
  });

  group('Logout / cross-user local data isolation (Phase G — mandatory)', () {
    test(
      'User A logs local cycle data, logs out, then User B signs in on the '
      'same device — User B cannot read User A\'s local data',
      () async {
        SecureLocalStore.debugUserIdOverride = 'user-a';
        final source = LocalCycleTrackingDataSource();
        await source.upsert(
          CycleLog(
            id: 'a-log-1',
            userId: 'user-a',
            date: DateTime(2026, 9, 1),
            flow: FlowLevel.medium,
          ),
        );
        expect(
          await source.loadLogs(),
          isNotEmpty,
          reason: 'sanity check: User A can read their own data',
        );

        // User A signs out; User B signs in on the same device.
        SecureLocalStore.debugUserIdOverride = 'user-b';

        final userBView = await source.loadLogs();
        expect(
          userBView,
          isEmpty,
          reason: 'User B must not see User A\'s cached cycle data',
        );

        // User A's data remains intact and unaffected.
        SecureLocalStore.debugUserIdOverride = 'user-a';
        expect(await source.loadLogs(), isNotEmpty);
      },
    );

    test(
      'the same isolation holds for prayer tracking data',
      () async {
        SecureLocalStore.debugUserIdOverride = 'user-a';
        final source = LocalPrayerTrackingDataSource();
        await source.upsert(
          PrayerEntry(
            id: 'a-prayer-1',
            userId: 'user-a',
            prayerName: PrayerName.dhuhr,
            date: DateTime(2026, 9, 1),
            scheduledTime: const TimeOfDay(hour: 12, minute: 30),
            status: PrayerStatus.completed,
          ),
        );

        SecureLocalStore.debugUserIdOverride = 'user-b';
        expect(await source.loadLogs(), isEmpty);
      },
    );
  });
}
