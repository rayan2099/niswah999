import 'package:flutter/foundation.dart';

import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/pregnancy_status_controller.dart';
import '../../data/repositories/pregnancy_tracking_repository_impl.dart';
import '../../domain/controllers/pregnancy_calculator.dart';
import '../../domain/entities/pregnancy_milestone.dart';
import '../../domain/repositories/pregnancy_tracking_repository.dart';

// DORMANT — only consumed by the equally-dormant PregnancyTrackingScreen.
// See that file's header comment for the full evidence trail on why this
// is kept in place, unwired, rather than deleted or forced into
// navigation (Pregnancy Tracking Product Integration wave, 2026-09-06).

class PregnancyTrackingViewModel extends ChangeNotifier {
  PregnancyTrackingViewModel({PregnancyTrackingRepository? repository})
    : _repository = repository ?? PregnancyTrackingRepositoryImpl();

  final PregnancyTrackingRepository _repository;

  bool isLoading = false;
  String? errorMessage;
  List<PregnancyMilestone> milestones = const <PregnancyMilestone>[];

  bool hydrationTargetMet = false;
  bool movementLogged = false;
  bool symptomsTracked = false;
  String notes = '';

  /// Whether the user has an active pregnancy to track at all — read from
  /// [PregnancyStatusController], the same source the dashboard's own
  /// pregnancy overview uses. Previously this ViewModel never checked this
  /// and always displayed a fabricated week/due-date regardless of whether
  /// the user had ever indicated they were pregnant.
  bool get isTrackingPregnancy => PregnancyStatusController.instance.isPregnant;

  /// Real current week from the user's own activation state — was
  /// previously always `DateTime.now() - 30 weeks`, a hardcoded fake value
  /// with no connection to any user input.
  int get currentWeek => PregnancyStatusController.instance.currentWeek;

  /// An effective LMP/due-date derived from the real current week, for
  /// [PregnancyCalculator]'s existing week-based content lookup —
  /// approximate by construction (this calculator only ever produced
  /// approximate trimester-level content, matching its original design),
  /// but now grounded in the user's real activation state rather than a
  /// constant.
  DateTime get dueDate =>
      DateTime.now().add(Duration(days: (40 - currentWeek) * 7));

  PregnancyTrimester get currentTrimester => currentMilestone.trimester;

  PregnancyMilestoneSnapshot get currentMilestone =>
      PregnancyCalculator.milestoneForDueDate(
        dueDate: dueDate,
        now: DateTime.now(),
      );

  String? get _currentUserId =>
      NiswahSupabase.clientOrNull?.auth.currentUser?.id;

  Future<void> loadMilestones() async {
    await PregnancyStatusController.instance.load();
    final userId = _currentUserId;
    if (userId == null) {
      milestones = const <PregnancyMilestone>[];
      notifyListeners();
      return;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      milestones = await _repository.getMilestonesForUser(userId);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveDailyTracker() async {
    final userId = _currentUserId;
    if (userId == null) {
      errorMessage = 'You must be signed in to save an update.';
      notifyListeners();
      return;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final label = currentMilestone.label;
      final summary = notes.isEmpty
          ? '${currentMilestone.summary} Hydration goal: ${hydrationTargetMet ? 'met' : 'pending'}. Movement: ${movementLogged ? 'logged' : 'not logged'}. Symptoms: ${symptomsTracked ? 'tracked' : 'not tracked'}.'
          : notes;

      final milestone = PregnancyMilestone(
        id: '${userId}_${DateTime.now().toIso8601String()}',
        userId: userId,
        week: currentWeek,
        trimester: currentTrimester,
        label: label,
        summary: summary,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _repository.saveMilestone(milestone);
      milestones = await _repository.getMilestonesForUser(userId);
      notes = '';
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void setHydrationTargetMet(bool value) {
    hydrationTargetMet = value;
    notifyListeners();
  }

  void setMovementLogged(bool value) {
    movementLogged = value;
    notifyListeners();
  }

  void setSymptomsTracked(bool value) {
    symptomsTracked = value;
    notifyListeners();
  }

  void updateNotes(String value) {
    notes = value;
    notifyListeners();
  }
}
