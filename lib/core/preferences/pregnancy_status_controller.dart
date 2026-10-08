import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_clock.dart';
import 'user_scoped_preferences.dart';

/// Persists the "I am currently pregnant" (أنا حامل حالياً) status so the
/// pregnancy tracker, dashboard, and reports stay in sync — mirroring the
/// web app's persisted `user.pregnant` flag.
class PregnancyStatusController extends ChangeNotifier {
  PregnancyStatusController._();

  static final PregnancyStatusController instance =
      PregnancyStatusController._();

  static const _storageKey = 'niswah_is_pregnant';
  static const _startWeekKey = 'niswah_pregnancy_start_week';
  static const _activatedAtKey = 'niswah_pregnancy_activated_at';
  static const _nifasStartKey = 'niswah_nifas_started_at';

  bool _isPregnant = false;
  int _startWeek = 1;
  DateTime? _activatedAt;
  DateTime? _nifasStartedAt;

  bool get isPregnant => _isPregnant;
  int get startWeek => _startWeek;
  DateTime? get activatedAt => _activatedAt;
  DateTime? get nifasStartedAt => _nifasStartedAt;

  /// Nifas lasts up to ~40 days after birth.
  bool get isNifasActive {
    final start = _nifasStartedAt;
    if (start == null) return false;
    return AppClock.now().difference(start).inDays < 40;
  }

  /// Days elapsed since birth (0-based).
  int get nifasDay => _nifasStartedAt == null
      ? 0
      : AppClock.now().difference(_nifasStartedAt!).inDays + 1;

  /// Current pregnancy week derived from the activation date and the week
  /// the user selected during setup (1 week of pregnancy elapses per 7 days).
  int get currentWeek {
    if (!_isPregnant || _activatedAt == null) return _startWeek;
    final elapsedWeeks = AppClock.now().difference(_activatedAt!).inDays ~/ 7;
    return (_startWeek + elapsedWeeks).clamp(1, 40);
  }

  static const _allKeys = [
    _storageKey,
    _startWeekKey,
    _activatedAtKey,
    _nifasStartKey,
  ];

  static String _k(String base) => UserScopedPreferences.key(base);

  /// Reads the signed-in user's own pregnancy/Nifas state (never another
  /// user's).
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    await UserScopedPreferences.adoptLegacy(preferences, _allKeys);
    _isPregnant = preferences.getBool(_k(_storageKey)) ?? false;
    _startWeek = preferences.getInt(_k(_startWeekKey)) ?? 1;
    final stored = preferences.getString(_k(_activatedAtKey));
    _activatedAt = stored == null ? null : DateTime.tryParse(stored);
    final nifas = preferences.getString(_k(_nifasStartKey));
    _nifasStartedAt = nifas == null ? null : DateTime.tryParse(nifas);
    notifyListeners();
  }

  /// Forgets the in-memory state (sign-out) so the next account can never
  /// observe it before its own [load] completes.
  void resetInMemory() {
    _isPregnant = false;
    _startWeek = 1;
    _activatedAt = null;
    _nifasStartedAt = null;
    notifyListeners();
  }

  /// Records the moment of birth and starts Nifas tracking (up to 40 days).
  Future<void> startNifas() async {
    _isPregnant = false;
    _startWeek = 1;
    _activatedAt = null;
    _nifasStartedAt = AppClock.now();
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_k(_storageKey), false);
    await preferences.remove(_k(_startWeekKey));
    await preferences.remove(_k(_activatedAtKey));
    await preferences.setString(
      _k(_nifasStartKey),
      _nifasStartedAt!.toIso8601String(),
    );
  }

  /// Activates pregnancy tracking with the week chosen in the setup sheet.
  Future<void> activate({required int startWeek}) async {
    _isPregnant = true;
    _startWeek = startWeek.clamp(1, 40);
    _activatedAt = AppClock.now();
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_k(_storageKey), true);
    await preferences.setInt(_k(_startWeekKey), _startWeek);
    await preferences.setString(
      _k(_activatedAtKey),
      _activatedAt!.toIso8601String(),
    );
  }

  /// Deactivates pregnancy tracking (e.g. after logging birth / nifas).
  Future<void> deactivate() async {
    _isPregnant = false;
    _startWeek = 1;
    _activatedAt = null;
    _nifasStartedAt = null;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_k(_storageKey), false);
    await preferences.remove(_k(_startWeekKey));
    await preferences.remove(_k(_activatedAtKey));
    await preferences.remove(_k(_nifasStartKey));
  }
}
