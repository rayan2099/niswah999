# Production Deployment Runbook — Niswah KB v1 + OpenAI + FD-1

**Status: NOT EXECUTED AGAINST PRODUCTION.** This runbook documents the
deployment procedure for review and future execution. Writing it does not
authorize running it. See
`PRODUCTION_DEPLOYMENT_READINESS_REPORT.md` for what has and has not been
validated, and for the explicit gates that must be satisfied first.

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
- `OPENAI_API_KEY` — required, no hardcoded fallback (`callOpenAI()` throws a config error if unset).
- `OPENAI_MODEL` — required, no hardcoded fallback. Verify the configured model is actually available to this API project before relying on it (Phase 9 of the OpenAI migration pass; do not assume from documentation).
- `SUPABASE_DB_URL` — deploy-time only, a Postgres connection string with migration/write rights, never stored in the repo or in Edge Function secrets.
- `SUPABASE_URL` / `SUPABASE_ANON_KEY` — already platform-provided to Edge Functions.

### Backup requirements
Per the existing, separate backup/recovery workstream
(`production-readiness-results/backup-recovery/BR_recovery_runbook.md`): a
verified, recent, restorable production backup must exist before applying
any migration to production. This runbook does not create that backup —
confirm it separately first.

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

## DEPLOY

Real, already-existing pipeline (`scripts/deploy_kb_v1.sh`) — do not
invent a new procedure; use this one:

1. `python3 scripts/verify_kb_review_packets.py` — validates research/review packets.
2. `python3 scripts/build_kb_production_candidates.py` — materializes exactly 211 eligible candidates + 43 quarantined rows from `PRODUCTION_DISPOSITION_MASTER.csv`.
3. `python3 scripts/render_kb_seed_sql.py` — renders deterministic seed SQL to `production-readiness-results/knowledge-base/generated/PRODUCTION_KB_SEED.sql` and `FIQH_QUARANTINE.csv`.
4. `supabase db push --db-url "$SUPABASE_DB_URL"` — applies all pending migrations through the canonical migration path.
5. `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f production-readiness-results/knowledge-base/generated/PRODUCTION_KB_SEED.sql` — seeds only evidence-eligible rows. Quarantined rows are never loaded into authoritative retrieval tables.
6. `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f scripts/verify_kb_live.sql` — hard gate: 211 total = 74 Health/Safety + 137 Fiqh; no Fiqh row without an explicit Madhhab; no production-eligible version attached to a non-published item; no production-eligible version missing source metadata.
7. `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f scripts/verify_kb_retrieval_live.sql` — hard gate: Madhhab filtering, Arabic routing, cross-Madhhab leak check, Health routing, low-relevance fail-closed check (now passes — see Resolved blocker above).
8. Deploy Edge Functions: `supabase functions deploy dr-niswah-chat`, `fiqh-advisor-chat`, `ai-assistant-chat`, `dream-interpreter-chat` (or all via the CLI's bulk deploy).
9. Set secrets on the target project: `supabase secrets set OPENAI_API_KEY=<key> OPENAI_MODEL=<model> --project-ref <ref>`.

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

## ROLLBACK

- **Edge Functions**: stateless — rollback is redeploying the prior version's code (`supabase functions deploy <name>` from the prior git tag/commit). No data implications.
- **Database**: the two new migrations are additive only (new tables/columns/functions/indexes) — no existing production table, column, or row is altered or dropped. A rollback would mean writing a new down-migration that drops only the new objects, never `supabase db reset` (which would affect unrelated production data). No down-migration has been written this pass (out of scope unless requested).
- **Snapshot**: `kb_snapshot_registry` supports registering a different row as current; rolling back means re-registering the prior current snapshot, or deactivating KB-backed retrieval entirely — the Edge Functions already fail closed on no active/healthy snapshot, which is itself a safe "disable" lever without a code rollback.
- **Criteria that trigger rollback**: `verify_kb_live.sql` or `verify_kb_retrieval_live.sql` failing post-deploy; any post-deploy smoke test showing fail-closed bypass, Madhhab leakage, or qualification loss; the OpenAI connectivity check failing after reasonable retry; the urgent Health check failing.

---

*This runbook was written, not executed. No migration was applied to
production, no KB snapshot was activated in production, no Edge Function
was deployed to production, and no production secret was changed in the
process of writing it.*
