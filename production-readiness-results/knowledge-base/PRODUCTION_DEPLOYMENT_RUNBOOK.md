# Production Deployment Runbook — Niswah KB v1 + OpenAI + FD-1

**Status: NOT EXECUTED AGAINST PRODUCTION.** This runbook documents the
deployment procedure for review and future execution. Writing it does not
authorize running it. See
`PRODUCTION_DEPLOYMENT_READINESS_REPORT.md` for what has and has not been
validated, and `PRODUCTION_DEPLOYMENT_PREPARATION_REPORT.md` (2026-10-04)
for the real, live production inventory this update is based on.

**Updated 2026-10-04, with real production inventory — read this before
following the steps below.** This is **not a first-time deployment**:
production already has 26 real users and all 4 Edge Functions already
deployed and `ACTIVE` (versions 9–15), currently running on
`GEMINI_API_KEY`, not OpenAI. Of the 7 migrations this engagement calls
"active," **4 are already applied to production** (`ai_rate_limit`,
`wellbeing_logs_notes`, both `madhhab_authority_state` migrations —
confirmed directly against live schema, not assumed) — only the 3
KB-specific migrations are actually pending. The **canonical baseline
must never be applied to production** — it is a bare-DDL (no
`IF NOT EXISTS`) capture *of* production's own schema and would fail
immediately on every statement. See
`PRODUCTION_DEPLOYMENT_PREPARATION_REPORT.md` for the full delta and
`PRODUCTION_ROLLBACK_RUNBOOK.md` (new) for the rollback decision tree —
the ROLLBACK section below is superseded by that document, which
confirmed every mechanism it names actually exists (there is, notably,
**no platform "revert Edge Function to version N" button** — rollback
means redeploying prior source code).

---

## PRE-DEPLOY

### Required approvals
- `FD-5` (evidence-only production eligibility) — `FOUNDER_APPROVED_WITH_CONDITIONS`, 2026-09-29.
- `FD-6` (KB-only Fiqh retrieval, no live search) — `FOUNDER_APPROVED`, 2026-09-29.
- `FD-1` (canonical menstrual-state authority) — `FOUNDER_APPROVED`, implemented 2026-09-30 for the Haid/Tahara/Istihada axis.
- `FD-2` (TTC in V1 scope) and `FD-3` (Dream Interpreter KB positioning) remain `PENDING_FOUNDER_REVIEW` — both assessed as low-risk scope/positioning questions in `FOUNDER_DECISIONS.md`, not blocking this runbook, but the founder should be aware they are still open.
- Explicit founder authorization to deploy to production specifically — this runbook's existence is not that authorization.

### Expected branch/commit
- `release/niswah-kb-v1` at the commit recorded in `PRODUCTION_DEPLOYMENT_READINESS_REPORT.md` at the time of deploy (verify with `git log -1`, and re-confirm CI is green on that exact commit before proceeding).

### Expected evidence snapshot
- `EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json`: `frozen_at_commit_sha = eda4b96c7b2a77924a3dd86397cbcbba671440b3`.
- `PRODUCTION_DISPOSITION_MASTER.csv` SHA-256: `e6dd52c88f0986058156533754257652b43bca4a771ac42f82e5706049faafea`.
- Verify both with:
  ```
  shasum -a 256 production-readiness-results/knowledge-base/PRODUCTION_DISPOSITION_MASTER.csv
  python3 -c "import json; print(json.load(open('production-readiness-results/knowledge-base/EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json'))['production_disposition_master']['sha256'])"
  ```
  These two values must match exactly. If they do not, **stop** — the evidence snapshot has drifted and this runbook does not apply until that is resolved.

### Expected counts
- 254 total KB atoms; 211 `PRODUCTION_ELIGIBLE`; 43 `FAIL_CLOSED`.
- Verify: `python3 scripts/test_build_kb_production_candidates.py` (11 tests) and `python3 scripts/test_trust_boundary.py` (14 tests) both pass.

### Required secrets (set on the target Supabase project, never committed)

