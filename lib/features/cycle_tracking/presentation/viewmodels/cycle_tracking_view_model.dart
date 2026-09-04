import 'package:flutter/foundation.dart';

import '../../../../core/utils/app_clock.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../data/repositories/cycle_tracking_repository_impl.dart';
import '../../domain/controllers/cycle_tracking_controller.dart';
import '../../domain/entities/cycle_log.dart';
import '../../domain/repositories/cycle_tracking_repository.dart';
import '../../domain/services/cycle_calculation_service.dart';
import '../models/cycle_log_form_data.dart';

class CycleTrackingViewModel extends ChangeNotifier {
  CycleTrackingViewModel({
    CycleTrackingRepository? repository,
    AuthRepositoryImpl? authRepository,
  }) : _repository = repository ?? CycleTrackingRepositoryImpl() {
    _authRepository = authRepository;
  }

  final CycleTrackingRepository _repository;
  AuthRepositoryImpl? _authRepository;
  final CycleTrackingController _controller = CycleTrackingController();
  final CycleCalculationService _calculationService =
      const CycleCalculationService();

  String _currentUserId = 'local-user';
  AppUser? _currentUser;
  CyclePhase? selectedPhase;

  List<CycleLog> logs = const <CycleLog>[];
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
  CycleCalculationResult get cycleCalculation =>
      _calculationService.calculate(logs, asOf: AppClock.now());

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
      summary = _controller.summarizeHistory(logs);
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

    await loadCurrentUser();
    final userId = existingLog?.userId ?? _currentUserId;
    final log = formData.toCycleLog(userId: userId, id: existingLog?.id);

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
