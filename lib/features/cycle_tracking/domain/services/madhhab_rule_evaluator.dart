enum Madhhab { hanafi, maliki, shafii, hanbali }

/// [madhhabUnresolved] (Fiqh Remediation Wave 1, AUTH-005/AUTH-010's
/// Section E): the explicit, non-crashing, non-fabricating result for
/// "the user is currently bleeding, but no madhhab is SELECTED (she is
/// UNSET or UNKNOWN), so no fiqh classification can be produced without
/// inventing one." Callers must render this as a clear "select your
/// Madhhab to see this" state — never silently substitute [haid] under an
/// assumed madhhab, and never crash. Not applicable to [tahara] (a user
/// who isn't bleeding is pure regardless of madhhab), so a null/unresolved
/// madhhab never blocks that determination.
enum FiqhCycleState {
  insufficientHistory,
  tahara,
  haid,
  needsAdvisory,
  madhhabUnresolved,
}

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

/// Applies each madhhab's duration boundaries to factual bleeding data.
/// Selecting another Madhhab never changes the underlying logs.
///
/// Source status (Source Governance wave, 2026-09-09): these boundary
/// values are engineering-derived from general Islamic-studies knowledge,
/// not yet independently verified against a primary source by a qualified
/// reviewer — see production-readiness-results/fiqh-engine/fiqh_source_registry.json
/// (rule IDs FR-001/FR-002/FR-003) for the current, honestly-labeled
/// source status of each value below. Do not describe these as
/// "reviewed" until that registry says so.
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
