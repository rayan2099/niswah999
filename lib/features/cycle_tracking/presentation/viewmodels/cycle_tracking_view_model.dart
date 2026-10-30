import 'package:flutter/foundation.dart';

import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/calendar_days.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../data/repositories/cycle_tracking_repository_impl.dart';
import '../../domain/controllers/cycle_tracking_controller.dart';
import '../../domain/entities/bleeding_episode.dart';
import '../../domain/entities/cycle_log.dart';
import '../../domain/entities/load_result.dart';
import '../../domain/repositories/cycle_tracking_repository.dart';
import '../../domain/services/cycle_calculation_service.dart';
import '../models/cycle_log_form_data.dart';

/// Logging/sync hardening (proposed) — thrown by
/// [CycleTrackingViewModel.saveLog] instead of overwriting a `cycle_entries`
/// row that mirrors a canonical bleeding observation.
class CanonicalMirrorEditBlockedException implements Exception {
  const CanonicalMirrorEditBlockedException();

  @override
  String toString() => 'CanonicalMirrorEditBlockedException';
}

class CycleTrackingViewModel extends ChangeNotifier {
  CycleTrackingViewModel({
    CycleTrackingRepository? repository,
    AuthRepositoryImpl? authRepository,
    Future<List<CanonicalEpisodeTiming>> Function(String userId)?
    canonicalEpisodeLoader,
    Future<CycleBaseline?> Function(String userId)? statedBaselineLoader,
    Future<bool?> Function(String logId)? canonicalMirrorChecker,
    this._calculationService = const CycleCalculationService(),
    BleedingEpisodeRepositoryImpl? bleedingEpisodeRepository,
  }) : _repository = repository ?? CycleTrackingRepositoryImpl(),
       _canonicalMirrorChecker =
           canonicalMirrorChecker ?? _defaultCanonicalMirrorChecker,
       _canonicalHistoryLoader = canonicalEpisodeLoader == null
           ? ((userId) => _defaultCanonicalHistoryLoader(
               bleedingEpisodeRepository ?? BleedingEpisodeRepositoryImpl(),
               userId,
             ))
           : ((userId) async => (
               episodes: await canonicalEpisodeLoader(userId),
               complete: true,
             )),
       _statedBaselineLoader =
           statedBaselineLoader ?? _defaultStatedBaselineLoader {
    _authRepository = authRepository;
  }

  static Future<bool?> _defaultCanonicalMirrorChecker(String logId) =>
      BleedingEpisodeRepositoryImpl().isCanonicalObservationId(logId);

  /// Logging/sync hardening (proposed) — whether a `cycle_entries` row is
  /// the mirror of a canonical bleeding observation (see
  /// [BleedingEpisodeRepositoryImpl.isCanonicalObservationId]).
  final Future<bool?> Function(String logId) _canonicalMirrorChecker;

  /// Canonical episode start/end DATES only (never a flow) — see
  /// [CanonicalEpisodeTiming]. A read failure yields an empty list: the
  /// legacy statistics then simply have no supplement, exactly as before,
  /// and never a fabricated value. A degraded read (at least one row
  /// quarantined) keeps the rows that parsed for the statistics but is
  /// marked incomplete, so no prediction is built from it — see
  /// [canonicalHistoryComplete].
  static Future<({List<CanonicalEpisodeTiming> episodes, bool complete})>
  _defaultCanonicalHistoryLoader(
    BleedingEpisodeRepositoryImpl repository,
    String userId,
  ) async {
    if (userId == 'local-user') {
      return (episodes: const <CanonicalEpisodeTiming>[], complete: true);
    }
    try {
      final result = await repository.getEpisodesForUser(userId);
      return (
        episodes: [
          for (final episode in result.dataOrNull ?? const <BleedingEpisode>[])
            CanonicalEpisodeTiming.of(episode),
        ],
        complete: result is! LoadDegraded<List<BleedingEpisode>>,
      );
    } catch (_) {
      return (episodes: const <CanonicalEpisodeTiming>[], complete: true);
    }
  }

