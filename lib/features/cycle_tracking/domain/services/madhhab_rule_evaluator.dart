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

  /// The canonical version identifier for this engine's rule *values*
  /// (the durations below — not the surrounding Dart code structure).
  /// Mirrors `fiqh_source_registry.json`'s own `_meta.generated` date,
  /// since that registry and these values were produced together in the
  /// same Source Governance wave.
  ///
  /// Written explicitly into every `madhhab_history` row by
  /// `MadhhabController._recordHistory` — never left to a SQL column
  /// default — specifically so a future change to the values below is
  /// structurally forced to also bump this constant (adversarial review,
  /// 2026-10-07: an earlier draft only had this version living in the
  /// migration's `DEFAULT` clause, which nothing in this file ever wrote
  /// explicitly, making it cosmetic — a real ruleset change would have
  /// silently kept writing the old, now-wrong version string forever).
  /// This is what lets a future reader of `madhhab_history` distinguish
  /// "the user changed Madhhab" (new row, same `ruleset_version`) from
  /// "the same Madhhab now means something different" (new row, new
  /// `ruleset_version`, same `new_madhhab` as some prior row).
  static const String rulesetVersion = 'v1-2026-09-09';

  /// The minimum duration of bleeding each madhhab recognizes as Haid.
  /// Extracted as a named constant (rather than inlined in [evaluate])
  /// so UI copy describing each madhhab (e.g. [MadhhabSelector]) derives
  /// from the exact same value the engine itself uses, instead of a
  /// separately hand-typed number that could silently drift from it.
  static Duration minimumHaidFor(Madhhab madhhab) => switch (madhhab) {
    Madhhab.hanafi => const Duration(hours: 72),
    Madhhab.shafii ||
    Madhhab.hanbali ||
    Madhhab.maliki => const Duration(hours: 24),
  };

  /// The maximum duration of bleeding each madhhab recognizes as Haid.
  /// See [minimumHaidFor] for why this is a named, reusable constant.
  static Duration maximumHaidFor(Madhhab madhhab) => madhhab == Madhhab.hanafi
      ? const Duration(hours: 240)
      : const Duration(days: 15);

  MadhhabRuleResult evaluate({
    required Madhhab madhhab,
    required bool hasSufficientHistory,
    required bool isBleeding,
    required Duration bleedingDuration,
    Duration? purityBefore,
    Duration? personalHabit,
  }) {
    final minimum = minimumHaidFor(madhhab);
    final maximum = maximumHaidFor(madhhab);
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
