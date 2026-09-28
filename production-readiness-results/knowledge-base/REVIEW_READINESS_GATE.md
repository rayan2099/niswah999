# Niswah V1 Knowledge Review Readiness Gate

## Current state

The V1 evidence program is ready for domain review.

### Fiqh
- 180 / 180 Madhhab-specific atoms have concrete source locators.
- 137 are marked LOCATOR_VERIFIED.
- 29 are marked SCHOLAR_CLARIFICATION_REQUIRED.
- 14 are marked PARTIAL_EVIDENCE.
- 0 remain PRIMARY_LOCATOR_NEEDED.
- 0 are scholar-approved.

### Health / Safety
- 74 / 74 Health and Safety atoms have source-mapped Arabic/English draft wording.
- 0 are medically approved.

## Human-review blockers

Production publication is blocked until:
1. each Fiqh row receives a qualified Madhhab-aware scholar decision;
2. each Health/Safety row receives a qualified medical review decision;
3. approved wording, conditions/exceptions, reviewer identity/qualification, and review date are stored.

## Review order

### Fiqh
Review rows in this order:
1. SCHOLAR_CLARIFICATION_REQUIRED
2. PARTIAL_EVIDENCE
3. LOCATOR_VERIFIED

### Medical
Review in this order:
1. SAFETY_ESCALATION
2. pregnancy and postpartum
3. abnormal/heavy bleeding
4. TTC
5. general menstrual education
6. wellbeing

## Acceptance rule

A review is complete only when every row has one explicit decision:
- APPROVED
- APPROVED_WITH_EDITS
- CONFLICT_REQUIRES_REVIEW
- REJECTED
- NOT_APPLICABLE

Blank/PENDING does not count as review.

## Production rule

Only rows with APPROVED or APPROVED_WITH_EDITS may later be converted into production knowledge items.

Evidence extraction is not approval.
A source locator is not approval.
A coding-agent assertion is not approval.
An LLM-generated summary is not approval.
