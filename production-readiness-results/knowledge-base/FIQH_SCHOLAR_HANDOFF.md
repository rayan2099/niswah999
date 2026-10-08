# Fiqh Scholar Review Handoff

## Purpose

This package asks qualified Madhhab-aware scholars to review Niswah's proposed Fiqh knowledge **before any ruling becomes available to the production AI**.

There are four separate 45-row review packets:

- `HANAFI_SCHOLAR_REVIEW_PACKET.csv`
- `MALIKI_SCHOLAR_REVIEW_PACKET.csv`
- `SHAFII_SCHOLAR_REVIEW_PACKET.csv`
- `HANBALI_SCHOLAR_REVIEW_PACKET.csv`

## What the reviewer is approving

The reviewer is **not approving the app generally** and is not being asked to approve an AI model.

For each row, the reviewer decides whether the proposed source-supported proposition accurately represents the relied-upon position that Niswah should use for that Madhhab, including the relevant conditions and exceptions.

## Decision values

Use exactly one:

- `APPROVED` — proposition is accurate as written.
- `APPROVED_WITH_EDITS` — accurate after the reviewer supplies corrected canonical wording/conditions.
- `CONFLICT_REQUIRES_REVIEW` — the issue cannot yet be reduced to one production rule without further scholarly decision.
- `REJECTED` — the proposition/source mapping is materially incorrect.
- `NOT_APPLICABLE` — the atom should not exist for this Madhhab/product scope.

Do not leave `PENDING` when a row has been reviewed.

## Required reviewer fields

For every reviewed row, record:

- `scholar_decision`
- `approved_canonical_ruling_ar` when approved or edited
- `approved_canonical_ruling_en` when approved or edited
- `conditions_or_exceptions`
- `reviewer_name`
- `reviewer_qualification`
- `review_date`
- `review_notes` where relevant

## Evidence-status meaning

- `LOCATOR_VERIFIED` — a direct locator supports the research proposition. It is **not** an approval.
- `PARTIAL_EVIDENCE` — the located source supports the core proposition but the production formulation or an edge condition remains incomplete.
- `SCHOLAR_CLARIFICATION_REQUIRED` — the sources expose intra-Madhhab nuance, multiple views, or a decision-tree issue that must be resolved explicitly.

There are currently no `PRIMARY_LOCATOR_NEEDED` rows.

## Review priorities

Review `SCHOLAR_CLARIFICATION_REQUIRED` first because these are most likely to create unsafe or incorrect algorithmic simplification.

Pay particular attention to:

- interposed purity and resumed bleeding
- changes in menstrual habit
- tamyiz versus habit
- pregnancy bleeding
- pregnancy loss and Nifas
- multiple births
- prayer-time transitions
- fasting transitions around Fajr
- uncertain/mutahayyira states

## Product constraints the reviewer should know

1. Niswah records factual bleeding observations separately from Fiqh rulings.
2. UNKNOWN Madhhab must never silently default.
3. If evidence is insufficient, the product may preserve an UNKNOWN/uncertain classification rather than force a ruling.
4. A source statement that needs multiple conditions should be returned as conditions/decision logic, not compressed into a misleading sentence.
5. Modern medical terms must not be substituted for classical Fiqh criteria without explicit review.
6. The Dream Interpreter is outside this authoritative Fiqh KB.

## Publication rule

A row remains `NOT_APPROVED_NOT_PUBLISHED` unless its scholar decision is `APPROVED` or `APPROVED_WITH_EDITS` and the final canonical wording and conditions are recorded.

Scholar review must never be inferred from a checked source locator.
