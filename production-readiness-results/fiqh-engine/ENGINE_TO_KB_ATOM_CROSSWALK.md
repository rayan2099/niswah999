# Engine Rule → 180-Atom KB Evidence Crosswalk

Built 2026-10-15, prerequisite to commissioning scholar review of
`MadhhabRuleEvaluator`'s hardcoded duration thresholds (see
`DEFINITION_OF_DONE_BEFORE_LAUNCH.md`, Section 4). **This file does not
close that governance blocker.** It determines, atom by atom, what
evidence already exists in the 180-Fiqh-atom KB set
(`PRODUCTION_DISPOSITION_MASTER.csv` / `ATOMIC_KNOWLEDGE_MATRIX.csv`) for
each hardcoded value, so a scholar reviews exactly what needs reviewing
instead of starting from zero — and so any discrepancy between the
engine and the KB's own evidence is caught *before* a scholar is asked
to referee two different sets of numbers without being told they
disagree.

**Update (2026-10-15, same day): the 2 discrepancies this crosswalk
identified have since been corrected in code**, under Founder Decision
FD-7 (`FOUNDER_DECISIONS.md`) — an evidence-based governance decision to
fix them without waiting for scholar review, given the internal KB
evidence here plus independently-corroborating external sources the
founder cites in FD-7. See `madhhab_rule_evaluator.dart`'s
`minimumHaidFor`/`minimumPurityFor` and the "FD-7" test group in
`test/services/multi_madhhab_engine_test.dart`. This does **not** change
the rest of this document, which remains the accurate record of what
was found and why — it only means the two "Finding" sections below are
now implemented corrections, not just open findings. The broader
question (scholar review of the engine's thresholds in general) remains
open and unaffected.

This is a **different, more specific** crosswalk than the pre-existing
`fiqh_rule_source_matrix.md`, which maps the same engine rules (`FR-001`
etc.) to the separate 16-source *reference-work registry*
(`fiqh_source_registry.json` — book-title-level, e.g. "Hanafi: likely
grounded in Radd al-Muhtar") used for FD-5's unrelated KB-atom/AI-answer
system. This file instead checks the **180-atom production-disposition
set itself** — the one with per-atom primary locators, evidence
statuses, and production dispositions — for atoms whose proposition
states the *exact same numeric claim* the engine hardcodes.

## Method

For each of `MadhhabRuleEvaluator`'s hardcoded values
(`lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart:76-99`),
searched all 68 `*-HAID-*` atoms in `PRODUCTION_DISPOSITION_MASTER.csv`
(17 per madhhab) for a proposition stating the same duration. Every
match below was found in the **01–19 numbering band's 04/05/06 slots**
across all four madhhabs — not a coincidence; those three atom numbers
consistently hold "minimum Haid," "maximum Haid," and "minimum purity"
in this KB's own internal convention, independently of this crosswalk.

## Hanafi

| Engine value (`madhhab_rule_evaluator.dart`) | Matching atom | Atom's proposition | Evidence status | Production disposition | Primary locator |
|---|---|---|---|---|---|
| `minimumHaidFor(hanafi)` = 72h (3 days) | `HNF-HAID-04` | "The Hanafi minimum for Haid is three complete days with their nights." | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | رد المحتار، باب الحيض (islamweb.net/ar/library/content/27/369) + بدائع الصنائع (secondary) |
| `maximumHaidFor(hanafi)` = 240h (10 days) | `HNF-HAID-05` | "The Hanafi maximum for Haid is ten complete days with their nights." | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | رد المحتار، باب الحيض (same primary) + بدائع الصنائع, الاستحاضة (secondary) |
| `minimumPurity` = 15 days (enforced for Hanafi) | `HNF-HAID-06` | "The minimum complete purity interval separating two Haid episodes is fifteen days and nights." | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | رد المحتار، باب الحيض، p.286 + بدائع الصنائع (secondary) |

**Result: exact match on all 3 values, all production-eligible evidence.** A scholar reviewing Hanafi need only confirm these 3 already-located, already-cited atoms — no new source search required for the numeric thresholds themselves.

## Shafi'i

| Engine value | Matching atom | Atom's proposition | Evidence status | Production disposition | Primary locator |
|---|---|---|---|---|---|
| `minimumHaidFor(shafii)` = 24h (1 day) | `SHF-HAID-04` | "The relied-upon Shafi'i minimum Haid duration is one day and one night (24 hours)." | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | المجموع، أقل الحيض، ج2 ص404 |
| `maximumHaidFor(shafii)` = 15 days | `SHF-HAID-05` | "The Shafi'i maximum Haid duration is fifteen days." | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | المجموع، أقل الحيض، ج2 ص404 |
| `minimumPurity` = 15 days (computed, not gated for Shafi'i in `evaluate()`) | `SHF-HAID-06` | "The minimum complete purity interval separating two Haid episodes is fifteen days." | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | المجموع، أقل الحيض، ج2 ص404-405 |

**Result: exact match on all 3 values** — `SHF-HAID-04` even states "(24 hours)" verbatim, identical to the engine's own comment style.

## Hanbali

| Engine value | Matching atom | Atom's proposition | Evidence status | Production disposition | Primary locator |
|---|---|---|---|---|---|
| `minimumHaidFor(hanbali)` = 24h (1 day) | `HNB-HAID-04` | "The Hanbali minimum Haid duration in Kashshaf al-Qina' is one day and one night." | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | كشاف القناع، فصل والمبتدأ بها الدم |
| `maximumHaidFor(hanbali)` = 15 days | `HNB-HAID-05` | "The Hanbali maximum Haid duration in the cited source is fifteen days." | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | كشاف القناع، فصل والمبتدأ بها الدم |
| `minimumPurity` = 15 days (computed, not gated for Hanbali in `evaluate()`) | `HNB-HAID-06` | **"The minimum complete purity interval between two distinct Haid episodes is thirteen days in the cited Hanbali text."** | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | كشاف القناع، فصل المعتادة إذا استحيضت + كشاف القناع، أحكام الطهر (secondary) |

**Finding — discrepancy (new, this crosswalk):** the engine hardcodes
one universal `minimumPurity = Duration(days: 15)` constant shared by
all four madhhabs. The Hanbali KB atom for this exact proposition — itself
`LOCATOR_VERIFIED`/`PRODUCTION_ELIGIBLE`, i.e. evidence the KB system
already trusts enough to serve to users elsewhere — states **13 days**,
not 15, for Hanbali specifically. This does not currently misclassify a
live Hanbali user, because `evaluate()` only gates on `minimumPurity` in
the Hanafi branch (`FR-003`'s known, separately-tracked "enforcement
asymmetry," `FIQH-7` in `FIQH_AICTX_findings.md`) — for Hanbali the
value is computed and returned but never used as a branch condition. It
**would** become a live, incorrect-by-the-KB's-own-evidence bug the
moment `FIQH-7` is fixed by simply extending today's Hanafi-only gate to
all four madhhabs without first correcting this specific value. Flag
for scholar review: confirm whether Hanbali's minimum purity is 13 or
15 days, and fix the constant (or add a per-madhhab `minimumPurityFor()`
function mirroring `minimumHaidFor`) before `FIQH-7` is closed.

## Maliki

| Engine value | Matching atom | Atom's proposition | Evidence status | Production disposition | Primary locator |
|---|---|---|---|---|---|
| `minimumHaidFor(maliki)` = 24h (1 day) | `MLK-HAID-04` | **"For worship rulings, the Maliki school has no minimum duration measured by time; even a single discharge/brief occurrence can count as Haid..."** | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | مواهب الجليل، فصل في بيان حكم الحيض والنفاس + مواهب الجليل، باب العدة (secondary) |
| `maximumHaidFor(maliki)` = 15 days | `MLK-HAID-05` | "For a nonpregnant beginner, maximum Haid is fifteen days. For an established habit, the rule uses the longest prior habit plus up to three days of istizhar without exceeding fifteen; pregnancy has separate longer limits." | `SCHOLAR_CLARIFICATION_REQUIRED` | `FAIL_CLOSED` | حاشية الدسوقي، مدة الحيض، ص169-170 |
| `minimumPurity` = 15 days (computed, not gated for Maliki in `evaluate()`) | `MLK-HAID-06` | "The minimum complete purity interval separating menstrual episodes is fifteen days." | `LOCATOR_VERIFIED` | `PRODUCTION_ELIGIBLE` | حاشية الدسوقي، مدة الحيض، ص169 |

**Finding — contradiction (new, this crosswalk, the more serious of the
two):** the engine applies a flat 24-hour (1-day) minimum Haid duration
to Maliki, sharing the exact same code branch as Shafi'i/Hanbali
(`Madhhab.shafii || Madhhab.hanbali || Madhhab.maliki => const
Duration(hours: 24)`). The Maliki KB atom for minimum Haid duration —
`LOCATOR_VERIFIED`/`PRODUCTION_ELIGIBLE` — states the opposite: **Maliki
has no minimum time threshold at all** for worship rulings; even a
brief/single discharge can count as Haid. If the KB atom's evidence is
correct, the engine may currently misclassify a Maliki user whose
bleeding is shorter than 24 hours as `needsAdvisory` (treating her as
not-yet-confirmed-Haid) when her own school's position — per the
located, cited source — would recognize it as Haid outright. This is
the single most consequential finding of this crosswalk: it is not a
documentation gap, it is a specific, cited, already-production-eligible
piece of evidence that appears to directly contradict a live
classification rule, on a question that gates whether a woman is told
she is excused from prayer/fasting. **This must be the first item any
commissioned scholar review examines for Maliki**, ahead of general
re-verification of the other values.

**Secondary finding (lower severity, same madhhab):** `MLK-HAID-05`
(maximum Haid) itself is `SCHOLAR_CLARIFICATION_REQUIRED`/`FAIL_CLOSED`
— i.e. the KB's own governance has already determined this exact
proposition is not yet safe to serve as an authoritative AI answer.
The engine's flat `maximumHaidFor(maliki) = 15 days` only captures the
"nonpregnant beginner" case this atom describes; the atom's own text
shows the real relied-upon rule is habit-and-istizhar-dependent (longest
prior habit + up to 3 days, capped at 15, with a separate longer
pregnancy limit) — a simplification, not a wrong ceiling number, but
one a scholar should confirm is an acceptable V1 approximation given the
engine has no habit-duration input for this purpose (`personalHabit` is
currently informational-only, per `FR-004`/`fiqh_rule_source_matrix.md`,
and does not feed into `maximumHaidFor`).

## Summary table

| Madhhab | Min Haid | Max Haid | Min purity |
|---|---|---|---|
| Hanafi | ✅ exact match (`HNF-HAID-04`, eligible) | ✅ exact match (`HNF-HAID-05`, eligible) | ✅ exact match (`HNF-HAID-06`, eligible) |
| Shafi'i | ✅ exact match (`SHF-HAID-04`, eligible) | ✅ exact match (`SHF-HAID-05`, eligible) | ✅ exact match (`SHF-HAID-06`, eligible) |
| Hanbali | ✅ exact match (`HNB-HAID-04`, eligible) | ✅ exact match (`HNB-HAID-05`, eligible) | ⚠️ **mismatch: atom says 13 days, engine says 15** (`HNB-HAID-06`, eligible) |
| Maliki | 🔴 **contradiction: atom says no time minimum exists, engine says 24h** (`MLK-HAID-04`, eligible) | ⚠️ ceiling number matches but atom (not itself eligible) shows real rule is habit/istizhar-dependent, not a flat constant (`MLK-HAID-05`, fail-closed) | ✅ exact match (`MLK-HAID-06`, eligible) |

## What this means for commissioning scholar review

- **9 of 12 cells are exact matches against already-located,
  already-cited, production-eligible evidence.** A scholar reviewing
  Hanafi and Shafi'i's duration thresholds, and Hanbali/Maliki's minimum
  purity, is confirming existing located citations, not starting from
  nothing.
- **2 cells (Hanbali min-purity, Maliki min-Haid) show the engine's
  hardcoded value does not match the KB's own already-trusted
  evidence for the same proposition.** These should be the first two
  items a scholar is asked to resolve — not generic "is this engine
  correct" review, but a specific, named discrepancy with two concrete
  candidate answers to choose between.
- **1 cell (Maliki max-Haid) has evidence that is itself not yet
  production-eligible** (`SCHOLAR_CLARIFICATION_REQUIRED`) and shows the
  engine's simple constant is a known simplification of a more complex
  real rule.
- This crosswalk does not and cannot substitute for scholar review — it
  only means the review can be scoped and sequenced (discrepancies
  first, confirmations second) instead of open-ended.
