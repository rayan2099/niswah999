# Engineering Remediation Report

**Date**: 2026-09-29. **Scope**: remediation of the findings in
`CUTOVER_AUDIT_REPORT.md`, under founder approval of FD-5 (with binding
conditions) and FD-6 in `FOUNDER_DECISIONS.md`. All work committed
incrementally to `feat/niswah-v1-knowledge-base` (PR #6, still draft).
**No migration applied to any database. No deployment. No merge.**

## Founder decisions this pass implements

- **FD-5** — `FOUNDER_APPROVED_WITH_CONDITIONS`. Evidence-backed content may
  be production-eligible without prior human professional approval, but
  every one of the founder's eight binding conditions is now independently
  enforced or verified (see the Phase-by-phase sections below and
  `FOUNDER_DECISIONS.md`).
- **FD-6** — `FOUNDER_APPROVED`. KB-only authoritative retrieval stays the
  production model for Fiqh Advisor; live Google Search grounding is not
  restored to production answers.

## Cutover findings addressed, one by one

| # | Finding (from `CUTOVER_AUDIT_REPORT.md`) | Remediation | Status |
|---|---|---|---|
| 1 | Fail-closed rows structurally excluded (design PASS, unproven live) | Candidate generation now derives eligibility *only* from `PRODUCTION_DISPOSITION_MASTER.csv`, with reconciliation assertions against it | **Verified** (Python tests, real run) |
| 2 | Madhhab boundary enforcement (PASS) | Unchanged; added a static SQL check + Deno short-circuit test as regression coverage | **Verified** |
| 3 | Health uses only eligible rows (PASS, unproven live) | Same disposition-master-driven generation | **Verified** (candidate generation) |
| 4 | Qualification metadata has no schema column and is dropped by `formatKnowledgeBlock` (**HIGH**) | New `qualification_note` column; carried through generation → seed SQL → RPC → `formatKnowledgeBlock`'s `QUALIFICATION=` line → both system prompts instructed to state it, never drop it | **Fixed & verified** |
| 5 | Citations originate only from the KB (PASS) | Unchanged; added a structural test asserting `citationPayload`'s signature has no text/model-output parameter | **Verified** |
| 6 | Dr Niswah has no hard empty-KB gate (**HIGH**) | Added the same pre-generation gate `fiqh-advisor-chat` already had; urgent-banner path is untouched (fires independently of KB grounding) | **Fixed & type-checked** |
| 7 | API contract carries no "not professionally approved" marker (**MEDIUM/HIGH**) | Both system prompts now explicitly instruct the model to frame KB-grounded answers as evidence-verified, never as scholar/clinician-reviewed; `human_review_status=NOT_REVIEWED` is enforced on every row at the data layer | **Partially addressed** — see Remaining Risks |
| 8 | 34 judgment/conflict Fiqh rows technically blocked (PASS) | Unchanged mechanism + regression test naming the count | **Verified** |
| 9 | 3 pregnancy-loss/nifas rows categorically blocked (PASS) | Unchanged mechanism + regression test naming all 3 IDs explicitly | **Verified** |
| 10 | No snapshot/version tie (**BLOCKER**) | New `kb_snapshot_registry` table + `get_active_kb_snapshot()` RPC + `assertSnapshotHealth()` in `kb_retrieval.ts`, called by both edge functions whenever retrieval returns nothing | **Fixed & verified** (unit tests) |
| 11 | `build_kb_production_candidates.py` crashes (**BLOCKER, confirmed live**) | Full rewrite: eligibility derives from the disposition master, hardcoded per-domain assumptions removed entirely, checksum/integrity checks added | **Fixed & verified** (11 tests, real run against live data) |
| 12 | `verify-kb-review-packets` CI check failing on PR #6 (**confirmed live**) | Same rewrite + CI workflow's inline assertion now checks against the disposition master instead of hardcoded 29/14 | **Fixed & confirmed live** — see CI Status |

## Phase-by-phase summary

**Phase 1 — `build_kb_production_candidates.py` rewritten.** A row enters
production because its `atom_id` has `production_disposition ==
PRODUCTION_ELIGIBLE` in `PRODUCTION_DISPOSITION_MASTER.csv` — nothing else.
Hard failure modes, all before any output is written: wrong total row count
(≠254), duplicate atom_id, unknown disposition value, an atom missing from
the master, an orphaned master row, or any frozen source artifact's SHA-256
no longer matching `EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json`. Real run against
the actual repo: `74 Health/Safety + 137 Fiqh = 211 production candidates (4
carrying a qualification_note); 43 quarantined`.

**Phase 2 — qualification metadata end-to-end.** New `qualification_note`
column (migration `20260929120000_...sql`) threaded through: disposition
master's `qualifications` field (already present) → candidate generation
(sourced from `INTERNET_EVIDENCE_AUDIT.csv`'s `scope_restrictions`, unmodified)
→ rendered seed SQL → `retrieve_knowledge_v1`'s return shape →
`formatKnowledgeBlock()`'s `QUALIFICATION=` line → both system prompts'
explicit "state this, never drop it" instruction. `HL-MENS-002` is the named
regression fixture across three separate test files (Python builder test,
Python trust-boundary test, Deno `kb_retrieval.test.ts`), each independently
confirming its qualification text — *"Population-level general guidance
only; never an individual diagnostic boundary."* — survives to the stage
that test checks.

**Phase 3 — hard fail-closed in Dr Niswah.** `dr-niswah-chat` now has the
same pre-generation gate `fiqh-advisor-chat` already had: for a non-urgent
message, if `kbHits.length === 0` after retrieval, Gemini is never called; a
bilingual fallback (`NO_ELIGIBLE_KB_AR`/`NO_ELIGIBLE_KB_EN`) explicitly states
the verified KB lacks sufficient evidence and to consult a professional. This
gate is deliberately reason-agnostic — it fires identically whether
`kbHits` is empty because nothing matched, a row was filtered by
scope/pregnancy-state/postpartum/TTC/qualification rules, or the snapshot is
unrecognized — so it doesn't need per-reason special-casing (and doesn't
depend on state-applicability data this KB doesn't yet have — see Remaining
Risks). The urgent-banner path is untouched: it fires from the independent
keyword scan, never from KB grounding, so a missing KB match can never
suppress a safety escalation.

**Phase 4 — frozen-snapshot enforcement.** New `kb_snapshot_registry` table
(one row per seed run, exactly one `is_current`), `get_active_kb_snapshot()`
RPC, and `evidence_snapshot_commit` column on `knowledge_item_versions`.
`retrieve_knowledge_v1` itself now only returns rows tagged with whatever
commit the registry currently marks active — a second, independent layer
below the edge-function-level check. `kb_retrieval.ts` exports
`assertSnapshotHealth()`, checked by both edge functions whenever retrieval
returns zero hits, distinguishing (in logs only) "nothing matched" from "the
live data is a different snapshot than this code expects" — the user-facing
answer is identical either way, snapshot internals are never exposed to the
client. `render_kb_seed_sql.py` now refuses to render if the candidate
file's `evidence_snapshot_commit` doesn't match the current manifest's
`frozen_at_commit_sha`, and registers the snapshot identity as part of the
same seed transaction.

**Phase 5 — regression and trust-boundary tests.** 25 Python tests
(`test_build_kb_production_candidates.py`: 11, `test_trust_boundary.py`: 14)
plus 13 Deno tests (`kb_retrieval.test.ts`) — **all 38 executed and passing**,
not merely written. Coverage: the full 254/211/43 reconciliation; all three
pregnancy-loss/nifas rows confirmed fail-closed and quarantined; a static
check that `retrieve_knowledge_v1`'s Madhhab filter has no `coalesce`/default
fallback; every row's `human_review_status` confirmed `NOT_REVIEWED`; no
structured status field ever contains `SCHOLAR_APPROVED`/`MEDICALLY_APPROVED`;
all four qualified Health rows' exact qualification text confirmed present at
both the candidate-CSV and rendered-SQL stages; `assertSnapshotHealth`
confirmed to fail closed (not throw) on a missing registry row, a mismatched
commit, and an RPC error; `retrieveKnowledge` confirmed to never call the RPC
at all for Fiqh without a madhhab.

**Phase 6 — CI.** Rewrote `.github/workflows/kb-review-validation.yml`: the
inline assertion that hardcoded the stale 29/14 Fiqh split (root cause of
Finding 12) now reconciles against the disposition master dynamically; both
new Python test suites run as their own step; a new job installs Deno and
runs `deno check` + `deno test` against `kb_retrieval.ts` and both
KB-integrated edge functions. Also added `supabase/functions/deno.json`
(missing repo-wide — even the pre-existing `pregnancy_status.test.ts` and
`ai_user_context.test.ts` failed type-checking without it) and its
`deno.lock`.

## Files changed

`FOUNDER_DECISIONS.md` · `scripts/build_kb_production_candidates.py` (rewrite) ·
`scripts/render_kb_seed_sql.py` (updated) ·
`scripts/test_build_kb_production_candidates.py` (new, 11 tests) ·
`scripts/test_trust_boundary.py` (new, 14 tests) ·
`supabase/migrations/20260929120000_knowledge_base_v1_qualification_and_snapshot.sql` (new) ·
`supabase/functions/_shared/kb_retrieval.ts` (updated) ·
`supabase/functions/_shared/kb_retrieval.test.ts` (new, 13 tests) ·
`supabase/functions/deno.json` (new) · `supabase/functions/deno.lock` (new) ·
`supabase/functions/fiqh-advisor-chat/index.ts` (updated) ·
`supabase/functions/dr-niswah-chat/index.ts` (updated) ·
`.github/workflows/kb-review-validation.yml` (updated) · `.gitignore` (updated).

## Tests added and their results

| Suite | Count | How run | Result |
|---|---|---|---|
| `scripts/test_build_kb_production_candidates.py` | 11 | `python3 -m unittest` | **11 passed** |
| `scripts/test_trust_boundary.py` | 14 | `python3 -m unittest` | **14 passed** |
| `supabase/functions/_shared/kb_retrieval.test.ts` | 13 | `deno test` (Deno installed for this pass, real execution) | **13 passed** |
| Pre-existing `pregnancy_status.test.ts` + `ai_user_context.test.ts` | 37 | `deno test` (re-verified not broken by this pass) | **37 passed** |
| **Total executed this pass** | **75** | | **75 passed, 0 failed** |

Every number above is from an actual run in this session, not a written-but-
unexecuted claim — including installing Deno for the first time in this
environment specifically to verify the TypeScript-side tests rather than
leave them unexecuted.

## CI status

Before this pass: `verify-kb-review-packets` **failing** on PR #6 (confirmed
via `gh pr checks 6` in the prior audit). After pushing this pass's commits,
confirmed live via `gh pr checks 6`:

```
Analyze & Test                                   pass   3m5s
Validate DB migration reproducibility (BR-002)   pass   2m13s
verify-kb-retrieval-deno-tests                   pass    8s
verify-kb-review-packets                         pass    8s
Build Android (debug artifact)                   pending  -- unrelated to this KB work
Build iOS (no-codesign compile check)             pending  -- unrelated to this KB work
```

**The specific check that was failing (`verify-kb-review-packets`) now
passes, confirmed live, not inferred.** The new `verify-kb-retrieval-deno-tests`
job also passes. `Analyze & Test` and the DB-migration-reproducibility check
(pre-existing, unrelated to this KB work) both pass. Only the Android/iOS
build-artifact jobs — unrelated build steps that run on every PR regardless
of KB content — were still pending at last check.

## Remaining risks

1. **Finding 7 (API contract has no explicit "not professionally approved"
   marker) is only partially addressed.** The system prompts now instruct
   the model to communicate the evidence-only status, but this is still a
   prompt-level behavior, not a structural field in the JSON response the
   client receives. Whether the Flutter client's rendering of `citations`/
   `knowledgeGrounded` reinforces or undermines this was not re-verified
   this pass (out of scope — no Dart changes were made). **Recommendation**:
   a founder/product decision on whether the API response itself should
   carry an explicit `evidence_only: true` / disclaimer field, independent
   of prompt behavior.