  final Future<({List<CanonicalEpisodeTiming> episodes, bool complete})>
  Function(String userId)
  _canonicalHistoryLoader;

  /// False after a `bleeding_episodes` read that came back degraded (a
  /// row was quarantined). Forward predictions are then withheld on every
  /// screen that reads this view model — the same rule the reminder and
  /// the canonical calendar follow (integrity contract: a prediction is
  /// never computed from evidence known to have a gap). Proposed,
  /// prediction-efficiency audit 2026-10-21.
  bool get canonicalHistoryComplete => _canonicalHistoryComplete;
  bool _canonicalHistoryComplete = true;

  /// Her onboarding estimate of her usual cycle and period length. A read
  /// failure is simply "no estimate": predictions then come from logged
  /// history alone, exactly as before the estimate was used.
  static Future<CycleBaseline?> _defaultStatedBaselineLoader(
    String userId,
  ) async {
    if (userId == 'local-user') return null;
    try {
      return await CycleBaselineRepositoryImpl().getBaseline(userId);
    } catch (_) {
      return null;
    }
  }

  final Future<CycleBaseline?> Function(String userId) _statedBaselineLoader;

  final CycleTrackingRepository _repository;
  AuthRepositoryImpl? _authRepository;
  final CycleTrackingController _controller = CycleTrackingController();
  final CycleCalculationService _calculationService;

  String _currentUserId = 'local-user';
  AppUser? _currentUser;
  CyclePhase? selectedPhase;

  List<CycleLog> logs = const <CycleLog>[];

  /// Canonical episode timing supplement for the legacy statistics; see
  /// [CanonicalEpisodeTiming]. Empty until [loadLogs] has read it.
  List<CanonicalEpisodeTiming> canonicalEpisodes =
      const <CanonicalEpisodeTiming>[];

  /// Her stated usual cycle/period length (see [CycleBaseline]); null
  /// until [loadLogs] has read it, or when she never gave one.
  CycleBaseline? statedBaseline;
  CycleTrackingSummary _summary = const CycleTrackingSummary(
    averageCycleLength: null,
    averagePeriodLength: null,
    lastCycleStart: null,
    currentPhase: CyclePhase.follicular,
    fertileWindow: FertileWindow(start: null, end: null, peakDay: null),
  );

  /// The calendar day [_summary] was computed for; null before the first
  /// [loadLogs].
  DateTime? _summaryDay;

  /// Next-period range, late status, fertile window and phase all depend on
  /// "today". Recomputed from the already-loaded data whenever the calendar
  /// day has changed since it was last computed — the app can stay in
  /// memory across days, while [cycleCalculation] (and so the cycle day)
  /// always follows the clock.
  CycleTrackingSummary get summary {
    final today = calendarDay(AppClock.now());
    final computedFor = _summaryDay;
    if (computedFor != null && computedFor != today) {
      _summary = _summarize(today);
      _summaryDay = today;
    }
    return _summary;
  }

  CycleTrackingSummary _summarize(DateTime today) =>
      _controller.summarizeCalculation(_calculationFor(today), today: today);

  /// The last [CycleCalculationService.calculate] result and what it was
  /// computed from. Today, the Calendar tab and Insights all read
  /// [cycleCalculation] on every rebuild (the Today screen rebuilds at
  /// least once a minute), and [_summarize] needs the same calculation:
  /// with years of daily logs one run takes milliseconds, so it is
  /// computed once per data load and calendar day, not once per read.
  ({
    DateTime day,
    List<CycleLog> logs,
    List<CanonicalEpisodeTiming> canonicalEpisodes,
    CycleBaseline? statedBaseline,
    bool historyComplete,
    CycleCalculationResult result,
  })?
  _calculation;

