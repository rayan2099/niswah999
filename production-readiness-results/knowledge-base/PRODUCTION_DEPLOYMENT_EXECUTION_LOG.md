# Production Deployment Execution Log — Niswah

Founder authorization received: 2026-10-04T06:3x UTC (see conversation
record). Target: production project `jkmjobvxfrmuwafczvtw` / `Niswah`
only. This log records each production step and its result, with
timestamps. **No secret value is ever recorded here** — only booleans,
counts, non-secret identifiers, and status.

---

## PRE-MUTATION CHECKS

| Time (UTC) | Check | Result |
|---|---|---|
| 2026-10-04T06:34:48Z | Project identity | `ref=jkmjobvxfrmuwafczvtw`, `name=Niswah`, `status=ACTIVE_HEALTHY` — confirmed |
| 2026-10-04T06:34:48Z | Backup freshness | No on-demand "trigger backup now" endpoint exists in the Management API (confirmed by inspecting the full backups API surface: `GET backups`, `POST restore`/`restore-pitr`/`restore-point`/`undo`, `GET/PATCH schedule` — none trigger an immediate backup). Most recent `COMPLETED` physical backup: `2026-10-03T16:23:44.613Z` — **~14h11m old** at mutation time. `walg_enabled=true`, `pitr_enabled=false`, unchanged. Treated as "confirmed" (the applicable verb, since "take" has no API mechanism) and accepted as sufficient, consistent with the already-documented ~24h RPO. |
| 2026-10-04T06:36Z | Edge Function body snapshots (rollback safety net) | All 4 saved successfully via `GET /functions/{slug}/body`: `ai-assistant-chat` 333105 bytes, `dr-niswah-chat` 353030 bytes, `dream-interpreter-chat` 336139 bytes, `fiqh-advisor-chat` 339990 bytes — all nonzero, saved to local scratch (not committed; binary deploy artifacts, not secrets, but kept out of the repo regardless). |
| 2026-10-04T06:37Z | Local pre-steps: verify_kb_review_packets.py / build_kb_production_candidates.py / render_kb_seed_sql.py | All PASS. 211 production candidates, 43 quarantined, snapshot commit `eda4b96c7b2a` — no production touch. |

## MUTATION 1 — Migration #5: `20260929114500_knowledge_base_v1.sql`

| Time (UTC) | Action | Result |
|---|---|---|
| 2026-10-04T06:37:30Z | Applied via `POST /database/migrations` (platform migration-apply; no DB password needed), with an explicit rollback script and idempotency key `niswah-prod-deploy-20260929114500` | API call completed |
| 2026-10-04T06:37Z (immediately after) | **Independently verified via direct schema introspection** (not just trusting the API response): all 5 KB tables present (`knowledge_sources`, `knowledge_items`, `knowledge_item_versions`, `knowledge_item_sources`, `knowledge_citations`), `retrieve_knowledge_v1` function exists, `pg_trgm` extension installed | **PASS** |

## MUTATION 2 — Migration #6: `20260929120000_knowledge_base_v1_qualification_and_snapshot.sql`

| Time (UTC) | Action | Result |
|---|---|---|
| 2026-10-04T06:38:13Z | Applied via `POST /database/migrations`, idempotency key `niswah-prod-deploy-20260929120000` | API call completed |
| 2026-10-04T06:38Z (immediately after) | Independently verified: `kb_snapshot_registry` table exists, `get_active_kb_snapshot()` function exists, `knowledge_item_versions.qualification_note`/`evidence_snapshot_commit` columns present | **PASS** |

## MUTATION 3 — Migration #7: `20260930130000_retrieve_knowledge_v1_relevance_anchor.sql`

