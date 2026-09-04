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
  String? warningMessage;

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

    final synced = await _repository.saveCycleLog(log);
    warningMessage = synced
        ? null
        : 'Saved on this device, but could not be backed up to your account yet. It will sync automatically once you\'re back online.';
    await loadLogs();
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
