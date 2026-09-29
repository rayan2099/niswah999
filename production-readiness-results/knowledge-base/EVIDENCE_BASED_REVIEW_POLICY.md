# Evidence-Based Review Policy

## Purpose
This policy governs Niswah V1 knowledge publication when the product is providing educational, source-linked guidance rather than a personal medical diagnosis or personal fatwa.

## Evidence states
- `PRIMARY_SOURCE_VERIFIED`: the canonical proposition is directly supported by an authoritative primary source and does not exceed that source.
- `INSTITUTIONALLY_CORROBORATED`: the proposition is independently supported by at least two authoritative or institutional sources within the same scope.
- `CONFLICT_OR_JUDGMENT_REQUIRED`: authoritative sources conflict materially, interpretation is required, the proposition depends on unresolved Madhhab reasoning, or individual clinical/fiqh judgment is necessary.
- `SOURCE_SCOPE_CORRECTION_REQUIRED`: a cited source is real but does not support the proposition in the population/context where Niswah intends to use it.
- `INSUFFICIENT_EVIDENCE`: the proposition lacks adequate source support.

## Production eligibility
A knowledge item may be considered for educational production use only when all of the following are true:
1. it is `PRIMARY_SOURCE_VERIFIED` or `INSTITUTIONALLY_CORROBORATED`;
2. source scope matches the user's context;
3. Arabic and English wording do not exceed the supported proposition;
4. retrieval returns the source metadata and exact locator;
5. the AI contract presents the result as educational/source-based information, not a personal diagnosis or personal fatwa;
6. safety/escalation rules override ordinary generation where applicable.

`CONFLICT_OR_JUDGMENT_REQUIRED`, `SOURCE_SCOPE_CORRECTION_REQUIRED`, and `INSUFFICIENT_EVIDENCE` are fail-closed and excluded from authoritative production answers.

## Medical boundary
Niswah may summarize and cite general guideline information. It must not diagnose the user's condition, prescribe individualized treatment, or imply that a guideline establishes the user's diagnosis. Red-flag symptoms must route to appropriate clinical or emergency escalation.

## Fiqh boundary
Niswah may present a source-attributed Madhhab position when the proposition and locator are sufficiently verified. It must identify the selected Madhhab and must not silently infer one. Questions that depend on unresolved application, conflicting source interpretation, or personal circumstances beyond the encoded rule are `CONFLICT_OR_JUDGMENT_REQUIRED` and must direct the user to qualified religious guidance.

## User-facing limitation
The product must state in-context that medical information is educational and does not replace professional medical care, and that fiqh information is source-based educational guidance and does not replace a personal fatwa where individual judgment is needed.

## Auditability
Every production knowledge version retains atom ID, source IDs, locators, evidence state, audit date, wording version, and any superseded state. Evidence verification is not represented as external professional endorsement unless such endorsement actually exists.
