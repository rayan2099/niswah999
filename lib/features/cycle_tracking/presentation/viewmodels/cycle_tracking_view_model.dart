import 'package:flutter/foundation.dart';

import '../../../../core/utils/app_clock.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../data/repositories/cycle_tracking_repository_impl.dart';
import '../../domain/controllers/cycle_tracking_controller.dart';
import '../../domain/entities/bleeding_episode.dart';
import '../../domain/entities/cycle_log.dart';
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
  }) : _repository = repository ?? CycleTrackingRepositoryImpl(),
       _canonicalMirrorChecker =
           canonicalMirrorChecker ?? _defaultCanonicalMirrorChecker,
       _canonicalEpisodeLoader =
           canonicalEpisodeLoader ?? _defaultCanonicalEpisodeLoader,
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
  /// and never a fabricated value.
  static Future<List<CanonicalEpisodeTiming>> _defaultCanonicalEpisodeLoader(
    String userId,
  ) async {
    if (userId == 'local-user') return const [];
    try {
      final result = await BleedingEpisodeRepositoryImpl().getEpisodesForUser(
        userId,
      );
      return (result.dataOrNull ?? const [])
          .map(
            (episode) => CanonicalEpisodeTiming(
              startDate: episode.startDate,
              endDate: episode.endDate,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  final Future<List<CanonicalEpisodeTiming>> Function(String userId)
  _canonicalEpisodeLoader;

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
  final CycleCalculationService _calculationService =
      const CycleCalculationService();

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
  CycleTrackingSummary summary = const CycleTrackingSummary(
    averageCycleLength: null,
    averagePeriodLength: null,
    lastCycleStart: null,
    currentPhase: CyclePhase.follicular,
    fertileWindow: FertileWindow(start: null, end: null, peakDay: null),
  );
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
  CycleCalculationResult get cycleCalculation => _calculationService.calculate(
    logs,
    asOf: AppClock.now(),
    canonicalEpisodes: canonicalEpisodes,
    statedBaseline: statedBaseline,
  );

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
      final loadedLogs = await _repository.getCycleLogs();
      logs = loadedLogs
          .where(
            (log) => log.userId == _currentUserId || log.userId == 'local-user',
          )
          .toList();
      canonicalEpisodes = await _canonicalEpisodeLoader(_currentUserId);
      statedBaseline = await _statedBaselineLoader(_currentUserId);
      summary = _controller.summarizeHistory(
        logs,
        canonicalEpisodes: canonicalEpisodes,
        statedBaseline: statedBaseline,
      );
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
    if (existingLog != null &&
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
