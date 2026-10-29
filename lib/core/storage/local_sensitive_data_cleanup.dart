import '../../features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import '../../features/cycle_tracking/data/local/cycle_log_draft_store.dart';
import '../../features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import '../../features/prayer_tracking/data/datasources/local_prayer_tracking_data_source.dart';
import 'secure_local_store.dart';

/// The local, on-device sensitive data categories that must be removed for
/// a deleted account (Phase F) — shared between the deletion call site
/// ([AuthRepositoryImpl.deleteAccount]) and the app-startup retry
/// ([retryPendingAccountDeletionCleanups] in `main.dart`), so both always
/// clean up exactly the same set of categories.
///
/// The dormant pregnancy-tracking daily-log feature (never reachable from
/// any navigation route, confirmed since its first commit) was retired in
/// full during the Dormant Pregnancy Tracking Retirement wave, 2026-09-06 —
/// no cleanup entry is registered for it because no user could ever have
/// written data under its local storage category in the first place.
final Map<String, Future<void> Function(String userId)>
localSensitiveDataCleanupTasks = {
  'cycle_tracking': LocalCycleTrackingDataSource.clearForUser,
  // Logging/sync hardening (proposed): the not-yet-synced bleeding
  // operations queue (dates, flows, episode ids, baseline answers).
  'cycle_tracking_pending_bleeding_operations':
      PendingBleedingOperationStore.clearForUser,
  'prayer_tracking': LocalPrayerTrackingDataSource.clearForUser,
  // NJ-013: an unsaved day-log entry kept when her session ended.
  CycleLogDraftStore.category: CycleLogDraftStore.clearForUser,
};

/// Deletes every registered sensitive local data category for [userId],
/// tolerating per-category failure and recording it for retry at next app
/// start. See [SecureLocalStore.runAccountDeletionCleanup].
Future<void> cleanUpLocalSensitiveDataForDeletedAccount(String userId) =>
    SecureLocalStore.runAccountDeletionCleanup(
      userId: userId,
      cleanupTasks: localSensitiveDataCleanupTasks,
    );

/// Retries any account-deletion local cleanup left incomplete from a prior
/// app run. Call once during startup — a no-op when nothing is pending.
Future<void> retryPendingLocalSensitiveDataCleanups() =>
    SecureLocalStore.retryPendingAccountDeletionCleanups(
      cleanupTasks: localSensitiveDataCleanupTasks,
    );
