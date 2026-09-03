import 'package:niswah/core/models/cycle_log.dart';
import 'package:niswah/core/models/madhhab_type.dart';

class FiqhCalculationEngine {
  // Hanafi Limits
  static const int _hanafiMinMensesDays = 3;
  static const int _hanafiMaxMensesDays = 10;
  static const int _hanafiMinPurityDays = 15;

  // Shafi'i / Hanbali Limits
  static const int _shafiiHanbaliMinMensesHours = 24; // 1 day
  static const int _shafiiHanbaliMaxMensesDays = 15;
  static const int _shafiiHanbaliMinPurityDays = 15;

  // Maliki Limits - will implement later based on habitual tracking

  /// Checks if the bleeding duration falls within the legal bounds of the specified Madhhab.
  bool isValidMenses(Duration duration, MadhhabType madhhab) {
    final int bleedingDays = duration.inDays;
    final int bleedingHours = duration.inHours;

    switch (madhhab) {
      case MadhhabType.hanafi:
        return bleedingDays >= _hanafiMinMensesDays &&
            bleedingDays <= _hanafiMaxMensesDays;
      case MadhhabType.maliki:
        // Maliki rules are more complex, often relying on habit and a maximum of 15 days.
        // For simplicity, we'll assume it's valid if it's within a reasonable range (e.g., 1-15 days).
        // A more robust implementation would involve detailed habit tracking.
        return bleedingDays >= 1 && bleedingDays <= 15;
      case MadhhabType.shafii:
      case MadhhabType.hanbali:
        return bleedingHours >= _shafiiHanbaliMinMensesHours &&
            bleedingDays <= _shafiiHanbaliMaxMensesDays;
    }
  }

  /// Computes the predicted next start date and expected window based on her logged history and school rules.
  /// This is a simplified prediction. Real-world cycle prediction can be more complex.
  List<DateTime> calculateNextPredictedWindow(
    List<CycleLog> history,
    MadhhabType madhhab,
  ) {
    if (history.isEmpty) {
      return []; // Cannot predict without history
    }

    // Sort history by start date in descending order (most recent first)
    history.sort((a, b) => b.startDate.compareTo(a.startDate));

    // Take the last few cycles to calculate average length
    // For a more accurate prediction, more sophisticated algorithms might be needed
    final relevantHistory = history.take(3).toList(); // Consider last 3 cycles

    if (relevantHistory.length < 2) {
      return []; // Need at least two cycles to calculate an average
    }

    int totalCycleLengthDays = 0;
    int completedCycles = 0;

    for (int i = 0; i < relevantHistory.length - 1; i++) {
      final currentCycle = relevantHistory[i];
      final previousCycle = relevantHistory[i + 1];

      if (previousCycle.startDate != null) {
        final cycleLength = currentCycle.startDate
            .difference(previousCycle.startDate)
            .inDays;
        totalCycleLengthDays += cycleLength;
        completedCycles++;
      }
    }

    if (completedCycles == 0) {
      return []; // No complete cycles to average
    }

    final averageCycleLength = totalCycleLengthDays ~/ completedCycles;

    // Predict next start date
    final lastCycle = history.first;
    final predictedStartDate = lastCycle.startDate.add(
      Duration(days: averageCycleLength),
    );

    // For prediction window, let's assume a +/- 2 day window around the predicted start date
    final predictionWindowStart = predictedStartDate.subtract(
      const Duration(days: 2),
    );
    final predictionWindowEnd = predictedStartDate.add(const Duration(days: 2));

    return [predictionWindowStart, predictionWindowEnd];
  }

  /// Flags days exceeding the maximum allowable menses limit as irregular bleeding (Istihadah).
  /// bleedingDays is expected to be a list of consecutive bleeding days.
  List<DateTime> detectIstihadah(
    List<DateTime> bleedingDays,
    MadhhabType madhhab,
  ) {
    if (bleedingDays.isEmpty) {
      return [];
    }

    bleedingDays.sort(); // Ensure days are sorted chronologically

    final Duration totalBleedingDuration =
        bleedingDays.last.difference(bleedingDays.first) +
        const Duration(days: 1); // +1 to include the last day

    int maxMensesDays;
    switch (madhhab) {
      case MadhhabType.hanafi:
        maxMensesDays = _hanafiMaxMensesDays;
        break;
      case MadhhabType.maliki:
        maxMensesDays = 15; // Maliki usually has a max of 15 days
        break;
      case MadhhabType.shafii:
      case MadhhabType.hanbali:
        maxMensesDays = _shafiiHanbaliMaxMensesDays;
        break;
    }

    if (totalBleedingDuration.inDays > maxMensesDays) {
      // Identify days that are Istihadah
      final istihadahStartDayIndex =
          bleedingDays.length - (totalBleedingDuration.inDays - maxMensesDays);
      return bleedingDays.sublist(
        istihadahStartDayIndex.clamp(0, bleedingDays.length),
      );
    } else {
      return [];
    }
  }
}
