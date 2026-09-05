import '../../features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart';
import '../../features/pregnancy_tracking/data/datasources/local_pregnancy_tracking_data_source.dart';
import '../../features/prayer_tracking/data/datasources/local_prayer_tracking_data_source.dart';
import 'secure_local_store.dart';

/// The local, on-device sensitive data categories that must be removed for
/// a deleted account (Phase F) — shared between the deletion call site
/// ([AuthRepositoryImpl.deleteAccount]) and the app-startup retry
/// ([retryPendingAccountDeletionCleanups] in `main.dart`), so both always
/// clean up exactly the same set of categories.
final Map<String, Future<void> Function(String userId)>
localSensitiveDataCleanupTasks = {
  'cycle_tracking': LocalCycleTrackingDataSource.clearForUser,
  'prayer_tracking': LocalPrayerTrackingDataSource.clearForUser,
  'pregnancy_tracking': LocalPregnancyTrackingDataSource.clearForUser,
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