  CycleCalculationResult _calculationFor(DateTime day) {
    final cached = _calculation;
    if (cached != null &&
        cached.day == day &&
        identical(cached.logs, logs) &&
        identical(cached.canonicalEpisodes, canonicalEpisodes) &&
        identical(cached.statedBaseline, statedBaseline) &&
        cached.historyComplete == canonicalHistoryComplete) {
      return cached.result;
    }
    // `asOf` only sets the cycle day, which counts calendar days, so the
    // day alone is the same input as the exact time.
    final calculated = _calculationService.calculate(
      logs,
      asOf: day,
      canonicalEpisodes: canonicalEpisodes,
      statedBaseline: statedBaseline,
    );
    final result = canonicalHistoryComplete
        ? calculated
        : _withoutPrediction(calculated);
    _calculation = (
      day: day,
      logs: logs,
      canonicalEpisodes: canonicalEpisodes,
      statedBaseline: statedBaseline,
      historyComplete: canonicalHistoryComplete,
      result: result,
    );
    return result;
  }

  bool isLoading = false;
  String? errorMessage;

  /// The sync outcome of the most recent [saveLog] call, or `null` before
  /// any save this session. `null` and [SyncStatus.synced] both mean "no
  /// warning to show"; `pending`/`failed` distinguish "will retry
  /// automatically" from "won't" so callers can word an accurate message
  /// instead of a blanket "backs up automatically" claim.
  SyncStatus? lastSaveSyncStatus;

  String get currentUserId => _currentUserId;
  AppUser? get currentUser => _currentUser;

  /// [calculation] with every forward-prediction field cleared, so
  /// `canPredict` is false and every screen shows its existing
  /// "no prediction" state. The logged statistics are kept.
  static CycleCalculationResult _withoutPrediction(
    CycleCalculationResult calculation,
  ) => CycleCalculationResult(
    haidStarts: calculation.haidStarts,
    currentCycleDay: calculation.currentCycleDay,
    averageCycleLength: calculation.averageCycleLength,
    cycleLengths: calculation.cycleLengths,
    averagePeriodLength: calculation.averagePeriodLength,
    predictionCycleStarts: calculation.predictionCycleStarts,
    predictionCycleLengths: calculation.predictionCycleLengths,
  );

  CycleCalculationResult get cycleCalculation =>
      _calculationFor(calendarDay(AppClock.now()));

  ({
    DateTime lastDay,
    DateTime asOfDay,
    List<CycleLog> logs,
    List<CanonicalEpisodeTiming> canonicalEpisodes,
    CycleCalculationResult result,
  })?
  _rangeCalculation;

  /// Factual cycle statistics from the history logged up to and including
  /// [lastDay] (the Calendar tab's month/year summary), with the cycle day
  /// counted on [asOf]. Her stated estimate is not used: these are logged
  /// facts only. Cached like [cycleCalculation]: the Calendar tab stays
  /// mounted and rebuilds whenever the shared view model notifies.
  CycleCalculationResult calculationUpTo({
    required DateTime lastDay,
    required DateTime asOf,
  }) {
    final dayAfter = addCalendarDays(lastDay, 1);
    final asOfDay = calendarDay(asOf);
    final cached = _rangeCalculation;
    if (cached != null &&
        cached.lastDay == calendarDay(lastDay) &&
        cached.asOfDay == asOfDay &&
        identical(cached.logs, logs) &&
        identical(cached.canonicalEpisodes, canonicalEpisodes)) {
      return cached.result;
    }
    // The day after [lastDay] by calendar, never `Duration(days: 1)`: on a
    // month whose last day is a spring-forward Sunday (31 March 2024 in
    // the UK) that landed at 01:00 the next day, pulling the next month's
    // first-day logs into this summary.
    final result = _calculationService.calculate(
      logs.where((log) => log.date.isBefore(dayAfter)).toList(),
      canonicalEpisodes: canonicalEpisodes
          .where((episode) => episode.startDate.isBefore(dayAfter))
          .toList(),
      asOf: asOfDay,
    );
    _rangeCalculation = (
      lastDay: calendarDay(lastDay),
      asOfDay: asOfDay,
      logs: logs,
      canonicalEpisodes: canonicalEpisodes,
      result: result,
    );
    return result;
  }

