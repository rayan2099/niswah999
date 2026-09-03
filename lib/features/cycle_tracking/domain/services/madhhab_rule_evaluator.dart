enum Madhhab { hanafi, maliki, shafii, hanbali }

enum FiqhCycleState { insufficientHistory, tahara, haid, needsAdvisory }

class MadhhabRuleResult {
  const MadhhabRuleResult({
    required this.state,
    required this.minimumHaid,
    required this.maximumHaid,
    required this.minimumPurity,
    this.personalHabit,
    this.isWithinPersonalHabit,
  });

  final FiqhCycleState state;
  final Duration minimumHaid;
  final Duration maximumHaid;
  final Duration minimumPurity;
  final Duration? personalHabit;
  final bool? isWithinPersonalHabit;
}

/// Applies the reviewed duration boundaries to factual bleeding data.
/// Selecting another Madhhab never changes the underlying logs.
class MadhhabRuleEvaluator {
  const MadhhabRuleEvaluator();

  MadhhabRuleResult evaluate({
    required Madhhab madhhab,
    required bool hasSufficientHistory,
    required bool isBleeding,
    required Duration bleedingDuration,
    Duration? purityBefore,
    Duration? personalHabit,
  }) {
    final minimum = switch (madhhab) {
      Madhhab.hanafi => const Duration(hours: 72),
      Madhhab.shafii || Madhhab.hanbali => const Duration(hours: 24),
      Madhhab.maliki => const Duration(hours: 24),
    };
    final maximum = madhhab == Madhhab.hanafi
        ? const Duration(hours: 240)
        : const Duration(days: 15);
    const minimumPurity = Duration(days: 15);

    final FiqhCycleState state;
    if (!hasSufficientHistory) {
      state = FiqhCycleState.insufficientHistory;
    } else if (!isBleeding) {
      state = FiqhCycleState.tahara;
    } else if (madhhab == Madhhab.hanafi &&
        purityBefore != null &&
        purityBefore < minimumPurity) {
      state = FiqhCycleState.needsAdvisory;
    } else if (bleedingDuration < minimum || bleedingDuration > maximum) {
      state = FiqhCycleState.needsAdvisory;
    } else {
      state = FiqhCycleState.haid;
    }

    return MadhhabRuleResult(
      state: state,
      minimumHaid: minimum,
      maximumHaid: maximum,
      minimumPurity: minimumPurity,
      personalHabit: madhhab == Madhhab.maliki ? personalHabit : null,
      isWithinPersonalHabit: madhhab == Madhhab.maliki && personalHabit != null
          ? bleedingDuration <= personalHabit
          : null,
    );
  }
}
