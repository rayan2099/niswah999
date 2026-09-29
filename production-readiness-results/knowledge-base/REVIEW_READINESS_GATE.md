# Niswah V1 Knowledge Review Readiness Gate

## Current state
The V1 evidence program has completed source extraction and is now in documentary/institutional evidence audit.

### Fiqh
- 180 / 180 Madhhab-specific atoms have concrete source locators.
- 137 are currently LOCATOR_VERIFIED.
- 29 are currently SCHOLAR_CLARIFICATION_REQUIRED.
- 14 are currently PARTIAL_EVIDENCE.
- 0 remain PRIMARY_LOCATOR_NEEDED.
- 0 have attributable scholar approval.

### Health / Safety
- 74 / 74 Health and Safety atoms have source-mapped Arabic/English draft wording.
- 0 have attributable medical approval.

Human approval is not to be inferred or fabricated. The next gate is an evidence audit that determines which rows are safe for source-based educational guided use and which rows still require human judgment.

## Evidence-audit decisions
Each row must receive one explicit documentary decision:
- DOCUMENTARY_VERIFIED
- INSTITUTIONALLY_CORROBORATED
- HUMAN_JUDGMENT_REQUIRED
- CONFLICT_REQUIRES_REVIEW
- REJECTED
- NOT_APPLICABLE

Blank/PENDING does not count as audited.

## Guided-use eligibility
A row may later become ELIGIBLE_FOR_GUIDED_USE only when:
1. its primary source/locator is verified;
2. the user-facing wording does not materially exceed the evidence;
3. secondary corroboration, when cited, is context/population compatible;
4. no unresolved conflict changes the proposition;
5. it is not individualized diagnosis/treatment or a personalized fatwa;
6. the AI response contract requires citations and the relevant disclaimer;
7. safety/escalation behavior is fail-closed.

## Mandatory human-judgment blockers
A row remains blocked from guided production use when documentary review finds:
- unresolved intra-Madhhab interpretation that changes the result;
- material contradiction between relied-upon sources;
- dependence on facts requiring a scholar to apply the ruling to a specific person;
- medical diagnosis/treatment selection rather than general education or escalation;
- ambiguous or population-mismatched evidence;
- insufficient evidence to state the proposition conservatively.

## Review order
### Fiqh
1. SCHOLAR_CLARIFICATION_REQUIRED
2. PARTIAL_EVIDENCE
3. LOCATOR_VERIFIED

### Health / Safety
1. SAFETY_ESCALATION
2. pregnancy and postpartum
3. abnormal/heavy bleeding
4. TTC
5. general menstrual education
6. wellbeing

## Product rule
Niswah must not describe documentary verification as scholar approval, medical approval, a personal fatwa, diagnosis, or treatment. Guided outputs must remain source-based and educational, show citations, disclose limits, and escalate when a qualified professional is needed.

## Current execution
The Internet Evidence Audit is in progress. Results are recorded atom-by-atom in `INTERNET_EVIDENCE_AUDIT.csv`; production KB ingestion remains blocked until that audit establishes eligible rows and the engineering trust-boundary/citation controls exist.
