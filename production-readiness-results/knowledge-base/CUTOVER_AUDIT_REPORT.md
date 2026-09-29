# PR #6 Engineering Cutover Audit Report

**Date**: 2026-09-29. **Scope**: read-only code audit of the KB engineering
already present on `feat/niswah-v1-knowledge-base` (PR #6, draft), checked
against the frozen evidence snapshot (`EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json`,
commit `eda4b96c7b2a77924a3dd86397cbcbba671440b3`). **No production code was
modified to produce this report** — confirmed by `git status`/`git diff`
showing zero changes under `supabase/` or `scripts/` at time of writing. Two
scripts were executed read-only as part of the audit (see Findings 11–12);
neither wrote any output before failing.

## 254-row disposition reconciliation

| | Count |
|---|---|
| Fiqh atoms | 180 |
| Health/Safety atoms | 74 |
| **Total** | **254** |
| Production-eligible | 211 (137 Fiqh + 74 Health/Safety) |
| Fail-closed | 43 (all Fiqh) |
| **Total** | **254** |

Frozen dataset identity: `PRODUCTION_DISPOSITION_MASTER.csv`,
SHA-256 `e6dd52c88f0986058156533754257652b43bca4a771ac42f82e5706049faafea`,
frozen at commit `eda4b96c7b2a77924a3dd86397cbcbba671440b3`,
`2026-09-29T10:40:49Z`. Full manifest: `EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json`.

## Governance decisions still awaiting founder approval

All six entries in `FOUNDER_DECISIONS.md` — none currently `FOUNDER_APPROVED`.
Highest-priority: **FD-5** (evidence-only production-eligibility model,
already implemented in code) and **FD-6** (Fiqh Advisor's live-search removal,
already implemented in code). See that file for the full packet (what
changed / why it matters / implementation state / risks / choices / code
dependency) per entry.

## Code-audit findings, by the 10 required questions

### 1. Can fail-closed rows ever be retrieved as authoritative answers?
**PASS (by design), UNVERIFIED LIVE.** Three independent, redundant controls
all exclude the 43 fail-closed rows:
- `knowledge_sources.evidence_state` and `knowledge_item_versions.evidence_state`
  both carry a `CHECK` constraint allowing only `PRIMARY_SOURCE_VERIFIED` or
  `INSTITUTIONALLY_CORROBORATED` (migration lines 15, 51) — a
  `CONFLICT_OR_JUDGMENT_REQUIRED` row cannot be inserted into either table at
  all, by the database schema itself.
- `build_kb_production_candidates.py` routes any row whose `evidence_status`
  is in `FAIL_CLOSED_FIQH` to a separate quarantine file, never to the
  candidate file, and asserts `production_keys & quarantine_keys` is empty
  (a hard leak check) before writing anything.
- `render_kb_seed_sql.py` reads only the candidate file; the 43 quarantined
  rows are never referenced in the rendered SQL.
- **Caveat**: this is unproven end-to-end. The migration has not been
  applied to any database (correctly, per standing instruction), and the
  candidate-builder script currently cannot run at all (Finding 11) — so
  nothing has actually been seeded, fail-closed or otherwise.

### 2. Does Fiqh retrieval strictly preserve Madhhab boundaries?
**PASS.** Enforced at two layers: `kb_retrieval.ts` refuses to call the RPC
at all for `domain === 'FIQH'` when no `madhhab` is supplied (returns `[]`
immediately); the RPC itself requires `p_madhhab is not null and ki.madhhab
= lower(p_madhhab)` for the `FIQH` domain — an exact match, no fallback, no
cross-madhhab blending. No path was found that could return a Hanafi row to
a Maliki-selected user or vice versa.

### 3. Do Health answers use only production-eligible Health rows?
**PASS at the query layer**, same caveat as #1 (unseeded, unproven live).
`retrieveKnowledge({domain: 'HEALTH', ...})` goes through the identical
`retrieve_knowledge_v1` gate (`publication_state = 'PUBLISHED' AND
production_eligible = true`) as Fiqh.

### 4. Does qualification metadata survive retrieval and reach generation?
**FAIL — HIGH.** Two concrete gaps:
- **No storage path at all.** `knowledge_item_versions` has no column for
  the qualification/scope-restriction text this audit produced (e.g.
  `HL-MENS-002`'s "never state a bare cycle-length number without naming its
  source" — `VERIFIED_WITH_QUALIFICATION`'s entire point). Even if a human
  curator populated the KB from `PRODUCTION_DISPOSITION_MASTER.csv` today,
  there is nowhere to put that column's content.
- **An existing field is silently dropped.** `knowledge_item_versions.safety_class`
  is stored, selected by the RPC, and present on `KnowledgeHit` — but
  `formatKnowledgeBlock()` (`kb_retrieval.ts:47-64`) never includes it in the
  `[KNOWLEDGE]` block sent to Gemini. The data reaches the edge function and
  is then dropped before the model ever sees it, in both `fiqh-advisor-chat`
  and `dr-niswah-chat`.

### 5. Do backend citations originate from the canonical KB, never the model?
**PASS.** `citationPayload()` (`kb_retrieval.ts:66-82`) is built exclusively
from `KnowledgeHit[]`, which comes straight from the RPC result. Gemini's
output (`result.text`) is never inspected for citation extraction in either
edge function — the citations the client receives cannot contain anything
the model invented.

### 6. Does missing evidence cause a fail-closed response rather than model improvisation?
**SPLIT — Fiqh Advisor PASS, Dr Niswah HIGH gap.**
- `fiqh-advisor-chat` has a hard, pre-generation gate: `if (kbHits.length ===
  0) return NO_ELIGIBLE_KB_AR` (lines 109-113) — Gemini is never called when
  there is nothing to ground an answer in.
- `dr-niswah-chat` has **no equivalent gate**. When `kbHits.length === 0`,
  `formatKnowledgeBlock` returns a "no production-eligible knowledge item
  matched" line, but the code still calls Gemini with that line in the
  prompt and relies entirely on the system prompt's instruction ("if no
  qualified knowledge exists, state the limits and refer to a specialist")
  to prevent improvisation. This is a prompt-level mitigation, not a
  code-level one, and is a materially weaker guarantee — especially for a
  domain whose whole premise (Health) can involve safety-relevant claims.

### 7. Can the system accidentally treat evidence verification as Scholar/Medical Approval?
**MEDIUM/HIGH.** Internal governance docs and system prompts consistently
avoid this (`buildSystemInstruction`'s "never invent, broaden, or import a
ruling"; `NO_ELIGIBLE_KB_AR`'s explicit referral to a qualified scholar). But
**the actual API response contract carries no explicit marker** that what
was returned is evidence-verified-only, never scholar- or
clinician-approved. Both edge functions return `{text/reply, citations, ...}`
with real source titles and URLs and no accompanying "not professionally
approved" field. Whether an end user understands the distinction depends
entirely on (a) the model choosing to phrase it that way in free text, and
(b) whatever the Flutter client does with the `citations`/`knowledgeGrounded`
fields — neither was verified in this audit's scope (client-side rendering
of these fields was not re-inspected this pass).

### 8. Are the 34 judgment/conflict Fiqh rows technically blocked?
**PASS**, same mechanism and same live-unproven caveat as #1 — no
special-casing exists or is needed; they are a subset of the 43 the schema
constraint and candidate-builder already exclude categorically.

### 9. Are the three pregnancy-loss/nifas joint-review rows categorically blocked?
**PASS**, same mechanism as #8. `MLK-NIFAS-29`, `SHF-NIFAS-29`,
`HNB-NIFAS-29` are all `CONFLICT_OR_JUDGMENT_REQUIRED` in the frozen
disposition and excluded by the same schema/pipeline controls — no
Nifas-specific carve-out exists in the code, and none is needed given the
general mechanism already covers them.

### 10. Is runtime code tied to the exact frozen KB version/checksum?
**FAIL — BLOCKER.** No column, function parameter, response header, or log
field anywhere in `kb_retrieval.ts`, the migration, or either edge function
references `EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json`'s commit SHA or any
checksum. If this were deployed today and later needed to be audited
("which evidence snapshot produced this specific answer a user saw"), there
would be no way to answer that from the running system alone — only by
correlating deploy timestamps against git history by hand.

## Two additional findings found by actually running the existing pipeline (read-only)

### 11. `build_kb_production_candidates.py` currently crashes — BLOCKER (for re-running the pipeline, not for data safety)
Ran read-only: `python3 scripts/build_kb_production_candidates.py` →
```
Health row HL-MENS-001 is not evidence eligible: None
```
Root cause: the script reads `audit_row.get('audit_status')`
(`build_kb_production_candidates.py:63`) and hardcodes
`EXPECTED_JUDGMENT = 29` / `EXPECTED_INSUFFICIENT = 14`
(lines 15-16, and duplicated in the CI workflow). Both assumptions describe
the **prior, self-reported** audit's column name and status split. This
session's independently-verified `INTERNET_EVIDENCE_AUDIT.csv` uses
`verification_status` (not `audit_status` — the rename was intentional, to
fix the domain-vocabulary-mixing bug documented in
`INTERNET_EVIDENCE_AUDIT_SUMMARY.md`), and
`FIQH_INTERNET_EVIDENCE_AUDIT.csv`'s real split is 34
`CONFLICT_OR_JUDGMENT_REQUIRED` / 8 `PRIMARY_SOURCE_VERIFIED` / 1
`INSTITUTIONALLY_CORROBORATED` — there is no `INSUFFICIENT_EVIDENCE` value
in this session's Fiqh vocabulary at all. The script crashes on the very
first Health row before writing any output — confirmed no file was created
under `generated/`. This is a **fail-safe failure mode** (it stops rather
than silently mis-classifying), but it means the entire deploy pipeline
(`deploy_kb_v1.sh` calls this script as step 2 of 7) cannot currently run to
completion.

### 12. CI check `verify-kb-review-packets` is failing on PR #6 right now
Confirmed live via `gh pr checks 6`:
```
verify-kb-review-packets   fail   7s
Analyze & Test              pass  3m23s
Validate DB migration reproducibility (BR-002)   pass  2m0s
```
This is the same root cause as Finding 11 — the CI job's inline Python
(`.github/workflows/kb-review-validation.yml`) hardcodes the identical stale
`29`/`14` split. This is not a theoretical risk; it is the actual, current
state of PR #6's checks as of this report.

## Existing code that can remain as-is

- The RLS/`revoke all` posture on all 5 new KB tables (no direct client
  reads; service-role/RPC-only access) — sound.
- The `retrieve_knowledge_v1` RPC's Madhhab-exact-match gate, relevance
  threshold (`score >= 0.12`), and `PUBLISHED`+`production_eligible` filter —
  sound, matches audit questions 1-3, 8-9.
- `citationPayload()`'s dedup-from-DB-only design — sound, matches question 5.
- `fiqh-advisor-chat`'s pre-generation empty-KB gate — sound, matches
  question 6, and is the pattern `dr-niswah-chat` should be brought up to
  (see below).
- `render_kb_seed_sql.py`'s stale-data retirement logic (anything published
  before that's absent from today's candidate set gets `RETIRED`, and its
  versions get `production_eligible = false`) — sound design, just currently
  unreachable because step 2 of the pipeline crashes first.

## Existing code that must change before this is mergeable

1. `build_kb_production_candidates.py` (and the CI workflow's inline
   assertions): update to read `verification_status` /
   `production_eligibility` from the current `INTERNET_EVIDENCE_AUDIT.csv`
   schema, and to count against the real 34/8/1 Fiqh split instead of the
   stale 29/14. **Currently causes a real, live CI failure (Finding 12).**
2. `kb_retrieval.ts`'s `formatKnowledgeBlock()`: stop dropping
   `safety_class`; add a field for qualification/scope-restriction text once
   the schema gains a column for it (see #4 below).
3. Migration schema: add a qualification/scope-restriction text column to
   `knowledge_item_versions` (Finding 4) — without it, `VERIFIED_WITH_QUALIFICATION`
   content has no way to carry its qualification into a generated answer.
4. `dr-niswah-chat`: add the same pre-generation empty-KB gate
   `fiqh-advisor-chat` already has, rather than relying on a prompt
   instruction alone (Finding 6).
5. Add a snapshot-identity mechanism (at minimum, log the frozen manifest's
   commit SHA/checksum alongside each retrieval call or each seed run; at
   best, store it in the database and expose it from the RPC) so runtime
   behavior is traceable to a specific frozen evidence snapshot (Finding 10).
6. Consider surfacing an explicit "evidence-verified, not
   scholar/medically-approved" field in the API response contract itself,
   not only in the system prompt (Finding 7) — this is a product decision
   (how/whether to surface it in the UI) as much as an engineering one.

## Exact prerequisites before PR #6 can be considered mergeable

1. Founder resolves FD-1 through FD-6 in `FOUNDER_DECISIONS.md` — in
   particular FD-5 (is the evidence-only model acceptable at all) and FD-6
   (is removing live Fiqh search acceptable) — since code changes 1-6 above
   are largely moot if the founder rejects the underlying model.
2. Findings 11/12 fixed: the candidate-builder script and CI workflow
   updated to match the current, correct audit-file schema and real
   34/8/1 Fiqh split. **PR #6 cannot pass its own CI gate today.**
3. Finding 4 addressed: a qualification/scope-restriction column added to
   the schema and threaded through `formatKnowledgeBlock()`, and the
   already-fetched `safety_class` field stopped being silently dropped.
4. Finding 6 addressed: `dr-niswah-chat` given a hard empty-KB gate matching
   `fiqh-advisor-chat`'s pattern.
5. Finding 10 addressed: some mechanism ties a live retrieval/seed run back
   to a specific frozen evidence snapshot identity.
6. A decision (founder or delegated) on Finding 7: whether/how the API
   contract itself should mark evidence-only content as such.

None of the above have been implemented as part of this audit, per
instruction. **PR #6 remains draft and unmerged. No migration has been
applied to any database. No deployment has occurred. No additional
RAG/embedding work has begun.**
