# Fiqh Evidence Extraction Progress

## First-pass status

The first-pass evidence extraction now covers all **180 Madhhab-specific V1 Fiqh atoms**:

| Madhhab | Total | Locator verified | Scholar clarification required | Partial evidence | Primary locator needed | Scholar approved |
|---|---:|---:|---:|---:|---:|---:|
| hanafi | 45 | 32 | 6 | 5 | 2 | 0 |
| maliki | 45 | 33 | 8 | 3 | 1 | 0 |
| shafii | 45 | 32 | 9 | 2 | 2 | 0 |
| hanbali | 45 | 35 | 6 | 4 | 0 | 0 |
| **Total** | **180** | **132** | **29** | **14** | **5** | **0** |

## Meaning of this milestone

- **132/180** rows have a source locator that directly supports the concise source-derived proposition.
- **48/180** rows still need additional research and/or a scholar decision before they can be formulated as a production rule.
- **180/180** remain subject to qualified Madhhab-aware scholar review.
- **0/180** are currently approved for production.
- Evidence extraction is not publication approval.

## Evidence packs

- `HANAFI_EVIDENCE_PACK.csv`
- `MALIKI_EVIDENCE_PACK.csv`
- `SHAFII_EVIDENCE_PACK.csv`
- `HANBALI_EVIDENCE_PACK.csv`

## Next Fiqh gate

1. Resolve the `PRIMARY_LOCATOR_NEEDED` rows.
2. Narrow the `PARTIAL_EVIDENCE` rows.
3. Convert each `SCHOLAR_CLARIFICATION_REQUIRED` row into a concise decision question for the relevant scholar.
4. Run a locator/link/edition quality sweep.
5. Produce scholar-review packets containing the atom, concise proposition, direct source locator(s), and conflict note.
6. Record reviewer decisions without overwriting historical evidence.

## Hard rule

No evidence-pack row becomes an authoritative Niswah ruling merely because its locator is verified.
