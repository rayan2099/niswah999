# Evidence Snapshot Freeze Manifest

**Machine-readable manifest**: `EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json` (this file
explains it; the JSON is the authoritative artifact).

## What this is

A pinned, immutable snapshot identity for the exact evidence state this KB
workstream had reached as of the commit and timestamp recorded in the JSON.
Any future engineering work (retrieval, ingestion, embeddings, backend
citations) must be able to state which snapshot it was built against, and
that statement must be checkable — not asserted from memory.

- **Frozen commit**: `eda4b96c7b2a77924a3dd86397cbcbba671440b3`
- **Freeze timestamp (UTC)**: `2026-09-29T10:40:49Z`
- **Row counts**: 254 total = 180 Fiqh + 74 Health/Safety; 211
  `PRODUCTION_ELIGIBLE` + 43 `FAIL_CLOSED` = 254. Reconciliation check: **true**.
- **`PRODUCTION_DISPOSITION_MASTER.csv` SHA-256**:
  `e6dd52c88f0986058156533754257652b43bca4a771ac42f82e5706049faafea`

## How to use this manifest

1. Before building anything against the KB, recompute the SHA-256 of
   `PRODUCTION_DISPOSITION_MASTER.csv` (or any other listed source artifact) and
   compare it to the value recorded in the JSON. A mismatch means the file has
   changed since this freeze — do not assume the disposition data is the same;
   re-freeze first.
2. `included_atom_ids_all_254`, `production_eligible_atom_ids_211`, and
   `fail_closed_atom_ids_43` are exact, closed lists. An atom ID appearing in
   neither eligible nor fail-closed list at build time that isn't in this
   manifest at all is new since the freeze and has no frozen disposition — it
   must not be treated as retrievable until a new freeze covers it.
3. `source_artifact_versions` gives both a git blob SHA-1 (native to this repo)
   and an independent SHA-256 (portable outside git) for every file this
   disposition was computed from — the 4 Madhhab evidence packs, the Health
   canonical draft + corrections overlay, and both internet-audit CSVs.

## Why a new manifest, never an edit

This manifest is never edited in place. If any source artifact changes (a new
Fiqh row is added, a Health correction is revised, a scholar finally approves
a row), a **new** freeze manifest is created with a new timestamp and new
checksums. The old manifest stays exactly as it is — it accurately describes
what was true at its own freeze point, which is the whole reason it exists
(REVIEW_AND_PUBLISHING_WORKFLOW.md's non-destructive-versioning principle,
applied here to the evidence snapshot as a whole rather than to one knowledge
item).

## What this manifest does NOT do

- It does not approve, publish, or change the disposition of any atom — it
  only records the disposition `PRODUCTION_DISPOSITION_MASTER.csv` already
  assigned.
- It does not imply scholar or clinician review. Every one of the 254 rows'
  `human_review_status` is `NOT_REVIEWED` at this freeze point, without
  exception — see the JSON's `trust_boundary_statement`.
- It does not authorize any engineering change, migration, or deployment.
