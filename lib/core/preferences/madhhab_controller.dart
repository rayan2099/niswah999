import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../network/supabase_client.dart';

/// The three, deliberately-never-collapsed states a user's Madhhab
/// selection can be in (Fiqh Remediation Wave 1, AUTH-005/AUTH-010):
///
/// - [unset]: the user has not answered the Madhhab question yet.
/// - [unknown]: the user explicitly selected "I don't know my Madhhab."
/// - [selected]: the user explicitly selected exactly one real madhhab.
///
/// [unknown] must never be represented as if it were Hanbali, and [unset]
/// must never be silently resolved to any specific madhhab — every caller
/// that needs a madhhab for a Fiqh-guidance purpose must check this state
/// first and handle [unset]/[unknown] explicitly, never substitute a
/// default.
enum MadhhabSelectionState { unset, unknown, selected }

/// Server-authoritative Madhhab state — `LOCAL_CACHE_OF_SERVER`, the
/// design already prepared for `AUTH-005`'s remediation. Canonical state
/// lives in `public.users.madhhab` / `public.users.madhhab_selection_state`
/// (see `supabase/migrations/20260914120000_madhhab_authority_state.sql`);
/// `SharedPreferences` is only a local cache for fast startup and offline
/// resilience, never a substitute source of truth.
///
/// This replaces the previous SharedPreferences-only design, whose
/// `orElse: () => Madhhab.hanbali` fallback silently reached the live
/// Fiqh-calculation path and the Fiqh Advisor's AI context for any
/// already-onboarded user who lost local storage (reinstall, new device).
/// This class never returns a specific madhhab unless the user (or a
/// previously-synced server row) explicitly recorded one — see [state] and
/// [selectedOrNull].
class MadhhabController extends ChangeNotifier {
  MadhhabController._();

  static final MadhhabController instance = MadhhabController._();
  static const _stateKey = 'niswah_madhhab_selection_state';
  static const _valueKey = 'niswah_selected_madhhab';

  MadhhabSelectionState _state = MadhhabSelectionState.unset;
  Madhhab? _selected;

  MadhhabSelectionState get state => _state;

  /// Non-null only when [state] is [MadhhabSelectionState.selected].
  /// Callers must check [state] first — this never carries an invented
  /// value for [MadhhabSelectionState.unset]/[MadhhabSelectionState.unknown].
  Madhhab? get selectedOrNull => _selected;

  /// True only for [MadhhabSelectionState.selected] — the single condition
  /// under which a real madhhab may be used for Fiqh calculation or AI
  /// context.
  bool get isSelected =>
      _state == MadhhabSelectionState.selected && _selected != null;

  /// Loads the canonical state: the server row when a session and network
  /// are available (the authoritative source once it exists), otherwise
  /// this device's local cache, otherwise [MadhhabSelectionState.unset].
  /// Never falls back to a specific madhhab on any failure path.
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final serverRow = await _tryReadServerRow();
    if (serverRow != null) {
      _applyServerRow(serverRow);
      await _cacheLocally(preferences);
      notifyListeners();
      return;
    }

    // No server row available (signed out, offline, or the request
    // failed) — fall back to whatever this device last cached locally.
    // If a real local selection survives from before this device ever
    // synced with the server (e.g. it was made offline), it is preserved
    // here rather than discarded — but is still never invented from
    // nothing.
    final cachedState = preferences.getString(_stateKey);
    if (cachedState == MadhhabSelectionState.selected.name) {
      final cachedValue = preferences.getString(_valueKey);
      final madhhab = cachedValue == null
          ? null
          : Madhhab.values.firstWhereOrNull((v) => v.name == cachedValue);
      if (madhhab != null) {
        _state = MadhhabSelectionState.selected;
        _selected = madhhab;
        notifyListeners();
        return;
      }
    }
    if (cachedState == MadhhabSelectionState.unknown.name) {
      _state = MadhhabSelectionState.unknown;
      _selected = null;
      notifyListeners();
      return;
    }

