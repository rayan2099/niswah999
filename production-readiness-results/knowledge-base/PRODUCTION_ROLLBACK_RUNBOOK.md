# Production Rollback Runbook — Niswah KB v1 + OpenAI Edge Function Upgrade

**Status: NOT EXECUTED.** Written during the read-only Production
Deployment Preparation workstream (2026-10-04). Every mechanism named
below was independently confirmed to actually exist (via the Management
API or this engagement's own prior, dated, real evidence) before being
written down here — nothing here is a theoretical rollback statement.

This runbook assumes `PRODUCTION_DEPLOYMENT_RUNBOOK.md`'s DEPLOY
sequence was followed. It covers failure **during or after** that
sequence.

---

## Decision tree

### 1. Migration (#5/#6/#7) fails partway through

All three are additive-only (`CREATE TABLE`/`INDEX`/`FUNCTION`/`EXTENSION`
— no `ALTER` or `DROP` against any pre-existing table). A failure here
can only leave a **partially-created new object**, never a damaged
existing one.

- **Rollback**: `DROP` whichever new KB object(s) got created before the
  failure (safe — nothing pre-existing references them yet), fix the
  root cause, re-run from the start of the migration stage.
- **DB restore required?** No.
- **Order**: stop immediately on the first error (`psql -v ON_ERROR_STOP=1`,
  the same flag used throughout this engagement's staging work) — do
  not continue past a failed statement.

### 2. KB seed load fails partway through

- **Rollback**: `DELETE FROM knowledge_items;` (cascades to the
  dependent, equally-net-new `knowledge_item_versions`/
  `knowledge_item_sources`/`knowledge_citations` rows via FK, if
  cascade is configured — verify the FK `ON DELETE` behavior before
  relying on cascade; otherwise delete each table explicitly, child
  tables first). `render_kb_seed_sql.py`'s output is deterministic, so
  re-running from a clean KB-table state reproduces the identical seed.
- **DB restore required?** No — nothing outside the net-new KB tables
  is touched by this stage.

### 3. Snapshot activation is wrong (wrong commit active, or none active)

- **Rollback**: `UPDATE kb_snapshot_registry SET is_current = false
  WHERE is_current = true;` then re-register the correct row as
  current (or leave none current). The system's own
  `assertSnapshotHealth()` already fails closed with no eligible
  evidence in either wrong-state case — this was directly verified,
  twice, as a reversible test on staging (register a fake commit as
  current, confirm fail-closed, restore the real one, confirm
  recovery).
- **DB restore required?** No.

### 4. Edge Function deployment fails or regresses behavior

**No platform "revert to version N" mechanism exists** — confirmed by
checking the Management API directly: `/functions/{slug}` supports
`GET`/`PATCH`/`DELETE` only, no version history or restore endpoint.
Rollback is **always** a fresh deploy of the prior source, never a
one-click revert.

- **Rollback**: re-run `npx supabase functions deploy <name>
  --project-ref jkmjobvxfrmuwafczvtw --use-api` against the prior
  (currently-live, Gemini-based) source.
- **Before deploying the new code**, as a safety net independent of
  git history: `GET /v1/projects/{ref}/functions/{slug}/body` retrieves
  the exact binary bundle currently live for each of the 4 functions
  (confirmed to return a real artifact, not a 404, during this
  workstream). Save all 4 before the first new deploy, in case what's
  actually live has ever drifted from what git believes is deployed
  (plausible given the version numbers observed — 9 to 15 — imply a
  deployment history not fully reflected in this repository's own
  commit log).
- **DB restore required?** No — functions are stateless; this is a
  pure code rollback.
- **Can previous function versions be restored?** Only by re-deploying
  their source, not by any "restore version 9" action. State this
  precisely to whoever executes this runbook — it is easy to assume a
  version-pin exists when it does not.

### 5. OpenAI configuration failure (missing/invalid key, wrong model)

- **Rollback**: not really a rollback — fix or remove the secret via
  `supabase secrets set`/unset. The deployed functions already degrade
  safely without a working OpenAI key (confirmed on staging: urgent
  banner still fires alone, ordinary paths return a static safe
  fallback string, Fiqh returns a clean `502` — never a fabricated
  answer). No user-facing emergency exists while this is being fixed.
- **DB restore required?** No.

### 6. Retrieval (KB) misbehavior discovered post-deploy

- Already fails closed by construction (Madhhab filtering, relevance
  gate, snapshot-health check) — "rollback" here means **deactivating
  the snapshot** (scenario 3 above) to force every KB-dependent
  response into the already-safe no-evidence path while the real cause
  is fixed, not a data rollback.
- **DB restore required?** No.

### 7. Pooling issue under production load

- Not expected (staging validated concurrency 10/20/40 cleanly), and
  production's own pooler was confirmed already configured and live
  (Phase 1 of the preparation report) independent of this deployment.
- If it occurs: this is a platform-configuration question, not a data
  rollback — there is nothing in this deployment's own changes that
  touches pooling configuration.
- **DB restore required?** No.

### 8. Sentry / observability issue

- No data-plane impact. Fix the DSN/environment tag in the client build
  config and ship a corrected build — nothing server-side to roll back.
- **DB restore required?** No.

### 9. Post-deploy acceptance test fails (any case in the production matrix)

**This is the trigger condition for stopping forward progress.**
Specifically:
- Any Madhhab-isolation or cross-leakage case failing → stop, deactivate
  the KB snapshot (scenario 3), do not let Edge Functions serve
  KB-backed answers until root-caused.
- Any qualification or citation-fidelity case failing → same.
- Any fail-closed case failing to fail closed → same, and treat as the
  most urgent of all the above (a bypassed fail-closed gate is the
  single most safety-critical regression this system has guarded
  against throughout every phase of this engagement).
- Urgent Health path failing → stop and roll back Edge Functions to
  prior source (scenario 4) immediately; this is the one user-facing
  safety path with zero acceptable downtime.
- OpenAI/pooling/Sentry cases failing → handled per their own scenarios
  above; not independently blocking unless they also cause a
  fail-closed or Madhhab regression.

### 10. Catastrophic / unexpected production data damage

Only if every lighter-weight option above is insufficient:

- **Mechanism, confirmed real and already demonstrated once**: restore
  a daily physical backup via the Supabase Dashboard's "restore to new
  project" action (exactly what was used in the 2026-09-08 drill), or
  `POST /v1/projects/{ref}/database/backups/restore` with the target
  backup's `id` (confirmed present in the current API spec).
- **RTO**: ~13 minutes to a fully restored, behaviorally-verified state
  (measured, real data, 2026-09-08). **RPO**: up to ~24 hours (daily
  backups, no PITR) — the real, accepted limitation; a fresh manual
  backup immediately before this deployment (recommended in the deploy
  runbook) tightens this for this specific change window.
- **This is the last resort**, not the first response, because
  everything in scenarios 1–9 is cheaper, faster, and bounded to the
  net-new objects this deployment itself introduces.

---

## Summary: what is and isn't reversible

| Component | Reversible without DB restore? |
|---|---|
| KB migrations (#5/#6/#7) | Yes — additive only |
| KB seed data | Yes — delete + deterministic re-seed |
| Snapshot activation | Yes — re-register / deactivate |
| Edge Function code | Yes, but only by re-deploying prior source — no version-revert button exists |
| Secrets | Yes — set/unset at any time |
| Pre-existing production data (users, cycle_entries, etc.) | **Not touched by this deployment at all** — nothing in scenarios 1–9 ever writes to a pre-existing table |

No scenario in this deployment's own scope requires a full database
restore under normal failure modes — that mechanism exists, is proven,
and is documented here as the genuine last resort it actually is, not
as a first-line response to routine deployment issues.
