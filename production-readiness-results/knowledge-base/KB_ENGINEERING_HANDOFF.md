# KB Engineering Handoff

## Input set

Production-authoritative educational retrieval must be built only from the evidence-eligible set:

- Health/Safety: 74 candidate atoms
  - apply `HEALTH_SAFETY_EVIDENCE_CORRECTIONS.csv` as the canonical override where an atom appears there
  - add `SAUDI_MOH_PRECON` from `SOURCE_REGISTRY_ADDITIONS.csv` to the source registry before materialization
- Fiqh: 137 candidate atoms whose evidence status is `LOCATOR_VERIFIED`
- Fiqh: exclude all 43 rows listed in `FIQH_INTERNET_EVIDENCE_AUDIT.csv`

## Hard exclusions

Never ingest as authoritative retrieval:
- `CONFLICT_OR_JUDGMENT_REQUIRED`
- `INSUFFICIENT_EVIDENCE`
- `SOURCE_SCOPE_CORRECTION_REQUIRED` unless the correction overlay has been applied
- any row without source metadata and an exact locator

## Materialization order

1. Apply source-registry additions.
2. Apply Health/Safety correction overlay.
3. Create immutable versioned candidate records.
4. Mark evidence state on each version.
5. Preserve atom ID, source ID, locator, language, domain, Madhhab where applicable, and provenance.
6. Apply the KB database schema.
7. Ingest candidates only after schema constraints are active.
8. Build structured retrieval filters before embeddings/semantic retrieval.
9. Generate citations from backend metadata.
10. Connect AI modes only after retrieval tests pass.

## Required retrieval filters

Fiqh Advisor:
- confirmed Madhhab required for Madhhab-specific authoritative retrieval
- UNKNOWN Madhhab must not default
- fail-closed rows excluded
- factual bleeding observation remains separate from ruling

Dr Niswah / Health:
- pregnancy/postpartum scope checked before using maternal-warning content
- ordinary menstrual guidance must not inherit pregnancy-only source scope
- urgent red flags override educational generation
- no diagnosis or individualized treatment

General Assistant:
- only approved product and permitted general-health knowledge
- no implicit Fiqh authority

Dream Interpreter:
- separate non-authoritative contract

## Acceptance gate

Before any merge to production AI, test:
- all four Madhhabs
- UNKNOWN Madhhab
- Haid / Tahara / Istihada / Nifas
- TTC
- pregnancy
- postpartum
- Health/Safety red flags
- Arabic and English
- exact citations
- insufficient-evidence behavior
- cross-account isolation
- history/reload
- model outage / retrieval failure

No model-generated source title, page number, URL, or ruling may be accepted as citation metadata.