**Founder decisions, 2026-10-04 (resolved — see `PRODUCTION_DEPLOYMENT_PREPARATION_REPORT.md` Phase 8 for full detail):**
- `OPENAI_API_KEY` — a **dedicated production OpenAI project/key, never the staging key**. Must be delivered via the established secure `.env`-file handoff (never pasted in chat, never printed/logged/placed in argv by this agent — the same `Secret`-wrapped discipline already built for staging applies unchanged). **Not yet received** — this is the one open prerequisite blocking execution, not a decision.
- `OPENAI_MODEL` — the **same identifier already validated on staging**, no new choice.
- Spend controls — a conservative initial cap, set by the founder directly on the new production OpenAI project's own dashboard (not a Supabase-side configuration).
- `SUPABASE_DB_URL` — deploy-time only, never stored in the repo or in Edge Function secrets. Production's direct host is IPv6-only — use the Supavisor pooler, confirmed live at `aws-1-ap-southeast-1.pooler.supabase.com:6543`.
- `SUPABASE_URL` / `SUPABASE_ANON_KEY` — already platform-provided to Edge Functions.
- `GEMINI_API_KEY` — **founder decision: leave in place for now**, not removed as part of this deployment (harmless, unused post-cutover; cleanup deferred).
- Legacy anon/service_role API keys — **founder decision: explicitly keep enabled**, do not disable during this deployment (production has live users/older clients that may depend on them; retirement is a separate, later, deliberate migration). Use the new publishable/secret key types only for *newly*-deployed configuration where supported (the staging-validated app code and Edge Function `createClient()` calls already accept either transparently — no code change needed).
- `SENTRY_DSN` — **founder decision: reuse the existing Sentry project/DSN, no second project.** Production builds set `environment=production` (already supported, no code change). Alerting may be configured separately, later — not a deployment blocker.

### Backup requirements — VERIFIED, with real evidence (closed, not outstanding)
Per `production-readiness-results/backup-recovery/BR_recovery_runbook.md`
(2026-09-08 entry, the authoritative one — supersedes that workstream's
own earlier 2026-09-04 static-review NO-GO, which was conditioned
entirely on the backup configuration being then-unverified): daily
physical backups are confirmed running (`walg_enabled: true`,
`pitr_enabled: false`, re-verified live 2026-10-04 — 7 consecutive
`COMPLETED` backups), and a **real restore of real production data was
already executed and behaviorally validated** on 2026-09-08 (RTO ≈13
minutes). RPO is ~24h (daily backups, no PITR) — recommend one fresh
manual backup immediately before this deployment as cheap additional
insurance, not because the existing posture is unverified.

### Health checks before starting
- Confirm the target database is reachable and no other migration is mid-flight.
- Review the diff of the three new migration files one more time immediately before applying:
  `supabase/migrations/20260929114500_knowledge_base_v1.sql`,
  `supabase/migrations/20260929120000_knowledge_base_v1_qualification_and_snapshot.sql`,
  `supabase/migrations/20260930130000_retrieve_knowledge_v1_relevance_anchor.sql`.
  All three are additive (new tables/columns/functions/indexes, or
  `CREATE OR REPLACE FUNCTION` with an unchanged signature) — no
  `DROP TABLE`/`DROP COLUMN` against any existing production object was
  found in review.
- Confirm `scripts/verify_kb_retrieval_live.sql` passes on the target
  commit before applying anything (see **Resolved blocker** below) —
  it is expected to pass now, but re-verify on the actual target
  environment rather than assuming this local-environment result
  transfers unchanged.

### Resolved blocker (was: must be resolved before this runbook could be executed end-to-end)
`scripts/verify_kb_retrieval_live.sql`'s final assertion ("a low-relevance
Fiqh query returns 0 rows," using the example *"electric car shopping list
and tire pressure"*) previously failed against real data. The Retrieval
Precision Remediation Pass fixed this for real (a two-tier relevance gate,
not a threshold change — see `RETRIEVAL_PRECISION_REMEDIATION_REPORT.md`):
the gate is now re-confirmed passing. This required one additional
migration beyond the two listed above:
`supabase/migrations/20260930130000_retrieve_knowledge_v1_relevance_anchor.sql`
(the RPC-layer half of the two-tier gate) — include it in the migration
review step above; it is additive only (`CREATE OR REPLACE FUNCTION`,
same signature), verified reproducible from a clean database by CI's
"Validate DB migration reproducibility (BR-002)" job.

---

## GO / NO-GO CHECKPOINT — immediately before the first production mutation

**Everything above this line (PRE-DEPLOY, backup confirmation, migration
review) is read-only or preparatory. Everything in DEPLOY step 4 onward
mutates the real production database.** This checklist sits at that
exact boundary. All items must be true, verified at execution time (not
assumed from an earlier session), before running DEPLOY step 4.

