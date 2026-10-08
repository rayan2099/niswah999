# Pre-Merge Integration Validation Report

**Date**: 2026-09-29. **Scope**: validate the remediated KB architecture
(`ENGINEERING_REMEDIATION_REPORT.md`) against a real database/runtime
environment, and resolve Finding 7 (API-contract risk). All work committed
incrementally to `feat/niswah-v1-knowledge-base` (PR #6, still draft).
**No production database was touched. No deployment occurred. No merge.**

## Environment used

- **Database**: a genuinely disposable local Postgres 17.6 instance, started
  via `supabase start` (Docker containers on this machine — Docker Desktop
  was not running at the start of this pass; it was started specifically for
  this validation). `DB_URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres`,
  accessed via `docker exec supabase_db_Niswah psql ...` (no local `psql`
  binary was available).
- **Edge functions**: served locally via `supabase functions serve
  --env-file supabase/functions/.env` against that same local database.
- **Auth**: a real local test user, created via the local GoTrue signup
  endpoint (`http://127.0.0.1:54321/auth/v1/signup`), used to obtain a real
  JWT for every edge-function HTTP call below.
- **Model credentials**: `supabase/functions/.env` already contained a
  `GEMINI_API_KEY` (pre-existing in this repo, from earlier work on this
  project). It returned `401 Unauthorized` from Google's real endpoint on
  every call — this pass did not attempt to obtain, guess, or replace it.
- **Deno**: installed this session (`curl -fsSL https://deno.land/install.sh | sh`)
  to run `deno check`/`deno test` for real rather than leaving the
  TypeScript-side tests unexecuted.
- **Flutter**: `flutter analyze` and `flutter test` run directly against
  this repo's existing toolchain (Flutter 3.47.0 / Dart 3.13.0), already
  installed.

## Phase 1 — Migrations actually executed

`supabase db reset` (full clean rebuild + apply all migrations in order,
including both KB migrations) — run **twice**, both times exit-clean, both
times ending with all 6 prior migrations plus the 2 KB migrations applied
and tracked in `supabase_migrations.schema_migrations`.

**Found and fixed a real defect**: re-running
`20260929114500_knowledge_base_v1.sql` in isolation (after
`20260929120000_..._qualification_and_snapshot.sql` had already widened
`retrieve_knowledge_v1`'s return shape) failed:
```
ERROR:  cannot change return type of existing function
DETAIL:  Row type defined by OUT parameters is different.
```
Fixed with `drop function if exists ...` before `create or replace function`
(matching the pattern the later migration already used). Re-ran both
migration files in sequence after the fix — both exited 0, and `\df` confirmed
the function's final shape was correct either way. Committed separately
(`5c036ea`).

**Verified directly via SQL** (not reasoning from SQL text):
- `knowledge_item_versions`, `kb_snapshot_registry`, and all other new
  columns/tables exist with the exact structure the migration specifies
  (`\d` output captured for both).
- RLS is enabled on every new table with **zero** policies — confirmed via
  `information_schema.table_privileges` that `anon`/`authenticated` have
  **no** direct grants on any of the 4 KB tables.
- `retrieve_knowledge_v1` and `get_active_kb_snapshot` both exist with the
  exact expected return shape (including `qualification_note`) and are
  granted `EXECUTE` only to `postgres`/`authenticated` (never `anon`) —
  confirmed via `information_schema.routine_privileges`.
- No rollback/down-migration convention exists anywhere in this repo
  (checked via `find`/`grep`) — this is a pre-existing, repo-wide
  forward-only convention, not something PR #6 introduces or omits
  differently.

## Phase 2 — Real KB ingestion

Ran the real pipeline: `build_kb_production_candidates.py` →
`render_kb_seed_sql.py` → loaded the rendered SQL directly into the local
database via `docker exec -i ... psql < PRODUCTION_KB_SEED.sql`
(`ON_ERROR_STOP=1`, exit 0, ends in `COMMIT`).

**Independently verified via SQL against the live database** (not the
generation scripts' own output):

| Query | Result |
|---|---|
| `knowledge_items` by domain (PUBLISHED) | FIQH 137, HEALTH 59, SAFETY_ESCALATION 15 → **211** |
| Fiqh items by madhhab | hanafi 33, maliki 33, shafii 34, hanbali 37 → **137** |
| The 43 fail-closed atom IDs (5 spot-checked, incl. all 3 pregnancy-loss/nifas rows) present in `knowledge_items`? | **0 rows** — genuinely absent |
| `kb_snapshot_registry` | exactly 1 row, `is_current=true`, commit `eda4b96c...`, `254/211/43` |

211 + 43 (never loaded) = 254, reconciling exactly to the frozen disposition.

## Phase 3 — End-to-end retrieval validation (real `retrieve_knowledge_v1` calls)

**Madhhab boundary — the core trust-boundary claim, proven directly**: the
exact same query text (`"bleeding beyond ten days"`) run with
`p_madhhab='hanafi'` / `'maliki'` / `'shafii'` / `'hanbali'` returned four
completely disjoint result sets — every `knowledge_key` returned was
prefixed for its own madhhab and never any other (`HNF-*` only under
hanafi, `MLK-*` only under maliki, etc.). No overlap in any direction.

**Fail-closed rows genuinely unreachable**: querying with text drawn
*directly from a fail-closed row's own proposition* (`HNF-HAID-09`'s
yellow/brown-discharge wording; `MLK-NIFAS-29`'s pregnancy-loss wording)
never returned that row — because it was never loaded at all (confirmed
above). Ten other, real, eligible Hanafi/Maliki rows were returned instead
each time.

**Nonexistent proposition**: a gibberish Fiqh query returned 0 rows.

**Qualification metadata returned from the real RPC, not just present in
seed data** — all 4 `VERIFIED_WITH_QUALIFICATION` Health rows checked
individually, each returning its exact qualification text:

| Atom | `qualification_note` returned by the live RPC |
|---|---|
| `HL-MENS-002` | *"Population-level general guidance only; never an individual diagnostic boundary."* |
| `HL-MENS-003` | *"Escalation/education threshold, not a diagnosis. Threshold value is source-specific..."* |
| `HL-PREG-012` | *"Saudi-market localization, explicitly scoped as such in the corrected wording."* |
| `HL-TTC-011` | *"General referral-timing guidance."* |

Other, non-qualified rows returned in the same result sets correctly had an
**empty** `qualification_note` — confirming the field is genuinely
item-specific, not a template artifact.

**Real finding — retrieval precision gap (not a trust-boundary breach)**: a
deliberately unrelated gibberish query (`"purple elephant spacecraft
unrelated nonsense"`) against the HEALTH domain returned **1 row**
(`HL-POST-010`) at `rank_score = 0.1334` — just above the `0.12` threshold.
Calibration against genuine matches in this pass (weakest observed genuine
secondary match: `0.2`) suggests the threshold has some margin for
false-positive matches on certain strings. **This is not a trust-boundary
violation** — `HL-POST-010` is a real, `PRODUCTION_ELIGIBLE` row; nothing
fail-closed or quarantined was ever returned in any test in this entire
pass. It is a genuine, reproducible retrieval-precision finding: the
"no eligible evidence" case is reached less reliably for Health than for
Fiqh (where the identical nonsense string returned 0 rows). **Not changed
in this pass** — a threshold adjustment based on 4-5 data points risks
under- or over-correcting without a much larger test corpus, and this pass
was scoped to validate the existing architecture, not re-tune it. Recorded
as a remaining risk below.

## Phase 4 — Edge-function integration (real HTTP calls, real database, real auth)

Both `fiqh-advisor-chat` and `dr-niswah-chat` served locally and called via
real signed HTTP requests with a real JWT.

**DATABASE/RUNTIME PATH VERIFIED** for both functions: auth check → rate
limit → madhhab validation (Fiqh) / red-flag scan (Dr Niswah) → KB retrieval
against the real database → (reaching, and attempting, the Gemini call).
**MODEL CALL NOT EXECUTED**: every attempted Gemini call failed with a real
`401` from Google's endpoint (invalid/expired key already in this repo's
local dev `.env`, not something this pass obtained or needs to obtain to
prove the rest of the chain). This distinction is made explicitly per every
result below.

| Test | Result |
|---|---|
| Fiqh, no madhhab selected | Correct Arabic "select your madhhab first" text, `citations: []` — no RPC call, no Gemini call |
| Fiqh, on-topic Hanafi question | Reached Gemini (401) — proves auth → rate-limit → retrieval all succeeded first |
| Fiqh, genuinely no-match gibberish (confirmed 0 rows at SQL level first) | Exact `NO_ELIGIBLE_KB_AR` text, `citations: []` — **gate fired before any Gemini call** (confirmed via server log: no new Gemini attempt logged) |
| Fiqh, invalid/SQL-injection-style madhhab string | `400 {"error":"Invalid madhhab."}` — rejected before reaching the database at all; `knowledge_items` count unchanged (211) afterward |
| Fiqh, **no active snapshot registered** (registry corrupted for this test, then restored) | Exact `NO_ELIGIBLE_KB_AR` text — fail-closed gate fired end-to-end through the real edge function, not just at the SQL layer |
| Dr Niswah, on-topic Health question | Reached Gemini (401); response included real, KB-sourced citations with correct `title`/`url`/`locator` |
| Dr Niswah, urgent red-flag message ("severe bleeding right now") | `urgent: true`, correct Arabic urgent banner text, returned **regardless** of the Gemini 401 — confirms the safety-banner path is fully independent of KB/model availability |
| Dr Niswah, genuinely no-match gibberish (Fiqh-confirmed-0 string) | Reached Gemini (401) instead of hard-gating — **this is the Health-domain precision finding above, observed end-to-end**: `HL-POST-010` matched weakly, so `kbHits.length` was 1, not 0 |

## Phase 5 — Finding 7 resolution (real, concrete gaps found and fixed)

Investigated the actual Flutter call sites
(`ai_advisor_service.dart`, `dr_niswah_backend_service.dart`,
`chat_view_model.dart`, `dr_niswah_chat_screen.dart`) against the real
backend response shape. Found two genuine producer/consumer gaps — neither
was a crash (defensive `?? 0`/`?? ''` defaults absorbed both), both were
silent data loss:

1. **`FiqhCitation.fromJson` never parsed `locator`.** The backend has sent
   it since the KB cutover; the Dart model silently dropped it. **Fixed**:
   added as an optional field (default `''`), fully backward compatible —
   verified via `grep` that `startIndex`/`endIndex` (the old
   Google-Search-grounding character offsets) are read nowhere else in the
   codebase, so kept as harmless always-0 fields rather than removed.
2. **Dr Niswah's citations never reached the UI, through either of the two
   paths that could carry them.** `dr-niswah-chat`'s persisted
   `chat_messages.metadata` carried only a `citation_count` (a number),
   never the actual citation objects `dr_niswah_chat_screen.dart` reads from
   `metadata['citations']`; and `DrNiswahBackendResponse` (the live-response
   model) never parsed `citations`/`knowledgeGrounded` from the JSON at
   all — so even `ChatViewModel.sendViaDrNiswahBackendForTesting`'s
   locally-built optimistic message (confirmed, via its own doc comment, to
   be the real production send path, `@visibleForTesting` only for a
   pre-existing DI-seam reason) never had citation data to put in its own
   metadata either. **Fixed all three places**, mirroring the Fiqh Advisor
   path exactly and reusing `FiqhCitation` for both (the backend shape is
   identical for both edge functions).

**Documented request/response contracts** (current, as verified this pass):

- **`fiqh-advisor-chat` request**: `{question, madhhab, madhhab_state,
  clientFiqhState?}`. **Response**: `{text, citations: FiqhCitation[]}` or
  `{error}` (400/401/502). No nullable-field surprises found — `citations`
  is always an array, never null.
- **`dr-niswah-chat` request**: `{threadId, content}`. **Response**:
  `{reply, urgent, messageId, citations: FiqhCitation[], knowledgeGrounded}`
  or `{error}` (400/401/500). `messageId` is `null` when persistence failed
  or fail-closed short-circuited before persistence — the client already
  tolerates this.
- **Citation payload** (both functions, identical shape):
  `{knowledgeKey, versionId, sourceKey, title, locator, url,
  contentLanguage}`, mapped by `FiqhCitation.fromJson` to
  `{url, title, locator, startIndex: 0, endIndex: 0}`.
- **Qualification payload**: not a separate JSON field — carried inside the
  model's own reply text, per the system-prompt instruction added in the
  Engineering Remediation Pass ("state this scope restriction, never drop
  it"). Not independently verifiable this pass (model calls didn't
  execute) — see Remaining Risks.
- **Snapshot/version information**: not exposed in either function's client
  response at all (deliberately — see `kb_retrieval.ts`'s own comment: never
  expose snapshot internals to the client). Only observable server-side via
  logs or `get_active_kb_snapshot()`.
- **Fail-closed response**: identical shape to a normal response
  (`{text/reply, citations: [], ...}`) with a specific, honest fallback
  string — never a distinct error shape, so the client's existing
  success-path rendering already handles it with no special-casing needed.

**Contract tests added**: `test/ai_backend_citation_contract_test.dart`
(6 tests) — encodes the exact current wire shape so a future field rename on
either side fails a test instead of silently regressing again (exactly what
happened with `locator` before this pass).

## Phase 6 — Flutter integration validation

- `flutter analyze` (whole repo): **43 issues, all `info` severity**
  (pre-existing deprecation/style lints unrelated to this pass), **zero
  errors, zero warnings**. The one hint on a file this pass touched
  (`ai_advisor_service.dart:101`) is on a line this pass did not modify.
- `flutter test` on every test file referencing the touched files
  (`ai_backend_citation_contract_test.dart`,
  `dr_niswah_red_flag_dual_state_test.dart`,
  `ai_chat_persistence_resilience_test.dart`): **16/16 passed.**
- Citation rendering, fail-closed handling, and empty-evidence handling are
  all exercised by the contract tests and the existing red-flag test; a
  true end-to-end (network-backed) test of the Dr Niswah success path could
  not be added without changing `DrNiswahBackendService`'s hardcoded-
  singleton DI structure (a pre-existing constraint, documented in the
  code's own comments) — doing so would be exactly the "redesign the
  Flutter application" this pass was told not to do. Stated explicitly
  rather than silently claimed as covered.

## Phase 7 — Security and fail-closed smoke tests

| Test | Result |
|---|---|
| Client requests a quarantined atom directly, bypassing retrieval | **No such path exists** — confirmed by code inspection: `retrieveKnowledge()`'s params are `{domain, language, query, madhhab, limit}`, no `knowledge_key` parameter anywhere in the API surface |
| Arbitrary Madhhab input defeats filtering | **No** — rejected with `400` at the edge-function layer before reaching the database; separately, a SQL-injection-style string passed directly to the RPC returned 0 rows and left `knowledge_items` at 211 rows, unchanged |
| Malformed snapshot identity | **Fails safely** — a fabricated commit registered as current returned 0 rows (real rows are tagged with the real commit, not the fake one) |
| Missing snapshot | **Fails safely** — no `is_current` row at all returned 0 rows at the SQL layer and the exact `NO_ELIGIBLE_KB_AR` fallback at the edge-function/HTTP layer |
| Stale snapshot | Same mechanism and same result as "malformed" above |
| Malformed/empty evidence causes model-authoritative fallback | **Mostly no** — Fiqh: confirmed the gate fires before Gemini for a genuinely-zero-match query. Health: **see the Phase 3 precision finding** — a spurious weak match meant the gate didn't fire for one specific gibberish string, and Gemini was attempted (which then failed for an unrelated reason, 401) |
| Canonical citation fields substituted by arbitrary model text | **No** — structurally impossible; confirmed via code (`citationPayload` reads only `KnowledgeHit[]`) and via every live HTTP response this pass captured, where every citation traced to a real KB row |
| Health qualification metadata silently discarded | **Was happening, now fixed** — see Phase 5. Confirmed via a direct negative DB test that `evidence_state='SCHOLAR_APPROVED'` is rejected by the schema's `CHECK` constraint (`ERROR: violates check constraint "knowledge_sources_evidence_state_check"`) — human-review status cannot be transformed into scholar/medical approval at the data layer, independent of any application code |

## Full automated test totals (this pass + carried forward)

| Suite | Count | Result |
|---|---|---|
| Python (`test_build_kb_production_candidates.py` + `test_trust_boundary.py`) | 25 | **25 passed** |
| Deno (`kb_retrieval.test.ts` + pre-existing `pregnancy_status.test.ts` + `ai_user_context.test.ts`) | 50 | **50 passed** |
| Flutter/Dart (`ai_backend_citation_contract_test.dart` + `dr_niswah_red_flag_dual_state_test.dart` + `ai_chat_persistence_resilience_test.dart`) | 16 | **16 passed** |
| **Total automated tests executed this pass** | **91** | **91 passed, 0 failed** |

Plus every manual database/HTTP/security test in Phases 1-4 and 7 above —
executed live, with actual commands and actual output captured, not
reasoned from source text.

## PR check status (`gh pr checks 6`, confirmed live after this pass's pushes)

```
Analyze & Test                                   pass   2m59s
Validate DB migration reproducibility (BR-002)   pass   2m3s
verify-kb-retrieval-deno-tests                   pass    10s
verify-kb-review-packets                         pass    10s
Build Android (debug artifact)                   pending  -- unrelated to this KB work
Build iOS (no-codesign compile check)             pending  -- unrelated to this KB work
```

Every check that has ever failed on this PR during this whole workstream
(`verify-kb-review-packets`) now passes, confirmed live, twice, across two
separate pushes. Only the pre-existing, KB-unrelated native-build artifact
jobs remain pending (they take longer and run on every PR regardless of
content).

## Remaining known risks

1. **Health-domain retrieval precision** (Phase 3/7 finding): the `0.12`
   relevance threshold let one specific gibberish string spuriously match a
   real, eligible row. Not a trust-boundary breach; a genuine precision gap.
   Needs a broader test corpus before any threshold change — not touched
   this pass.
2. **No real Gemini call ever succeeded in this pass.** Everything up to
   and including the attempt is DATABASE/RUNTIME PATH VERIFIED; the model's
   actual behavior (does it really state the `QUALIFICATION=` line? does it
   really stay within the `[KNOWLEDGE]` block's content?) remains
   MODEL CALL NOT EXECUTED. This is the single largest remaining gap
   between "verified" and "will behave correctly in production."
3. **The Dr Niswah view-model success path has no true unit test** (the
   `DrNiswahBackendService` singleton has no DI seam) — covered by manual
   HTTP testing this pass, not by an automated regression test. Adding one
   would require a DI change, explicitly out of scope.
4. **This was a single local Docker/Postgres instance**, not a staging
   environment matching production configuration (connection pooling,
   `pgbouncer`, resource limits, network topology). Behavior under load or
   under production infrastructure specifics is unverified.
5. **FD-1, FD-2, FD-3 remain `PENDING_FOUNDER_REVIEW`** — unchanged by this
   pass.

## Remaining expert-review dependencies

Unchanged: the 43 fail-closed Fiqh rows need qualified Madhhab-specific
scholarly review (34 genuinely require choosing among documented positions;
8 need only wording sign-off); the 3 pregnancy-loss/nifas rows need joint
scholar-and-medical review. This pass re-confirmed, at the live-database
level, that all 43 remain completely absent from the retrievable dataset —
it did not attempt to resolve any of them.

## Remaining founder decisions

- FD-1, FD-2, FD-3 (`FOUNDER_DECISIONS.md`) — unchanged, still pending.
- Whether the Health-domain relevance threshold should be tuned (Risk 1
  above) before or after merge — a product/quality decision, not resolved
  by this pass.
- Whether real model-call validation (Risk 2) is a blocking prerequisite for
  deployment specifically (as distinct from merge) — this report takes no
  position beyond stating the gap plainly.

---

## TECHNICALLY MERGE-READY: **YES**

Every specific blocker from `CUTOVER_AUDIT_REPORT.md` and every specific
gap from `ENGINEERING_REMEDIATION_REPORT.md` has now been exercised against
a real database, real edge functions over real HTTP, and a real (if
credential-limited) model-call attempt — not just unit-tested or reasoned
about. The one CI check that was ever actually failing now passes,
confirmed live twice. The two real Flutter-side contract gaps this pass
found (`locator` dropped, Dr Niswah citations never threaded through) are
fixed and covered by new contract tests. 91 automated tests pass. No
migration or seed step failed against a real Postgres instance. No
trust-boundary violation was produced by any test in this entire pass —
every attempt to leak a fail-closed row, cross a Madhhab boundary, forge a
citation, or silently fall back to pretrained-model knowledge on missing
evidence either failed to do so or (in the one Health-precision case) fell
short of ideal without ever crossing into unsafe territory (no fail-closed
content was ever returned; only a real, eligible, if irrelevant, row).

## READY FOR PRODUCTION DEPLOYMENT: **NO**

Merge-readiness is a statement about this code's internal consistency and
tested behavior against a disposable environment. Deployment approval would
additionally require: real model-call validation (Risk 2 — currently
untested end-to-end, only up to the attempt), a decision on the Health
retrieval-precision gap (Risk 1), testing against actual production-shaped
infrastructure rather than a single local Docker instance (Risk 4), and
resolution of FD-1/FD-2/FD-3. **This report does not recommend deployment.**

PR #6 remains **draft and unmerged**. No migration was applied to any
production database. No deployment occurred. The local disposable
environment used for this pass is exactly that — disposable, local, and
never touched anything outside this machine's Docker containers.