| Time (UTC) | Action | Result |
|---|---|---|
| 2026-10-04T06:38:47Z | Applied via `POST /database/migrations`, idempotency key `niswah-prod-deploy-20260930130000` | API call completed |
| 2026-10-04T06:39Z | Independently verified: `retrieve_knowledge_v1`'s live function body (via `pg_get_functiondef`) contains the relevance-anchor logic and comment | **PASS** |
| 2026-10-04T06:39Z | Consolidated post-migration tally: 5 `knowledge_*` tables, 1 `kb_snapshot_registry`, 3 KB functions present, `knowledge_items` = 0 rows, `kb_snapshot_registry` = 0 rows (expected — seed not yet loaded) | **PASS** |
| 2026-10-04T06:39Z | RPC smoke-call attempt via the Management API's read-only query endpoint returned `HTTP 400 / permission denied for function retrieve_knowledge_v1` (Postgres 42501) | **Investigated, not a defect**: the read-only endpoint runs as `supabase_read_only_user` (confirmed via `select current_user`), a role deliberately not present in the function's ACL. `pg_proc.proacl` confirms `authenticated=X` (and `anon`/`service_role`/`postgres`) are correctly granted EXECUTE — matching staging's identical ACL pattern exactly. Real callability (as `authenticated`, via the deployed Edge Functions) is what the acceptance matrix below actually proves. |

All 3 migrations applied and independently verified. Zero production mutation beyond these 3 additive migrations occurred.

## MUTATION 4 — KB seed load (211 eligible atoms)