  List<CycleLog> get filteredLogs =>
      _controller.filterLogsByPhase(logs, selectedPhase);

  Future<void> loadCurrentUser() async {
    try {
      final activeAuthRepository = _authRepository ?? _safeAuthRepository();
      if (activeAuthRepository == null) {
        _currentUser = null;
        _currentUserId = 'local-user';
        notifyListeners();
        return;
      }

      _currentUser = await activeAuthRepository.currentUser;
      _currentUserId = _currentUser?.id ?? 'local-user';
    } catch (_) {
      _currentUser = null;
      _currentUserId = 'local-user';
    }
    notifyListeners();
  }

  Future<void> loadLogs() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await loadCurrentUser();
      final loadedLogs = await _repository.getCycleLogs(
        limit: CycleCalculationService.historyLogLimit,
      );
      logs = loadedLogs
          .where(
            (log) => log.userId == _currentUserId || log.userId == 'local-user',
          )
          .toList();
      final canonicalHistory = await _canonicalHistoryLoader(_currentUserId);
      canonicalEpisodes = canonicalHistory.episodes;
      _canonicalHistoryComplete = canonicalHistory.complete;
      statedBaseline = await _statedBaselineLoader(_currentUserId);
      final today = calendarDay(AppClock.now());
      _summary = _summarize(today);
      _summaryDay = today;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveLog(
    CycleLogFormData formData, {
    CycleLog? existingLog,
  }) async {
    final validationMessage = formData.validate();
    if (validationMessage != null) {
      throw FormatException(validationMessage);
    }

    // Logging/sync hardening (proposed): the legacy sheet never overwrites
    // the mirror of a canonical observation — doing so would make the two
    // read models disagree (the observation itself is the fact, and is
    // corrected through the Calendar's correction flow). Only rows that
    // could be a mirror (a provenance the projection writes) are checked;
    // an undeterminable answer (offline) does not block a local edit.
    // Round-2 hardening (proposed): only an edit of the mirrored FACTS —
    // the flow or the day — is blocked. Symptoms and notes are not part of
    // the canonical observation's fact, and the "Symptoms & notes" sheet
    // is the only place she can add them to a day she logged bleeding on;
    // blocking those too left her unable to log cramps on any period day.
    final changesMirroredFact =
        existingLog != null &&
        (formData.flow != existingLog.flow ||
            formData.date == null ||
            calendarDaysBetween(existingLog.date, formData.date!) != 0);
    if (existingLog != null &&
        changesMirroredFact &&
        existingLog.dataProvenance != CycleEntryProvenance.legacyUnverified &&
        await _canonicalMirrorChecker(existingLog.id) == true) {
      throw const CanonicalMirrorEditBlockedException();
    }

    await loadCurrentUser();
    final userId = existingLog?.userId ?? _currentUserId;
    final log = formData.toCycleLog(
      userId: userId,
      id: existingLog?.id,
      dataProvenance: existingLog?.dataProvenance,
      today: AppClock.now(),
    );

    lastSaveSyncStatus = await _repository.saveCycleLog(log);
    await loadLogs();
  }

  /// Retries any locally-pending logs against the remote — called from
  /// app start and app resume (see NiswahHomeShell in main.dart), which is
  /// what makes the "backs up automatically" promise in [saveLog]'s
  /// warning actually true rather than aspirational copy.
  Future<void> retryPendingSync() async {
    final result = await _repository.syncPendingLogs();
    if (result.synced > 0) {
      await loadLogs();
    }
  }

  AuthRepositoryImpl? _safeAuthRepository() {
    try {
      return AuthRepositoryImpl();
    } on StateError {
      return null;
    } catch (_) {
      return null;
    }
  }

  void updatePhaseFilter(CyclePhase? phase) {
    selectedPhase = phase;
    notifyListeners();
  }
}
