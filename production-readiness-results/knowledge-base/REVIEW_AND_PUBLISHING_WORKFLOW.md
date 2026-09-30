# Review and Publishing Workflow

> **Governance status (2026-09-29): this workflow's core policy — that a row
> may become a `PRODUCTION_CANDIDATE` through evidence classification alone,
> with human scholar/clinician review marked optional — is an agent
> recommendation, not a founder-approved policy. It replaced an earlier
> design (`DRAFT → SOURCE_VERIFIED → DOMAIN_REVIEWED → APPROVED → PUBLISHED`,
> human review required to reach `APPROVED`) without recorded founder
> sign-off. See `FOUNDER_DECISIONS.md` FD-5. The content below is preserved
> as-is (it is already honest about not fabricating human approval) but its
> status as *the* governing policy is `PENDING_FOUNDER_REVIEW`.**

## Lifecycle
DRAFT
→ SOURCE_VERIFIED
→ EVIDENCE_CLASSIFIED
→ PRODUCTION_CANDIDATE
→ PUBLISHED
→ RETIRED

## Evidence states
- `PRIMARY_SOURCE_VERIFIED`
- `INSTITUTIONALLY_CORROBORATED`
- `CONFLICT_OR_JUDGMENT_REQUIRED`
- `SOURCE_SCOPE_CORRECTION_REQUIRED`
- `INSUFFICIENT_EVIDENCE`

## Roles
- FIQH evidence review: source/locator verification plus Madhhab-specific scope check
- HEALTH evidence review: guideline/source verification plus population/context scope check
- SAFETY evidence review: red-flag source verification with fail-closed escalation
- PRODUCT: Niswah product/engineering owner
- OPTIONAL HUMAN REVIEW: qualified scholar/clinician when external endorsement or unresolved judgment is required

## Rules
- Do not overwrite published history.
- An edit creates a new version.
- Retain source, locator, evidence state, audit date, wording version, and any human reviewer metadata when present.
- A rejected or fail-closed item remains auditable.
- Production retrieval excludes DRAFT, `CONFLICT_OR_JUDGMENT_REQUIRED`, `SOURCE_SCOPE_CORRECTION_REQUIRED`, `INSUFFICIENT_EVIDENCE`, rejected, and retired versions.
- Evidence verification must never be represented as external professional endorsement unless a qualified human reviewer actually supplied that endorsement.

## Production-candidate rule
A row may become a production candidate only if:
1. evidence state is `PRIMARY_SOURCE_VERIFIED` or `INSTITUTIONALLY_CORROBORATED`;
2. the cited source applies to the same population/context as the intended answer;
3. Arabic and English wording do not exceed the source-supported proposition;
4. exact source/locator metadata is retained;
5. the relevant AI mode displays the result as educational/source-based guidance, not a personal diagnosis or personal fatwa;
6. safety and escalation contracts are satisfied.

## Fiqh
A Madhhab proposition may be presented as source-attributed educational guidance when the source and locator support it and application does not require unresolved individual judgment. The selected Madhhab must be explicit. `UNKNOWN` must never silently default. Any unresolved source interpretation, conflicting Madhhab application, or person-specific judgment is `CONFLICT_OR_JUDGMENT_REQUIRED` and fails closed to qualified religious guidance.

## Health
General guideline information may be presented when its source and context are verified. Niswah must not diagnose an individual user or prescribe individualized treatment. Red-flag symptoms override ordinary educational generation and route to appropriate clinical/emergency guidance.

## Human review
Human review remains valuable and may upgrade confidence or provide true external endorsement, but it is not represented as having occurred unless attributable reviewer identity/qualification and decision are actually recorded.
