# Fiqh Evidence Extraction Progress

## Current evidence status

All **180 Madhhab-specific V1 Fiqh atoms** have a concrete source locator. There are no remaining `PRIMARY_LOCATOR_NEEDED` rows.

| Madhhab | Total | Locator verified | Scholar clarification required | Partial evidence | Primary locator needed | Scholar approved |
|---|---:|---:|---:|---:|---:|---:|
| hanafi | 45 | 33 | 6 | 6 | 0 | 0 |
| maliki | 45 | 33 | 8 | 4 | 0 | 0 |
| shafii | 45 | 34 | 9 | 2 | 0 | 0 |
| hanbali | 45 | 37 | 6 | 2 | 0 | 0 |
| **Total** | **180** | **137** | **29** | **14** | **0** | **0** |

## Source-quality audit

- `178` rows: primary evidence suitable for scholar review.
- `2` rows: primary evidence is suitable, but a secondary link is corroborative only.
- `0` rows: still rely on a secondary/quoting primary host.
- `0` rows: missing primary URL.

## Interpretation

- **137/180** directly support the present concise proposition.
- **14/180** have located evidence but still require narrower/corroborated wording.
- **29/180** intentionally expose Madhhab-internal nuance or a relied-upon-view decision.
- **0/180** are scholar-approved.
- Evidence extraction is not publication approval.

## Scholar packets

- `HANAFI_SCHOLAR_REVIEW_PACKET.csv`
- `MALIKI_SCHOLAR_REVIEW_PACKET.csv`
- `SHAFII_SCHOLAR_REVIEW_PACKET.csv`
- `HANBALI_SCHOLAR_REVIEW_PACKET.csv`

## Next gate

1. Hand the four packets to qualified Madhhab-aware scholar reviewers.
2. Record `APPROVED`, `APPROVED_WITH_EDITS`, `CONFLICT_REQUIRES_REVIEW`, or `REJECTED`.
3. Preserve conditions/exceptions and reviewer identity/qualification/date.
4. Resolve all PARTIAL_EVIDENCE rows during review or subsequent research.
5. Convert only approved propositions into versioned production knowledge items.

No row is an authoritative Niswah ruling merely because the source locator is verified.