- [ ] **Explicit, separate founder production-deployment authorization has been given** — this runbook's existence, and even a founder's prior resolution of the secret/config decisions, is not that authorization. `PRODUCTION DEPLOYMENT AUTHORIZED` must be `YES` from the founder, for this specific execution, immediately before proceeding.
- [ ] Production identity re-confirmed *right now*, not from memory: `ref = jkmjobvxfrmuwafczvtw`, `name = Niswah`, `status = ACTIVE_HEALTHY`.
- [ ] A fresh manual backup has been taken immediately before this run (cheap, few minutes, tightens the ~24h RPO gap for this specific change window) — or the most recent daily backup's timestamp has been checked and explicitly accepted as sufficient.
- [ ] The production `OPENAI_API_KEY` (dedicated, founder-provided, never staging's) has been received via the secure `.env`-file handoff and verified present (boolean presence check only — never printed) — the deployment must not begin with this secret still missing, since the new Edge Function code has no Gemini fallback.
- [ ] The 4 currently-live Edge Function bundles have been snapshotted via `GET /functions/{slug}/body` for all four functions (the rollback safety net) — **before** DEPLOY step 10 overwrites them, and in practice simplest to do in this same checkpoint, before step 4, so it's never forgotten under deployment pressure.
- [ ] The exact 3 migration files to be applied are byte-identical to the ones already proven on staging (`diff`/checksum against the commit staging was validated at) — no drift since staging validation.
- [ ] CI is green on the exact commit being deployed from (not an older or newer one).
- [ ] Re-confirmed, this session, that production's schema still matches this report's inventory (migrations #1–#4 present, KB tables absent, `pg_trgm` absent) — if anything has changed since this report was written, stop and re-assess before proceeding; do not assume the inventory is still accurate indefinitely.
- [ ] No step in this runbook will print, log, or pass as a CLI argument the new `OPENAI_API_KEY`, the production DB password/connection string, the Management API PAT, or any Supabase secret/service-role key — confirmed by re-reading the exact commands about to be run, not assumed from having followed this discipline before.

**If every box above is checked: proceed to DEPLOY step 4. If any box is unchecked or uncertain: stop. Do not proceed on a partial checklist.**

---

## DEPLOY

Real, already-existing pipeline (`scripts/deploy_kb_v1.sh`'s steps,
exactly as executed for real against staging) — do not invent a new
procedure. **Updated 2026-10-04**: do not use `supabase db push` or
trust `supabase migration list`'s idea of "pending" for production —
its tracking table is empty for this project (migrations #1–#4 were
applied by direct means, never through it) and it would wrongly try to
replay all 7 migrations. Apply **only** the 3 KB migrations, directly,
in order, the same way they were applied to staging:

1. `python3 scripts/verify_kb_review_packets.py` — validates research/review packets.
2. `python3 scripts/build_kb_production_candidates.py` — materializes exactly 211 eligible candidates + 43 quarantined rows from `PRODUCTION_DISPOSITION_MASTER.csv`.
3. `python3 scripts/render_kb_seed_sql.py` — renders deterministic seed SQL to `production-readiness-results/knowledge-base/generated/PRODUCTION_KB_SEED.sql` and `FIQH_QUARANTINE.csv`.
4. Apply, directly and in order, only:
   `supabase/migrations/20260929114500_knowledge_base_v1.sql`,
   `supabase/migrations/20260929120000_knowledge_base_v1_qualification_and_snapshot.sql`,
   `supabase/migrations/20260930130000_retrieve_knowledge_v1_relevance_anchor.sql`
   — via `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <file>` against the pooler connection string, one at a time. **Do not apply the canonical baseline** — it is a bare-DDL capture of production's own existing schema and will error immediately (every table already exists). **Do not apply migrations #1–#4** — confirmed already live on production (see the 2026-10-04 inventory note above); re-running them would be a safe no-op since they're idempotently guarded, but there is nothing to gain by including them.
5. `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f production-readiness-results/knowledge-base/generated/PRODUCTION_KB_SEED.sql` — seeds only evidence-eligible rows. Quarantined rows are never loaded into authoritative retrieval tables.
6. `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f scripts/verify_kb_live.sql` — hard gate: 211 total = 74 Health/Safety + 137 Fiqh; no Fiqh row without an explicit Madhhab; no production-eligible version attached to a non-published item; no production-eligible version missing source metadata.
7. `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f scripts/verify_kb_retrieval_live.sql` — hard gate: Madhhab filtering, Arabic routing, cross-Madhhab leak check, Health routing, low-relevance fail-closed check.
8. Set secrets on the target project **before** deploying new function code (so the new code never runs even briefly without them): `OPENAI_API_KEY`, `OPENAI_MODEL` — via a minimal, dedicated secrets file (never the whole `.env`, never `GEMINI_API_KEY`/`SUPABASE_ACCESS_TOKEN` alongside them), matching the exact pattern already used for staging.
9. **Before** deploying, save each of the 4 currently-live function bundles via `GET /v1/projects/{ref}/functions/{slug}/body` (see `PRODUCTION_ROLLBACK_RUNBOOK.md`) — a real rollback safety net, confirmed available, independent of git history.
10. Deploy Edge Functions **(this replaces live, `ACTIVE`, versions-9-to-15 code currently capable of serving 26 real users — not a first-time deploy)**: `npx supabase functions deploy <name> --project-ref jkmjobvxfrmuwafczvtw --use-api` for each of `dr-niswah-chat`, `fiqh-advisor-chat`, `ai-assistant-chat`, `dream-interpreter-chat`.

Snapshot activation is automatic: step 5's seed SQL registers the active
row in `kb_snapshot_registry` (`is_current = true`); `assertSnapshotHealth()`
in `kb_retrieval.ts` enforces this at request time on every call, failing
closed if no current/healthy snapshot is registered.

---

## POST-DEPLOY

1. Re-run `scripts/verify_kb_live.sql` and `scripts/verify_kb_retrieval_live.sql` standalone (independent of the deploy script) as a second, separate confirmation.
2. SQL count checks:
   ```sql
   select count(*) from public.knowledge_items ki where ki.publication_state='PUBLISHED'
     and exists (select 1 from public.knowledge_item_versions kiv where kiv.knowledge_item_id=ki.id and kiv.production_eligible=true);
   -- expect 211
   select commit_sha, total_atoms, production_eligible_count, fail_closed_count, is_current
     from public.kb_snapshot_registry where is_current = true;
   -- expect eda4b96c7b2a77924a3dd86397cbcbba671440b3 | 254 | 211 | 43 | t
   ```
3. Representative Fiqh smoke tests: reuse `OPENAI_ACCEPTANCE_RESULTS.csv` (F01–F16) and `FD1_STATE_ACCEPTANCE_RESULTS.csv` (SD01–SD09) as the canonical smoke-test script — same questions, against the real deployed endpoint instead of local.
4. Representative Health smoke tests: reuse `OPENAI_ACCEPTANCE_RESULTS.csv` (H01–H16), specifically confirming H02–H05 (qualification preserved) and H09/H13 (fail-closed).
5. Citation check: confirm citations in the smoke-test responses carry real `knowledgeKey`/`sourceKey`/`locator`/`url` fields, never invented.
6. Qualification check: confirm H02–H05's qualifying language is present in the live responses.
7. No-evidence check: confirm an out-of-KB question (e.g. F06's trade-contract question) declines rather than answering from general knowledge.
8. Fail-closed check: confirm F07 (targets `HNF-HAID-09`, `FAIL_CLOSED`) and F08–F10 (the 3 joint pregnancy-loss/nifas atoms) all decline and defer to a qualified scholar.
9. OpenAI connectivity check: one real minimal call; confirm the model identifier in the sanitized log matches `OPENAI_MODEL`.
10. Urgent Health check: confirm an H11-equivalent case (severe bleeding + dizziness + shortness of breath) returns `urgent: true` with the urgent banner text.
11. FD-1 check: confirm SD01 (state-dependent, no state) fails closed, and SD06/SD07 (model asked to override a supplied state) refuses.

---

## ROLLBACK — superseded, see `PRODUCTION_ROLLBACK_RUNBOOK.md`

The summary below is kept for history; the dedicated rollback runbook
(written 2026-10-04, during the Production Deployment Preparation
workstream) has the full decision tree and confirmed every mechanism it
names actually exists via the Management API — use that document when
executing.

- **Edge Functions**: stateless — rollback is redeploying the prior
  version's code. **Correction**: there is no platform "revert to
  version N" mechanism (confirmed by checking the Management API
  directly) — rollback is always a fresh deploy of the prior source,
  and this specific deployment replaces *already-live* code (versions
  9–15, currently serving Gemini), not a first deployment. Save each
  function's current live bundle via `GET /functions/{slug}/body`
  before deploying, as a safety net independent of git history.
- **Database**: the three KB migrations are additive only — no
  existing production table, column, or row is altered or dropped.
- **Snapshot**: unchanged from below — re-registering the prior/correct
  current row, or deactivating KB-backed retrieval entirely, remains
  the right lever.
- **Backup/restore, now a confirmed real mechanism, not a gap**: per
  `PRODUCTION_DEPLOYMENT_PREPARATION_REPORT.md` Phase 4, a real restore
  of real production data was already demonstrated (2026-09-08,
  ~13 minute RTO) — this is the last-resort mechanism if everything
  above is insufficient, not the first response.
- **Criteria that trigger rollback**: unchanged — `verify_kb_live.sql`/
  `verify_kb_retrieval_live.sql` failing post-deploy; any post-deploy
  smoke test showing fail-closed bypass, Madhhab leakage, or
  qualification loss; the OpenAI connectivity check failing after
  reasonable retry; the urgent Health check failing.

---

*This runbook was written, not executed. No migration was applied to
production, no KB snapshot was activated in production, no Edge Function
was deployed to production, and no production secret was changed in the
process of writing it.*
