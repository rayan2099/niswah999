import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/supabase_client.dart';
import 'user_scoped_preferences.dart';

/// Requirement 4: which language community (`ar`/`en`) the user browses
/// in Community — deliberately separate from `AppLocaleController`'s
/// interface language. An Arabic-interface user may still choose to
/// browse the English community, and vice versa.
///
/// Mirrors `MadhhabController`'s pattern: server-authoritative
/// (`public.users.community_language`), `SharedPreferences` only a local
/// cache for fast startup/offline resilience. Simpler than
/// `MadhhabController` in one respect — there is no "unknown" third
/// state to preserve, just unset/ar/en — but just as careful never to
/// invent a value: [selectedOrNull] is null until the user has
/// explicitly chosen once, via the Community entry gate
/// (`community_language_gate.dart`) or the Profile/Settings toggle.
///
/// Uses [UserScopedPreferences] for its cache key from day one (this is
/// a brand-new preference, so there is no legacy global key to migrate
/// via `adoptLegacy`) — a second account signing in on the same device
/// must never inherit the first account's community-language choice.
class CommunityLanguageController extends ChangeNotifier {
  CommunityLanguageController._();

  static final CommunityLanguageController instance =
      CommunityLanguageController._();

  static const _key = 'niswah_community_language';

  CommunityLanguage? _selected;

  /// Bumped by every [select] and [resetInMemory]. A [load] that started
  /// before one of them must not overwrite it with an older answer: testing
  /// feedback 2026-10-30 showed Profile with neither community highlighted
  /// although one had been chosen.
  int _version = 0;

  /// Test seam for the server read; null uses `public.users`.
  @visibleForTesting
  static Future<CommunityLanguage?> Function()? serverReadOverride;

  /// Non-null only once the user has explicitly chosen — never a default.
  CommunityLanguage? get selectedOrNull => _selected;
  bool get isSelected => _selected != null;

  /// Loads the canonical state: the server row when a session and
  /// network are available, otherwise this device's local cache,
  /// otherwise null (unset) — never a guessed/defaulted language.
  Future<void> load() async {
    final version = _version;
    final preferences = await SharedPreferences.getInstance();
    final serverValue = await (serverReadOverride ?? _tryReadServerValue)();
    if (version != _version) return;
    if (serverValue != null) {
      _selected = serverValue;
      await _cacheLocally(preferences, serverValue);
      notifyListeners();
      return;
    }

    final cached = preferences.getString(UserScopedPreferences.key(_key));
    final cachedValue = cached == null ? null : _parse(cached);
    if (version != _version) return;
    _selected = cachedValue;
    notifyListeners();
    // The server has no value but this device does: an earlier
    // best-effort write did not land. Retry it so another device, or the
    // next install, shows the same choice.
    if (cachedValue != null && serverReadOverride == null) {
      await _writeServerValue(cachedValue);
    }
  }

  /// Explicit selection — from the Community entry gate or the
  /// Profile/Settings toggle. Never deletes or modifies any existing
  /// post; this only changes which community is displayed going forward.
  Future<void> select(CommunityLanguage value) async {
    _version++;
    if (_selected == value) return;
    _selected = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await _cacheLocally(preferences, value);
    await _writeServerValue(value);
  }

  /// Clears in-memory state only, called on sign-out so a different
  /// account signing in next cannot briefly read the previous account's
  /// in-memory language before its own [load] completes.
  void resetInMemory() {
    _version++;
    _selected = null;
    notifyListeners();
  }

  Future<CommunityLanguage?> _tryReadServerValue() async {
    final client = NiswahSupabase.clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return null;
    try {
      final row = await client
          .from('users')
          .select('community_language')
          .eq('id', userId)
          .maybeSingle();
      final value = row?['community_language'] as String?;
      return value == null ? null : _parse(value);
    } catch (_) {
      // Network/RLS failure — treated as "no server answer right now."
      return null;
    }
  }

  Future<void> _cacheLocally(
    SharedPreferences preferences,
    CommunityLanguage value,
  ) async {
    await preferences.setString(UserScopedPreferences.key(_key), value.name);
  }

  /// Best-effort write-through, matching `MadhhabController`'s
  /// established pattern for non-blocking preference writes — the local
  /// cache already reflects the choice for this session's UI.
  Future<void> _writeServerValue(CommunityLanguage value) async {
    final client = NiswahSupabase.clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;
    try {
      await client
          .from('users')
          .update({'community_language': value.name})
          .eq('id', userId);
    } catch (_) {
      // See doc comment above.
    }
  }

  CommunityLanguage? _parse(String raw) => switch (raw) {
    'ar' => CommunityLanguage.ar,
    'en' => CommunityLanguage.en,
    _ => null,
  };
}

enum CommunityLanguage { ar, en }
