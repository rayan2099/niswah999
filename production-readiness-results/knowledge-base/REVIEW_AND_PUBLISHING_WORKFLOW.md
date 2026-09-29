# Review and Publishing Workflow

## Purpose
This workflow governs evidence quality and product use. It does not represent a medical diagnosis, a personal fatwa, or human professional certification unless an attributable qualified reviewer has actually provided one.

## Evidence lifecycle
DRAFT
→ PRIMARY_SOURCE_VERIFIED
→ DOCUMENTARY_VERIFIED
→ INSTITUTIONALLY_CORROBORATED (when an independent authoritative source is available and applicable)
→ ELIGIBLE_FOR_GUIDED_USE
→ PUBLISHED
→ RETIRED

An item may instead move to:
- HUMAN_JUDGMENT_REQUIRED
- CONFLICT_REQUIRES_REVIEW
- REJECTED

## Evidence classes
### PRIMARY_SOURCE_VERIFIED
The proposition is traceable to the cited primary source and exact locator.

### DOCUMENTARY_VERIFIED
A second-pass audit confirms that the canonical wording does not materially exceed the cited evidence and that the source is applicable to the stated population/context.

### INSTITUTIONALLY_CORROBORATED
An independent authoritative or institutional source materially corroborates the proposition without a relevant conflict. Corroboration must be scope-compatible; e.g. a pregnancy/postpartum warning-sign source cannot be used as general-menstruation corroboration unless the item is explicitly limited to pregnancy/postpartum.

### HUMAN_JUDGMENT_REQUIRED
The item depends on individualized diagnosis, legal/fiqh application to a person's circumstances, unresolved intra-school interpretation, source conflict, or another question that documentary review alone cannot settle safely.

## Roles
- FIQH documentary audit: source/locator verification plus Madhhab-specific corroboration where available.
- HEALTH documentary audit: authoritative clinical/public-health sources and population/context checks.
- SAFETY documentary audit: authoritative warning-sign/emergency sources with fail-closed wording.
- PRODUCT: Niswah product/engineering owner.
- HUMAN REVIEWER (optional but stronger): qualified scholar or clinician when available or when an item is classified HUMAN_JUDGMENT_REQUIRED.

## Guided-use publication rule
An item may be eligible for guided, educational use without claiming human professional approval only when all of the following hold:
1. the primary source and locator are verified;
2. the final wording is documentary-verified and does not exceed the evidence;
3. any cited secondary source is scope-compatible;
4. no unresolved material conflict changes the user-facing proposition;
5. the item is not an individualized diagnosis, treatment directive, or personalized fatwa;
6. the response contract requires source citation and the applicable medical/fiqh disclaimer;
7. safety items use fail-closed escalation behavior.

Human review remains required for items classified HUMAN_JUDGMENT_REQUIRED or CONFLICT_REQUIRES_REVIEW.

## Product trust boundary
### Health
Niswah provides educational/source-based information, not diagnosis or individualized medical treatment. When symptoms may require clinical evaluation, the product must say so. Emergency/urgent warning signs must trigger escalation language rather than diagnostic conclusions.

### Fiqh
Niswah may present a source-based, Madhhab-specific proposition as educational guidance, but must not represent the output as a personal fatwa. If the user's facts materially affect application, the sources conflict, the Madhhab is unknown, or the evidence is ambiguous, the system must surface the uncertainty and recommend asking a qualified scholar/official fatwa service.

## Versioning and audit rules
- Do not overwrite published history.
- An edit creates a new version.
- Retain source, locator, evidence class, audit date, and reviewer identity when a human reviewer exists.
- Never populate a scholar/clinician approval field unless that human review actually occurred.
- A rejected or blocked item remains auditable.
- Production retrieval excludes DRAFT, HUMAN_JUDGMENT_REQUIRED, CONFLICT_REQUIRES_REVIEW, REJECTED, and RETIRED versions.
- Production retrieval may include ELIGIBLE_FOR_GUIDED_USE only under the trust-boundary and citation contracts above.
