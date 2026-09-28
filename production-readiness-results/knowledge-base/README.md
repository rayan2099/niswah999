# Niswah V1 Knowledge Base

This branch is the dedicated Knowledge Base workstream for Niswah V1. It is intentionally separate from PR #4 and from production AI implementation.

## Canonical review artifacts in this branch

- `SOURCE_REGISTRY.csv` — candidate sources, authority role, retrieval scope, rights/ingestion posture, and reviewer type.
- `ATOMIC_KNOWLEDGE_MATRIX.csv` — V1 atomic knowledge denominator: 261 requirements.
- `HEALTH_SAFETY_CANONICAL_DRAFT.csv` — 74 source-mapped English/Arabic Health and Safety draft statements.
- `FIQH_SCHOLAR_REVIEW_QUEUE.csv` — 180 Madhhab-specific review rows: 45 issues × Hanafi, Maliki, Shafi'i, Hanbali.

## Current status

- Health/Safety: source-mapped drafts only. Every row requires domain review before approval/publication.
- Fiqh: review queue only. No Madhhab ruling is approved merely because a source is listed. Exact passages/locators and qualified scholar review are still required.
- Embeddings/RAG: not authorized yet.
- Production KB migration: not authorized yet.
- Live AI publication: not authorized yet.

## Hard knowledge controls

1. Database/canonical application state is the authority for user facts.
2. Approved Knowledge Base items are the authority for health/Fiqh knowledge.
3. The LLM explains; it does not invent factual user state, a Madhhab, a ruling, a diagnosis, or a citation.
4. Fiqh retrieval must be Madhhab-filtered before semantic retrieval.
5. UNKNOWN/UNSET Madhhab must never silently default.
6. Health, Fiqh, Product, and Safety authority remain distinguishable.
7. Safety escalation takes precedence over ordinary health generation.
8. Only reviewed/approved items may later become production-retrievable.
9. Source rights are separate from source credibility. Restricted material must not be bulk-ingested without permission.
10. Historical versions/reviewer/source provenance must be retained when the production KB is implemented.

## Denominator

- 180 Fiqh Madhhab-specific atoms
- 59 Health atoms
- 15 Safety/Escalation atoms
- 7 Niswah product/trust-boundary atoms
- Total: 261 atomic V1 requirements

## Next gates

1. Complete exact Fiqh passage and locator extraction.
2. Medical review of Health/Safety draft statements.
3. Qualified Madhhab-aware scholar review of Fiqh propositions.
4. Only then finalize/apply the KB database schema.
5. Load approved knowledge, add structured retrieval and embeddings.
6. Connect real AI modes and run live-model acceptance.

The Excel workbooks used during research are review conveniences; CSV/Markdown artifacts in the repository are the diffable source-of-truth working files.


## Fiqh evidence packs

- `HANAFI_EVIDENCE_PACK.csv` — first-pass source/locator extraction for all 45 Hanafi atoms.
- `MALIKI_EVIDENCE_PACK.csv` — first-pass source/locator extraction for all 45 Maliki atoms.

Evidence-pack statuses are research states, not religious approval. Rows marked LOCATOR_VERIFIED still remain PENDING_SCHOLAR_REVIEW.