2. **The "filtered out due to scope/pregnancy-state/postpartum/TTC mismatch"
   half of Phase 3 is satisfied by the gate's reason-agnostic design, not by
   building real state-applicability filtering.** No atom in this KB
   currently carries structured `applicable_user_states` data (the schema
   column exists; it's never populated) — building that would mean
   inventing new structured data for 254 atoms, which is out of this pass's
   scope (`Do not rebuild the KB` / `Do not modify the evidence
   conclusions`). The gate correctly fails closed today because it reacts
   to "zero hits" however that occurs, but it has never actually been
   exercised against a real state-based exclusion, because none exists yet.
3. **Nothing in this pass has been run against a live database.** All
   verification is: (a) real execution of Python/Deno test suites against
   file-based fixtures and static SQL text, (b) `deno check` type-checking,
   (c) live CI on GitHub Actions. No `supabase db push`, no `psql`, no
   actual Postgres instance has executed `retrieve_knowledge_v1`,
   `get_active_kb_snapshot()`, or the RLS policies. The SQL is believed
   correct by inspection and by the `Validate DB migration reproducibility`
   CI check, but true integration testing needs a real database.
4. **The Dart/Flutter client was not touched or re-verified.** Whether the
   app actually surfaces `qualification_note`-derived text, the new
   fail-closed fallback strings, or citation data in a way consistent with
   FD-5's conditions was not checked this pass.
5. **FD-1, FD-2, FD-3 remain `PENDING_FOUNDER_REVIEW`** — unrelated to this
   engineering pass, but still open (canonical menstrual-data authority for
   AI context, TTC's V1 scope, Dream Interpreter's KB positioning).

## Remaining founder decisions

- FD-1, FD-2, FD-3 (see `FOUNDER_DECISIONS.md`) — not addressed by this
  engineering pass; still pending.
- The Finding-7 API-contract question above (not yet a numbered FD; should
  become one if the founder wants it decided explicitly rather than left to
  prompt behavior).

## Remaining expert-review dependencies

Unchanged from `CUTOVER_AUDIT_REPORT.md` / `INTERNET_EVIDENCE_AUDIT_SUMMARY.md`:
the 43 fail-closed Fiqh rows need qualified Madhhab-specific scholarly review
(34 genuinely require choosing among documented positions; 8 need only
wording sign-off on an otherwise single, well-evidenced position); the 3
pregnancy-loss/nifas rows specifically need **joint** scholar-and-medical
review to map classical criteria onto modern clinical terms. None of this
pass's engineering work resolves or attempts to resolve any of that — it
remains exactly as fail-closed as before, by design.

## Is PR #6 technically merge-ready?

**Technical merge readiness and deployment approval are different
questions, and this report answers only the first one.**

**Technically merge-ready, as of this pass: yes, with caveats.** Every
concrete, previously-failing CI check now passes; the previously-crashing
candidate-generation script now runs correctly and is covered by executed
regression tests; the BLOCKER findings from the cutover audit
(qualification-metadata loss, missing Dr Niswah gate, no snapshot
enforcement) have been fixed and verified at the unit/integration-test level
available in this environment. The caveats: no live-database integration
test has been run (Remaining Risk 3), the Flutter client is unverified
(Remaining Risk 4), and Finding 7's product-level question is open.

**This is not deployment approval.** Merging this PR would not, by itself,
change any live behavior — no migration has been applied, nothing has been
deployed, and PR #6 remains draft. Before any deployment (separate from
merge) should be considered: a live-database run of the migration + seed +
verification scripts against a real (non-production) Supabase instance;
Flutter-side verification of the new fallback strings and qualification
surfacing; and founder sign-off on Finding 7. **This report does not
recommend deployment and does not claim the product is production-ready —
it claims the code on this branch is now internally consistent, tested
where testable in this environment, and no longer contains the specific
blockers the cutover audit found.**

PR #6 remains **draft and unmerged**. No migration has been applied to any
database. No deployment has occurred. No additional RAG/embedding work has
begun.
