import 'package:flutter/foundation.dart';

import 'dart:async';

import '../../../../core/utils/app_clock.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../data/repositories/cycle_tracking_repository_impl.dart';
import '../../domain/controllers/cycle_tracking_controller.dart';
import '../../domain/entities/cycle_log.dart';
import '../../domain/repositories/cycle_tracking_repository.dart';
import '../../domain/services/cycle_calculation_service.dart';
import '../models/cycle_log_form_data.dart';
import '../../data/local/prediction_history_review_store.dart';
import '../../data/local/secure_prediction_history_review_store.dart';
import '../../domain/entities/prediction_history_review.dart';

class CycleTrackingViewModel extends ChangeNotifier {
  CycleTrackingViewModel({
    CycleTrackingRepository? repository,
    AuthRepositoryImpl? authRepository,
    PredictionHistoryReviewStore? predictionReviewStore,
    Future<List<CanonicalEpisodeTiming>> Function(String userId)?
    canonicalEpisodeLoader,
  }) : _repository = repository ?? CycleTrackingRepositoryImpl(),
       _predictionReviewStore =
           predictionReviewStore ?? createPredictionHistoryReviewStore(),
       _canonicalEpisodeLoader =
           canonicalEpisodeLoader ?? _defaultCanonicalEpisodeLoader {
    _authRepository = authRepository;
    _reviewSubscription = PredictionHistoryReviewStore.changes.listen((owner) {
      if (owner != _currentUserId || _disposed) return;
      if (_savingHistoryReview) {
        _reviewChangedWhileSaving = true;
      } else {
        unawaited(loadLogs());
      }
    });
  }

  /// Canonical episode start/end DATES only (never a flow) — see
  /// [CanonicalEpisodeTiming]. Incomplete reads fail explicitly so predictions
  /// cannot silently fall back to the potentially incomplete legacy table.
  static Future<List<CanonicalEpisodeTiming>> _defaultCanonicalEpisodeLoader(
    String userId,
  ) async {
    if (userId == 'local-user') return const [];
    final result = await BleedingEpisodeRepositoryImpl().getEpisodesForUser(
      userId,
    );
    if (!result.isCleanSuccess) {
      throw StateError('Canonical cycle history could not be verified');
    }
    return (result.dataOrNull ?? const [])
        .map(
          (episode) => CanonicalEpisodeTiming(
            startDate: episode.startDate,
            endDate: episode.endDate,
          ),
        )
        .toList();
  }

  final Future<List<CanonicalEpisodeTiming>> Function(String userId)
  _canonicalEpisodeLoader;

  final CycleTrackingRepository _repository;
  final PredictionHistoryReviewStore _predictionReviewStore;
  late final StreamSubscription<String> _reviewSubscription;
  bool _disposed = false;
  bool _savingHistoryReview = false;
  bool _reviewChangedWhileSaving = false;
  int _loadGeneration = 0;
  int _userLoadGeneration = 0;
  String? _summaryOwner;
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
  );

  List<CycleLog> get filteredLogs =>
      _controller.filterLogsByPhase(logs, selectedPhase);

  Future<void> loadCurrentUser() async {
    final generation = ++_userLoadGeneration;
    AppUser? nextUser;
    try {
      final activeAuthRepository = _authRepository ?? _safeAuthRepository();
      nextUser = await activeAuthRepository?.currentUser;
    } catch (_) {
      nextUser = null;
    }
    if (_disposed || generation != _userLoadGeneration) return;
    final nextOwner = nextUser?.id ?? 'local-user';
    if (nextOwner != _currentUserId) {
      logs = const [];
      canonicalEpisodes = const [];
      _summaryOwner = null;
      summary = _controller.summarizeHistory(const []);
    }
    _currentUser = nextUser;
    _currentUserId = nextOwner;
    notifyListeners();
  }

  Future<void> loadLogs() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    isLoading = true;
    errorMessage = null;
    if (!_disposed) notifyListeners();

    try {
      await loadCurrentUser();
      if (_disposed || generation != _loadGeneration) return;
      final owner = _currentUserId;
      final loadedLogs = await _repository.getCycleLogs();
      final nextLogs = loadedLogs
          .where((log) => log.userId == owner || log.userId == 'local-user')
          .toList();
      final nextEpisodes = await _canonicalEpisodeLoader(owner);
      var reviews = <PredictionHistoryReview>[];
      var reviewsVerified = true;
      try {
        reviews = await _predictionReviewStore.load(owner);
      } catch (_) {
        reviewsVerified = false;
      }
      if (_disposed ||
          generation != _loadGeneration ||
          owner != _currentUserId) {
        return;
      }
      logs = nextLogs;
      canonicalEpisodes = nextEpisodes;
      _summaryOwner = owner;
      summary = _controller.summarizeHistory(
        logs,
        canonicalEpisodes: canonicalEpisodes,
        historyReviews: reviews,
        historyVerified: reviewsVerified,
      );
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      errorMessage = error.toString();
      // Do not retain another account's or a prior fetch's predictions.
      canonicalEpisodes = const [];
      logs = const [];
      _summaryOwner = null;
      summary = const CycleTrackingSummary(
        averageCycleLength: null,
        averagePeriodLength: null,
        lastCycleStart: null,
        currentPhase: CyclePhase.follicular,
        fertileWindow: FertileWindow(start: null, end: null, peakDay: null),
      );
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    unawaited(_reviewSubscription.cancel());
    super.dispose();
  }

  Future<void> savePredictionHistoryReview(
    PredictionHistoryReview review,
  ) async {
    if (_disposed || _savingHistoryReview) {
      throw StateError('History review is no longer active or is saving');
    }
    final owner = _summaryOwner;
    await loadCurrentUser();
    if (_disposed ||
        _savingHistoryReview ||
        owner == null ||
        owner != _currentUserId ||
        !summary.periodPrediction.reviewGaps.any(
          (gap) => gap.key == review.key,
        )) {
      throw StateError('History changed; reload before reviewing');
    }
    _savingHistoryReview = true;
    try {
      await _predictionReviewStore.save(owner, review);
      do {
        _reviewChangedWhileSaving = false;
        await loadLogs();
      } while (_reviewChangedWhileSaving &&
          !_disposed &&
          owner == _currentUserId);
    } finally {
      _savingHistoryReview = false;
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
    if (!_disposed) notifyListeners();
  }
}
