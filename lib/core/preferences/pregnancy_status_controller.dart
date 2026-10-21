import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import '../../features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';
import '../utils/app_clock.dart';
import '../utils/calendar_days.dart';
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

  /// The engine's own postpartum status for the locally logged birth date —
  /// the ONE shared nifas definition (2026-10-21, proposed): the dashboard
  /// previously used its own `elapsed < 40` rule while the reports and
  /// notifications used the engine's phase, so they disagreed on day 40.
  /// Which days count as nifas is unchanged from the engine and remains an
  /// open owner decision.
  PregnancyStatus? get _postpartumStatus {
    final start = _nifasStartedAt;
    if (start == null) return null;
    return PregnancyStatusEngine.getStatus(
      PregnancyProfile(
        id: '',
        userId: '',
        isPostpartum: true,
        postpartumStartDate: calendarDay(start),
      ),
      AppClock.now(),
    );
  }

  /// True while the engine's phase for the logged birth date is nifas.
  bool get isNifasActive =>
      _postpartumStatus?.phase == PregnancyStatusEngine.nifasPhase;

  /// Elapsed calendar days since the logged birth date (0 on the birth
  /// date) — the engine's `daysPostpartum`, the same count the reports and
  /// the nifas reminder copy use. Proposed default (2026-10-21) until the
  /// owner decides how nifas days are numbered: the dashboard shows 0 as
  /// "Birth day" and N as "Day N/40", so it can never read "Day 41/40"
  /// inside the engine window. 0 when no birth is logged.
  int get nifasDay => _postpartumStatus?.daysPostpartum ?? 0;

  /// Current pregnancy week, computed by [PregnancyStatusEngine] from the
  /// week chosen at setup and the activation time — the same math, and the
  /// same [PregnancyStatusEngine.maxWeek] cap, the chat/reports/
  /// notifications use for the synced `manual_week` profile.
  int get currentWeek {
    if (!_isPregnant || _activatedAt == null) return _startWeek;
    return PregnancyStatusEngine.getStatus(
          PregnancyProfile(
            id: '',
            userId: '',
            trackingBasis: TrackingBasis.manualWeek,
            manualWeekValue: _startWeek,
            manualWeekSetAt: _activatedAt,
          ),
          AppClock.now(),
        ).week ??
        _startWeek;
  }

  /// Current gestational age in days (from the LMP convention): the week
  /// chosen at setup (its first day) plus whole calendar days since
  /// activation. Feeds the classical stage label
  /// ([PregnancyStatusEngine.classicalStageForGestationalDays]).
  int get currentGestationalDays {
    final activated = _activatedAt;
    if (!_isPregnant || activated == null) return _startWeek * 7;
    return _startWeek * 7 + calendarDaysBetween(activated, AppClock.now());
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

  /// Records the birth date and starts Nifas tracking. [birthDate] defaults
  /// to today; only its calendar date is kept. A future date is rejected
  /// with an [ArgumentError].
  Future<void> startNifas({DateTime? birthDate}) async {
    final today = calendarDay(AppClock.now());
    final birthDay = calendarDay(birthDate ?? today);
    if (birthDay.isAfter(today)) {
      throw ArgumentError.value(birthDate, 'birthDate', 'is in the future');
    }
    _isPregnant = false;
    _startWeek = 1;
    _activatedAt = null;
    _nifasStartedAt = birthDay;
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
    _startWeek = startWeek.clamp(
      PregnancyStatusEngine.minWeek,
      PregnancyStatusEngine.maxWeek,
    );
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