    _state = MadhhabSelectionState.unset;
    _selected = null;
    notifyListeners();
  }

  /// Explicit selection of exactly one real madhhab — from onboarding, an
  /// explicit suggestion-confirmation ("yes, use this"), or Settings'
  /// change-Madhhab flow. Always replaces whatever state existed before,
  /// and is never inferred from a geographic suggestion without this
  /// explicit call.
  Future<void> selectMadhhab(Madhhab value) async {
    _state = MadhhabSelectionState.selected;
    _selected = value;
    notifyListeners();
    await _persist();
  }

  /// Explicit "I don't know my Madhhab." A first-class, durable state —
  /// never represented as any specific madhhab, and never silently
  /// re-asked merely because local storage was lost (see
  /// `_tryReadServerRow`, which restores this exact state from the server).
  Future<void> selectUnknown() async {
    _state = MadhhabSelectionState.unknown;
    _selected = null;
    notifyListeners();
    await _persist();
  }

  /// Clears in-memory state only (not the local cache, which belongs to
  /// whichever account is signed in when it's next written) — called on
  /// sign-out so a different account signing in next cannot briefly read
  /// the previous account's in-memory madhhab before its own [load]
  /// completes. See `AuthController`'s `onAuthStateChange` handler.
  void resetInMemory() {
    _state = MadhhabSelectionState.unset;
    _selected = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> _tryReadServerRow() async {
    final client = NiswahSupabase.clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return null;
    try {
      return await client
          .from('users')
          .select('madhhab, madhhab_selection_state')
          .eq('id', userId)
          .maybeSingle();
    } catch (_) {
      // Network/RLS failure — treated as "no server answer right now",
      // never coerced into a specific state. The local-cache fallback in
      // load() handles this case.
      return null;
    }
  }

  void _applyServerRow(Map<String, dynamic> row) {
    final stateName = row['madhhab_selection_state'] as String?;
    final madhhabName = (row['madhhab'] as String?)?.toLowerCase();
    final madhhab = madhhabName == null
        ? null
        : Madhhab.values.firstWhereOrNull((v) => v.name == madhhabName);

    if (stateName == MadhhabSelectionState.selected.name && madhhab != null) {
      _state = MadhhabSelectionState.selected;
      _selected = madhhab;
    } else if (stateName == MadhhabSelectionState.unknown.name) {
      _state = MadhhabSelectionState.unknown;
      _selected = null;
    } else {
      // Covers 'unset', a missing/unrecognized state value, and the
      // defensive case of state='selected' with no valid madhhab (the
      // database CHECK constraint should make this impossible, but this
      // client never trusts that alone) — all resolve to UNSET, never a
      // guessed madhhab.
      _state = MadhhabSelectionState.unset;
      _selected = null;
    }
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await _cacheLocally(preferences);
    await _writeServerRow();
  }

  Future<void> _cacheLocally(SharedPreferences preferences) async {
    await preferences.setString(_stateKey, _state.name);
    if (_state == MadhhabSelectionState.selected && _selected != null) {
      await preferences.setString(_valueKey, _selected!.name);
    } else {
      await preferences.remove(_valueKey);
    }
  }

  /// Best-effort write-through, matching this app's established pattern
  /// for non-blocking preference writes (e.g. onboarding's Anonymous Mode
  /// toggle) — the local cache above already reflects the user's choice
  /// for this session's UI. A failed server write is not surfaced here as
  /// a blocking error; it does mean this specific write could be lost on
  /// a future reinstall if it never later succeeds, which is why callers
  /// (e.g. onboarding) re-select on every real user action rather than
  /// relying on a single fire-and-forget write.
  Future<void> _writeServerRow() async {
    final client = NiswahSupabase.clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;
    try {
      await client
          .from('users')
          .update({
            'madhhab_selection_state': _state.name,
            'madhhab': _state == MadhhabSelectionState.selected
                ? _selected!.name
                : null,
          })
          .eq('id', userId);
    } catch (_) {
      // See doc comment above.
    }
  }
}
