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

  /// `null` for Maliki — see [MadhhabRuleEvaluator.minimumHaidFor].
  final Duration? minimumHaid;
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
  ///
  /// Returns `null` for Maliki — **explicit semantic, not `Duration.zero`**.
  /// Evidence-based correction, Founder Decision FD-7 (2026-10-15; see
  /// `FOUNDER_DECISIONS.md` and
  /// `production-readiness-results/fiqh-engine/ENGINE_TO_KB_ATOM_CROSSWALK.md`):
  /// the engine previously shared Shafi'i/Hanbali's 24-hour minimum with
  /// Maliki. The Maliki-specific KB atom for this exact proposition
  /// (`MLK-HAID-04`, `LOCATOR_VERIFIED`/`PRODUCTION_ELIGIBLE`) states the
  /// Maliki school recognizes no minimum duration measured by time at
  /// all for worship rulings — even a single, brief discharge can count
  /// as Haid — corroborated by independent external sources per FD-7. A
  /// zero `Duration` would still assert "there is a bound, and it is
  /// zero"; `null` means "this bound does not exist for this madhhab",
  /// which is the actual claim. [evaluate] skips the lower-bound check
  /// entirely when this is `null`, for Maliki only — Hanafi/Shafi'i/
  /// Hanbali are unaffected.
  static Duration? minimumHaidFor(Madhhab madhhab) => switch (madhhab) {
    Madhhab.hanafi => const Duration(hours: 72),
    Madhhab.shafii || Madhhab.hanbali => const Duration(hours: 24),
    Madhhab.maliki => null,
  };

  /// The maximum duration of bleeding each madhhab recognizes as Haid.
  /// See [minimumHaidFor] for why this is a named, reusable constant.
  /// Unaffected by FD-7 — only [minimumHaidFor] (Maliki) and
  /// [minimumPurityFor] (Hanbali) changed.
  static Duration maximumHaidFor(Madhhab madhhab) => madhhab == Madhhab.hanafi
      ? const Duration(hours: 240)
      : const Duration(days: 15);

  /// The minimum complete purity (tuhr) interval each madhhab requires
  /// between two menstrual episodes before a later one is recognized as
  /// its own fresh Haid rather than a resumption of the same one.
  ///
  /// Evidence-based correction, Founder Decision FD-7 (2026-10-15): the
  /// engine previously used one universal 15-day constant for all four
  /// madhahib. The Hanbali-specific KB atom for this exact proposition
  /// (`HNB-HAID-06`, `LOCATOR_VERIFIED`/`PRODUCTION_ELIGIBLE`, citing
  /// Kashshaf al-Qina') states **thirteen days**, not fifteen, for
  /// Hanbali specifically — corroborated by independent external
  /// sources per FD-7. Hanafi/Maliki/Shafi'i remain at 15 days; this is
  /// a Madhhab-specific correction, not a generalized rule change. Only
  /// Hanafi's branch of [evaluate] currently gates on this value as a
  /// branch condition (the pre-existing, separately-tracked `FR-003`
  /// enforcement asymmetry) — this function still returns each
  /// madhhab's own correct value so that gap, when closed, inherits the
  /// right number per madhhab instead of a single wrong-for-Hanbali
  /// constant.
  static Duration minimumPurityFor(Madhhab madhhab) =>
      madhhab == Madhhab.hanbali
          ? const Duration(days: 13)
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
    final minimumPurity = minimumPurityFor(madhhab);

    final FiqhCycleState state;
    if (!hasSufficientHistory) {
      state = FiqhCycleState.insufficientHistory;
    } else if (!isBleeding) {
      state = FiqhCycleState.tahara;
    } else if (madhhab == Madhhab.hanafi &&
        purityBefore != null &&
        purityBefore < minimumPurity) {
      state = FiqhCycleState.needsAdvisory;
    } else if ((minimum != null && bleedingDuration < minimum) ||
        bleedingDuration > maximum) {
      // Maliki has no time-based minimum (minimum == null) — only the
      // maximum bound can trigger needsAdvisory for Maliki. Hanafi/
      // Shafi'i/Hanbali are unaffected: their real minimum still gates
      // exactly as before.
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
