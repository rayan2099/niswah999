import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/app_error_reporter.dart';
import '../network/supabase_client.dart';

/// Encrypted, per-user-scoped local storage for sensitive health data
/// (cycle, prayer, pregnancy tracking).
///
/// Replaces the prior plaintext, globally-shared `SharedPreferences` keys
/// those data sources used, which had two confirmed defects: the data was
/// unencrypted at rest, and the storage key was a fixed global constant not
/// scoped to the signed-in user at all — a second person signing in on the
/// same device could read the first person's cached health records.
///
/// Backed by `flutter_secure_storage` (Android Keystore / iOS Keychain) —
/// platform-managed key material, no custom crypto, key never stored
/// alongside its own ciphertext.
class SecureLocalStore {
  SecureLocalStore._();

  // Android: v11's default AndroidOptions() already uses AES-GCM with
  // RSA-OAEP Keystore-backed key wrapping, and android:allowBackup="false"
  // (AndroidManifest.xml) already excludes all app data — this store
  // included — from any OS-level backup, so no Android-specific options
  // are needed here.
  //
  // iOS: the plugin's own defaults leave `synchronizable: false` (no
  // iCloud Keychain sync — already safe) but `accessibility: unlocked`,
  // which *is* eligible to migrate to a different physical device via an
  // encrypted local backup/restore. This data is meant to be strictly
  // on-device (there is no server copy to reconcile a restored value
  // against), so accessibility is tightened to `unlocked_this_device`:
  // the Keychain item simply won't restore onto a new device — it reads
  // back the same as "no local data yet," which is the correct, safe
  // outcome (see Phase I).
  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );

  static const _noSessionSentinel = '__no_session__';

  /// Test-only seam: when set, [currentUserId] returns this instead of
  /// resolving a real Supabase session — lets tests simulate distinct
  /// signed-in users (e.g. the Phase G cross-user isolation test) without
  /// standing up a real auth session. Must never be set outside test code;
  /// reset to `null` in `tearDown()`.
  @visibleForTesting
  static String? debugUserIdOverride;

  /// The current signed-in user's id, or a stable sentinel when there is no
  /// session. Every stored value is scoped by this, so switching users on
  /// the same device can never expose one user's cache to another.
  static String currentUserId() =>
      debugUserIdOverride ??
      NiswahSupabase.clientOrNull?.auth.currentUser?.id ??
      _noSessionSentinel;

  static String _scopedKey(String category, String userId) =>
      '${category}__$userId';

  static Future<String?> read(String category) =>
      _secureStorage.read(key: _scopedKey(category, currentUserId()));

  static Future<void> write(String category, String value) => _secureStorage
      .write(key: _scopedKey(category, currentUserId()), value: value);

  static Future<void> delete(String category) =>
      _secureStorage.delete(key: _scopedKey(category, currentUserId()));

  /// Removes this category's data for the *given* user id, regardless of
  /// who is currently signed in. Used by account-deletion cleanup (Phase F),
  /// which must run after the server-side deletion has already invalidated
  /// the session but before local sign-out clears `currentUser` — callers
  /// capture the user id first and pass it explicitly rather than relying
  /// on [currentUserId].
  static Future<void> clearForUser(String category, String userId) =>
      _secureStorage.delete(key: _scopedKey(category, userId));

  /// One-time, non-destructive migration from a legacy, unscoped, plaintext
  /// `SharedPreferences` key to this category's encrypted, user-scoped
  /// store. Safe to call on every app start — idempotent.
  ///
  /// Sequence: detect legacy plaintext -> read it -> validate/deserialize
  /// it -> write it to secure storage -> read it back -> verify semantic
  /// equality -> only then remove the plaintext copy. A failure at any step
  /// leaves the legacy plaintext copy untouched and reports via
  /// [AppErrorReporter] — never a silent data loss, and never a partial
  /// migration state that would make a retry see "already migrated" for
  /// data that was never actually verified.
  ///
  /// [isValid] performs the deserialize/validate step — callers pass a
  /// check appropriate to their stored JSON shape (e.g. decodes and
  /// confirms it's a `List`). Migration only proceeds past validation.
  static Future<void> migrateLegacyIfNeeded({
    required String legacyKey,
    required String category,
    required bool Function(String json) isValid,
  }) async {
    try {
      final alreadyMigrated = await read(category);
      if (alreadyMigrated != null) return; // idempotent: nothing to do

      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(legacyKey);
      if (legacy == null || legacy.isEmpty) return; // nothing to migrate

      if (!isValid(legacy)) {
        throw FormatException(
          'Legacy local data for "$category" failed validation before '
          'migration; leaving plaintext copy in place.',
        );
      }

      await write(category, legacy);

      final readBack = await read(category);
      if (readBack != legacy) {
        // Verification failed — roll back the partial secure-storage write
        // so a retry starts clean instead of wrongly appearing "migrated".
        await delete(category);
        throw StateError(
          'Migration verification failed for "$category" — read-back did '
          'not match the original data; leaving plaintext copy in place.',
        );
      }

      // Verified byte-for-byte equal — the plaintext copy is now safe to
      // remove.
      await prefs.remove(legacyKey);
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'SecureLocalStore.migrateLegacyIfNeeded',
        feature: 'local_storage_migration',
        recordId: category,
      );
      // Reported, not rethrown — a migration failure must never crash app
      // startup or block the user from using the app on its (still-intact)
      // legacy plaintext data.
    }
  }

  // Tracks user ids whose account-deletion local cleanup (Phase F) has not
  // yet fully succeeded, so a later app start can retry it. This list holds
  // only opaque user ids — never health data — so plain `SharedPreferences`
  // is appropriate; it is not the sensitive data being protected.
  static const _pendingCleanupKey = 'niswah_pending_local_account_cleanup';

  static Future<void> _markPendingCleanup(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingCleanupKey) ?? const [];
    if (!pending.contains(userId)) {
      await prefs.setStringList(_pendingCleanupKey, [...pending, userId]);
    }
  }

  static Future<void> _clearPendingCleanup(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingCleanupKey) ?? const [];
    if (pending.contains(userId)) {
      await prefs.setStringList(
        _pendingCleanupKey,
        pending.where((id) => id != userId).toList(),
      );
    }
  }

  /// Runs [cleanup] for a given deleted-account's user id, across every
  /// registered local data category, tolerating each category's failure
  /// independently. On any failure, the user id is recorded so a later call
  /// (from app startup) retries it; on full success, any prior record is
  /// cleared. Never rethrows — deletion-cleanup failure must not block
  /// sign-out or crash app startup.
  static Future<void> runAccountDeletionCleanup({
    required String userId,
    required Map<String, Future<void> Function(String userId)> cleanupTasks,
  }) async {
    var anyFailed = false;
    for (final entry in cleanupTasks.entries) {
      try {
        await entry.value(userId);
      } catch (error, stack) {
        anyFailed = true;
        AppErrorReporter.report(
          error,
          stack,
          context: 'SecureLocalStore.runAccountDeletionCleanup',
          feature: entry.key,
          recordId: userId,
        );
      }
    }

    if (anyFailed) {
      await _markPendingCleanup(userId);
    } else {
      await _clearPendingCleanup(userId);
    }
  }

  /// Retries any account-deletion local cleanup that failed on a previous
  /// run — call once at app startup. Safe to call even with no pending
  /// work (a no-op in that case) and safe to call repeatedly.
  static Future<void> retryPendingAccountDeletionCleanups({
    required Map<String, Future<void> Function(String userId)> cleanupTasks,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingCleanupKey) ?? const [];
    for (final userId in pending) {
      await runAccountDeletionCleanup(
        userId: userId,
        cleanupTasks: cleanupTasks,
      );
    }
  }

  /// Decodes a stored JSON list, tolerating a corrupted/unreadable payload
  /// (Phase H: an encrypted value that fails to decrypt cleanly, or that
  /// was somehow left malformed, must not crash the caller). On decode
  /// failure, reports via [AppErrorReporter] and returns an empty list —
  /// not a silent failure (it's reported), but a user-safe one: the app
  /// degrades to "no local data" rather than crashing on data it can't use
  /// anyway.
  static List<T> decodeJsonListSafely<T>({
    required String? raw,
    required String category,
    required T Function(Map<String, dynamic> json) fromJson,
  }) {
    // Deliberately `<T>[]`, not `const []` — a bare `const []` inside a
    // generic method infers as `List<Never>` (the empty const list has no
    // way to be parameterized by the runtime type T), which then throws a
    // confusing `_TypeError` in any caller doing `.firstWhere(orElse: () =>
    // T(...))` on the result.
    if (raw == null || raw.isEmpty) return <T>[];
    final List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'SecureLocalStore.decodeJsonListSafely',
        feature: category,
      );
      return <T>[];
    }

    // Each item is parsed independently and a failure quarantines only that
    // one record rather than the whole list — a `fromJson` that now throws
    // on strictly invalid required data (rather than silently fabricating a
    // plausible-looking default, per the menstrual-data-integrity charter's
    // strict-parsing requirement) must never cause every *other*, perfectly
    // valid record sharing this same on-disk blob to vanish with it.
    final results = <T>[];
    for (final item in decoded) {
      try {
        results.add(fromJson(item as Map<String, dynamic>));
      } catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'SecureLocalStore.decodeJsonListSafely',
          feature: category,
        );
      }
    }
    return results;
  }
}
