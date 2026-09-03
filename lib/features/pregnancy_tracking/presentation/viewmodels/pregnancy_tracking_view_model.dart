import 'package:flutter/foundation.dart';

import '../../data/repositories/pregnancy_tracking_repository_impl.dart';
import '../../domain/controllers/pregnancy_calculator.dart';
import '../../domain/entities/pregnancy_milestone.dart';
import '../../domain/repositories/pregnancy_tracking_repository.dart';

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

  DateTime get lmp => DateTime.now().subtract(const Duration(days: 30 * 7));

  DateTime get dueDate => lmp.add(const Duration(days: 280));

  int get currentWeek =>
      PregnancyCalculator.currentWeekFromLmp(lmp: lmp, now: DateTime.now());

  PregnancyTrimester get currentTrimester => currentMilestone.trimester;

  PregnancyMilestoneSnapshot get currentMilestone =>
      PregnancyCalculator.milestoneForDueDate(
        dueDate: dueDate,
        now: DateTime.now(),
      );

  Future<void> loadMilestones({String userId = 'demo-user'}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final latest = await _repository.getMilestonesForUser(userId);
      milestones = latest;
      if (latest.isNotEmpty) {
        final latestMilestone = latest.first;
        hydrationTargetMet = latestMilestone.summary.toLowerCase().contains(
          'hydration',
        );
        movementLogged = latestMilestone.label.toLowerCase().contains(
          'movement',
        );
        symptomsTracked = latestMilestone.summary.toLowerCase().contains(
          'symptom',
        );
      }
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveDailyTracker({String userId = 'demo-user'}) async {
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
