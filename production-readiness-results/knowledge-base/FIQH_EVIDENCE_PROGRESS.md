# Fiqh Evidence Extraction Progress

## First-pass evidence status

All **180 Madhhab-specific V1 Fiqh atoms** now have at least a concrete source locator. There are no remaining rows in `PRIMARY_LOCATOR_NEEDED`.

| Madhhab | Total | Locator verified | Scholar clarification required | Partial evidence | Primary locator needed | Scholar approved |
|---|---:|---:|---:|---:|---:|---:|
| hanafi | 45 | 33 | 6 | 6 | 0 | 0 |
| maliki | 45 | 33 | 8 | 4 | 0 | 0 |
| shafii | 45 | 34 | 9 | 2 | 0 | 0 |
| hanbali | 45 | 35 | 6 | 4 | 0 | 0 |
| **Total** | **180** | **135** | **29** | **16** | **0** | **0** |

## Interpretation

- **135/180** rows have a direct locator supporting the current concise proposition.
- **16/180** have a locator but still need a narrower or better-corroborated formulation.
- **29/180** deliberately expose Madhhab-internal nuance or a product decision that a qualified scholar must settle.
- **0/180** are scholar-approved.
- Evidence extraction is not publication approval.

## Evidence packs

- `HANAFI_EVIDENCE_PACK.csv`
- `MALIKI_EVIDENCE_PACK.csv`
- `SHAFII_EVIDENCE_PACK.csv`
- `HANBALI_EVIDENCE_PACK.csv`

## Next gate

1. Quality-sweep all locators and flag secondary-host or edition-quality concerns.
2. Produce four scholar-review packets from the evidence packs.
3. Every packet must preserve the source proposition and expose disagreements rather than silently choose a view.
4. Scholar decisions are recorded as APPROVED / APPROVED_WITH_EDITS / CONFLICT_REQUIRES_REVIEW / REJECTED.
5. Only approved propositions can be transformed into production knowledge items.

## Hard rule

A verified locator does not make a Fiqh ruling authoritative for Niswah. Scholar approval remains mandatory.