| Time (UTC) | Action | Result |
|---|---|---|
| 2026-10-04T06:41:08Z | Loaded `PRODUCTION_KB_SEED.sql` (777KB, transactional `begin;`/`commit;`) via `POST /database/migrations`, idempotency key `niswah-prod-deploy-kb-seed-20261004` | API call completed |
| 2026-10-04T06:41Z | Independently verified: `knowledge_items` = 211 (FIQH 137, HEALTH 59, SAFETY_ESCALATION 15 — 59+15=74, matching "74 Health/Safety + 137 Fiqh = 211" exactly), `knowledge_item_versions` = 285 | **PASS** |
| 2026-10-04T06:41Z | Snapshot registry: 1 row, `commit_sha=eda4b96c7b2a77924a3dd86397cbcbba671440b3`, `is_current=true`, `total_atoms=254`, `production_eligible_count=211`, `fail_closed_count=43` | **PASS — exact match** |
| 2026-10-04T06:42Z | `scripts/verify_kb_live.sql` run via the read-only query endpoint (psql meta-command `\set` stripped first — not real SQL, rejected by the endpoint as a syntax error, unrelated to the gate itself): completed with **no exception raised** (the script's own `DO` block only raises on failure) | **PASS** |
| 2026-10-04T06:42Z | `scripts/verify_kb_retrieval_live.sql` run the same way: failed with `permission denied for function retrieve_knowledge_v1` (Postgres 42501) | **Tooling limitation, not a gate failure** — identical root cause to the earlier RPC-callability check: the Management API's read-only endpoint runs as `supabase_read_only_user`, a role deliberately absent from the function's ACL (confirmed via `pg_proc.proacl`: only `postgres`/`anon`/`authenticated`/`service_role` are granted). This script's actual safety property (Madhhab isolation, Arabic routing, low-relevance fail-closed) is proven instead by the production acceptance matrix below, using real authenticated sessions — the function's actual intended caller, and a more faithful test than an unprivileged role could ever provide. |

## MUTATION 5 — Production OpenAI secrets

| Time (UTC) | Action | Result |
|---|---|---|
| 2026-10-04T06:43:52Z | `npx supabase secrets set --env-file <minimal, OpenAI-only file> --project-ref jkmjobvxfrmuwafczvtw` (dedicated production key, never staging's, per founder decision) | `{"count":2,"message":"Finished supabase secrets set."}` |
| 2026-10-04T06:44Z | Verified secret **names** only: `OPENAI_API_KEY` present, `OPENAI_MODEL` present, `GEMINI_API_KEY` still present (left in place per founder decision), `SUPABASE_ACCESS_TOKEN` confirmed **not** leaked onto production | **PASS** |

## MUTATION 6 — Edge Function deployment (OpenAI cutover)

| Time (UTC) | Action | Result |
|---|---|---|
| 2026-10-04T06:44:21Z | Deployed all 4 functions via `npx supabase functions deploy <name> --project-ref jkmjobvxfrmuwafczvtw --use-api` (replacing the live Gemini-based code) | All 4: `{"project_ref":"jkmjobvxfrmuwafczvtw", ...}` confirmed |
| 2026-10-04T06:45Z | Verified new versions, all `ACTIVE`: `ai-assistant-chat` v9→v11, `dr-niswah-chat` v15→v17, `dream-interpreter-chat` v9→v11, `fiqh-advisor-chat` v9→v11 | **PASS** |

## PRODUCTION ACCEPTANCE MATRIX

All cases use fresh synthetic Supabase Auth accounts (`@niswah-production-test.invalid`), real HTTP calls to the deployed functions, real OpenAI calls. No real user data touched.

| Case | Result |
|---|---|
| Fiqh, per-Madhhab (Hanafi/Maliki/Shafi'i/Hanbali) | **PASS** — all 4 returned real, distinct answers with 8 citations each |
| Cross-Madhhab leakage attempt | **PASS** — refused (0 citations, fail-closed Arabic message) |
| Unresolved-state fail-closed | **PASS** — 0 citations |
| Nifas-adjacent fail-closed | **PASS** — 0 citations |
| Qualified Health (`HL-MENS-002` explicit) | **PASS** — retrieved, qualification present in reply |
| Ordinary Health | **PASS** — `knowledgeGrounded=true`, 12 citations |
| Relevance gate (gibberish) | **PASS** — `knowledgeGrounded=false`, 0 citations |
| Urgent Health | **PASS** — `urgent=true`, banner present, `knowledgeGrounded=true`, 16 citations |
| Citation fidelity (Hanafi Fiqh + qualified Health, cross-checked against `PRODUCTION_KB_CANDIDATES.csv`) | **PASS** — zero fabricated/mismatched citations |
| OpenAI provider cutover | **PASS** — every case above is a real, successful OpenAI-backed response (not Gemini) |
| DB/RPC health | **PASS** — every call above succeeded end-to-end, confirming `retrieve_knowledge_v1`/snapshot checks work correctly under real `authenticated` sessions |

One transient `ConnectionResetError` occurred in this session's own Python test client during a session-creation call — not a function/server error, not reproducible on retry, not one of the defined rollback triggers (no safety gate involved; retried successfully).

## PRODUCTION SENTRY TEST

| Time (UTC) | Action | Result |
|---|---|---|
| 2026-10-04T06:5xZ | Reused DSN (founder decision), one synthetic non-sensitive exception, `environment=production`, via a temporary `flutter_test` file mirroring the staging mechanism exactly | Real event ID `65d589c890474245a37b337e487d3821` returned, no transport exception. Same basis as staging's `PARTIAL` result — arrival not independently confirmable from this environment without Sentry dashboard/API access (same as staging, where the founder later confirmed directly). Temporary test file deleted immediately after. |

## LIGHT PRODUCTION POOLING CHECK

| Time (UTC) | Action | Result |
|---|---|---|
| 2026-10-04T06:5xZ | 10 requests at concurrency 10 against `fiqh-advisor-chat`, reusing 8 pre-created sessions (avoiding the Auth rate-limit confound discovered during staging validation) — deliberately moderate, not the full staging stress drill, per the prepared plan's own guidance against stress-testing live shared infrastructure | **10/10 success (100%)** |

## FINAL HEALTH CONFIRMATION

| Check | Result |
|---|---|
| `knowledge_items` count | 211 (not 254 — the 43 fail-closed atoms are structurally absent, never loaded) |
| Total public tables | 31 (25 pre-existing + 6 new KB tables) |
| Active snapshot | `eda4b96c7b2a77924a3dd86397cbcbba671440b3`, `is_current=true`, `211/43` |
| All 4 Edge Functions | `ACTIVE` |
| Project status | `ACTIVE_HEALTHY` |

**No rollback trigger was hit at any point.** No restore was needed; the backup/restore capability documented in `PRODUCTION_ROLLBACK_RUNBOOK.md` remains available and untouched. The 4 pre-deployment Edge Function body snapshots remain saved locally as a safety net, even though they were not needed.
