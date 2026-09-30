# Medical Review Handoff

## Purpose

Review the 74 source-mapped Niswah V1 Health and Safety statements before they become production knowledge.

Review file:

- `MEDICAL_REVIEW_PACKET.csv`

Breakdown:
- 59 Health atoms
- 15 Safety/Escalation atoms

## Decision values

Use one:
- `APPROVED`
- `APPROVED_WITH_EDITS`
- `CONFLICT_REQUIRES_REVIEW`
- `REJECTED`
- `NOT_APPLICABLE`

## Required fields

For each reviewed row:
- medical_decision
- approved_canonical_en
- approved_canonical_ar
- approved_escalation_class
- conditions_or_exceptions
- reviewer_name
- reviewer_qualification
- review_date
- review_notes when necessary

## Review questions

The reviewer should check:

1. Is the medical proposition accurate and appropriately scoped?
2. Is the escalation level safe?
3. Are thresholds stated with the right degree of precision?
4. Does the wording avoid diagnosis or false reassurance?
5. Does the Arabic preserve the medical meaning of the English?
6. Are pregnancy/postpartum safety statements appropriately conservative?
7. Are TTC estimates clearly separated from observed ovulation/pregnancy facts?
8. Are any statements unsuitable for a Saudi consumer-health product without local clinical adaptation?

## Safety rows

Safety/Escalation rows deserve separate attention. If a statement could cause a user with an urgent symptom to wait unnecessarily, it should not be approved as written.

## Source and rights constraints

The current production-oriented draft prefers OWH/HHS, NICHD/NIH and CDC material because their reuse posture is more compatible with Niswah's commercial AI use, subject to page-specific third-party exceptions.

Restricted professional guidance may be used for clinical corroboration/review, but must not be bulk-ingested into the production AI unless the appropriate rights are obtained.

## Publication rule

All rows remain `NOT_APPROVED_NOT_PUBLISHED` until a qualified reviewer explicitly approves or edits them. Review approval must be versioned and attributable.
