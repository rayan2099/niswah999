import 'package:shared_preferences/shared_preferences.dart';

import '../storage/secure_local_store.dart';

/// Device-local answers and cached values (marital status, TTC mode, pregnancy
/// and Nifas state, prayer city, reminder choices, the notification feed, the
/// day's wellbeing check-in) used to live under ONE global `SharedPreferences`
/// key each. A second person signing in on the same phone therefore inherited
/// the first person's answers — including a pregnancy overview on Today and the
/// first person's mood notes (found by the account-switch acceptance persona).
///
/// Every such key is now namespaced by the signed-in user, exactly like the
/// encrypted cache in [SecureLocalStore] already is. With no session (only
/// tests and pre-sign-in code) the plain key is used, which is the previous
/// behaviour.
class UserScopedPreferences {
  UserScopedPreferences._();

  /// [base] namespaced for the current user (or [base] itself with no session).
  static String key(String base) {
    if (!SecureLocalStore.hasSession) return base;
    return '${base}__${SecureLocalStore.currentUserId()}';
  }

  /// One-time, idempotent hand-over of the old global keys to the first user
  /// who loads them after the upgrade (an existing install keeps its owner's
  /// answers). A value is only moved when the user has none of their own yet,
  /// and the global key is removed once moved, so it can never reach a second
  /// user. No-op without a session.
  static Future<void> adoptLegacy(
    SharedPreferences preferences,
    Iterable<String> baseKeys,
  ) async {
    if (!SecureLocalStore.hasSession) return;
    for (final base in baseKeys) {
      final legacy = preferences.get(base);
      if (legacy == null) continue;
      final scoped = key(base);
      if (!preferences.containsKey(scoped)) {
        switch (legacy) {
          case final bool v:
            await preferences.setBool(scoped, v);
          case final int v:
            await preferences.setInt(scoped, v);
          case final double v:
            await preferences.setDouble(scoped, v);
          case final String v:
            await preferences.setString(scoped, v);
          case final List<String> v:
            await preferences.setStringList(scoped, v);
        }
      }
      await preferences.remove(base);
    }
  }
}
