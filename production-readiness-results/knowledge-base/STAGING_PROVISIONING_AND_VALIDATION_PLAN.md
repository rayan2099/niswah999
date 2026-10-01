# Staging Provisioning and Validation Plan — Niswah

**Date**: 2026-10-01. No staging environment exists today — this plan
specifies exactly what is needed before one can, and exactly what can be
provisioned/validated by an agent versus what requires founder action.
Nothing in this document authorizes creating paid infrastructure; it is
the specification to get that explicit approval against.

---

## Minimum required staging environment

### Supabase

| Requirement | Detail |
|---|---|
| Separate non-production project | A distinct Supabase project (own project ref, own URL), never the production project reused with a different schema. |
| Postgres version | Match production exactly (currently `17.6` locally; confirm the real production project's version before provisioning — do not assume). |
| Extensions | `pg_trgm` (retrieval scoring), plus whatever `canonical_baseline`'s own `CREATE EXTENSION`/schema setup requires — verified by applying the same baseline+migrations sequence this pass's CI job now proves reproducible. |
| RLS | Same policies as production — comes for free from applying the same baseline + migrations; no staging-specific RLS divergence. |
| RPCs | Same functions as production (`retrieve_knowledge_v1`, `get_active_kb_snapshot`, `check_and_increment_ai_rate_limit`, etc.) — same source, applied via the same migration path. |
| Edge Functions | All 4 AI-backed functions (`dr-niswah-chat`, `fiqh-advisor-chat`, `ai-assistant-chat`, `dream-interpreter-chat`) deployed from the same code, to the staging project specifically. |
| Connection pooling / Supavisor | Enabled — this is one of the two things (with staging itself) this whole workstream has never been able to validate locally. Must be genuinely on, not left disabled as local dev has it. |
| Separate secrets | `OPENAI_API_KEY`/`OPENAI_MODEL` set on the staging project specifically, never copied from production. |
| Separate service-role credentials | Staging's own, never production's. |
| Isolated database | No shared data path with production, ever. |

### OpenAI

| Requirement | Detail |
|---|---|
| Staging key | Either a genuinely separate OpenAI API key/project, or an explicitly founder-approved shared key with a documented spending cap — founder's call, not assumed. |
| `OPENAI_MODEL` | Same model identifier intended for production, so acceptance results transfer. |
| Spending/rate limits | Set wherever OpenAI's dashboard allows a project-level cap, specifically to bound an unattended staging environment's cost exposure. |
| No production health records | All staging testing uses synthetic accounts and synthetic questions only — same discipline already used throughout every local pass in this workstream, carried forward, never real user data. |

### App

| Requirement | Detail |
|---|---|
| Staging backend URL | The staging Supabase project's own URL — never production's. |
| Staging anon/public key | The staging project's own anon key. |
| `APP_ENV=staging` | The app already supports this exact mechanism today (`lib/core/config/app_environment.dart`: `--dart-define=APP_ENV=...` or `.env`'s `APP_ENV`, with `AppEnvironment.isProduction` gating Sentry's `options.environment` and anything else that checks it) — no new code needed, just a staging-specific build configuration. |
| No accidental cross-pointing | A staging build must be structurally incapable of silently using the production URL/key — achieved by keeping staging's `.env`/dart-defines entirely separate from production's and never committing either to the repo (consistent with the existing `.env.example`-only convention already enforced throughout this workstream). |

### Observability

| Requirement | Detail |
|---|---|
| Staging Sentry environment | Either a separate Sentry project, or the same project with `environment=staging` tagging (the code already supports environment tagging — see Phase 8/9 below) — founder's call on Sentry plan/organization structure. |
| Sanitized logs | Already true today for the AI/KB path (§ below) — carries over unchanged to staging, no new work. |
| Edge Function errors / OpenAI failures / 429s / retry exhaustion / DB-RPC failures / snapshot mismatches / no-evidence/fail-closed events | All already logged via existing `console.error`/`console.log` call sites (`openai_client.ts`, `kb_retrieval.ts`, `rate_limit.ts`, each Edge Function's own catch blocks) — visible via `supabase functions logs` on the staging project once deployed, no new code required. |
| Latency / token / cost observability | Already captured per-request (`callOpenAI`'s `usage` field, logged) — aggregating it into a dashboard is a follow-up, not a staging-provisioning blocker. |

---

## What this report can execute itself vs. what needs the founder

| Step | Who |
|---|---|
| Write/maintain the staging build configuration (`APP_ENV=staging`, separate `.env.example` entries) | **Agent** — no external access needed. |
| Deploy Edge Functions to a staging project once one exists | **Agent** — standard `supabase functions deploy`, same as the existing runbook. |
| Apply baseline + migrations + KB seed to a staging database once it exists | **Agent** — the exact, now CI-proven `scripts/deploy_kb_v1.sh`/`scripts/bootstrap_local_dev.sh` sequence, pointed at the staging `SUPABASE_DB_URL`. |
| Run the staging acceptance matrix (below) once the environment exists | **Agent** — real HTTP calls, synthetic data, same pattern as every real-model test already run in this workstream. |
| Create the Supabase staging project itself | **Founder** — requires account-level/billing action this agent cannot and should not take unilaterally. |
| Provide staging project credentials (`SUPABASE_DB_URL`, service-role key, anon key) | **Founder** — securely, the same way `OPENAI_API_KEY` was supplied earlier in this workstream (never pasted into a tracked file). |
| Create/approve a staging OpenAI key or spending cap | **Founder**. |
| Create/approve a staging Sentry project or environment tag policy | **Founder**. |
| Approve ongoing staging cost | **Founder** — see cost estimate below. |

## Approximate cost / billing consideration

Rough, non-binding estimate, founder to confirm against actual current
pricing before approving:
- Supabase: a second project on a paid tier (if the account is already on
  a paid plan) or free-tier limits (if acceptable for staging's expected
  low, intermittent traffic) — founder's plan/org structure determines
  this, not estimated further here.
- OpenAI: staging acceptance runs are low-volume, synthetic-only
  (comparable to the ~32–75 case real-model runs already done this
  workstream, each a few cents at most) — a capped staging key with a
  modest monthly limit (e.g. low tens of dollars) should comfortably
  cover ongoing validation without real financial exposure, but the exact
  cap is the founder's call.
- Sentry: typically free at low event volumes; founder to confirm current
  plan.

---

## Connection-pooling test plan (Phase 10)

Cannot be executed until a pooled staging project exists — local direct-DB
connections are explicitly **not** treated as equivalent (this workstream
already confirmed local pooling is disabled and never validated it).

**Test design, to run once staging exists:**
- **Request volume**: 100 requests total (5× the local moderate-load test
  already run, to actually exercise pool reuse/contention rather than stay
  within a single pool's idle capacity).
- **Concurrency**: 10, 20, then 40 (three stepped runs, not one single
  level) — specifically to find where pooled behavior starts to degrade,
  not just confirm it works at one arbitrary level.
- **Coverage**: both `fiqh-advisor-chat` and `dr-niswah-chat`, synthetic
  users only (fresh signup per request, as already established).
- **Pass criteria**: success rate ≥ 99% at concurrency 10 and 20; p95
  latency does not grow by more than ~2× between concurrency 10 and 40
  (a soft, documented expectation, not a hard architectural guarantee);
  zero connection-exhaustion errors at concurrency 10/20; any
  connection-exhaustion at concurrency 40 is recorded as a finding, not
  silently accepted or treated as a failure of the test itself.
- **Metrics required**: p50/p95 latency per concurrency level; error rate
  per concurrency level; Supabase's own pooler metrics if exposed
  (active/idle connections, wait time) — pulled from the Supabase
  dashboard for the staging project, not inferred.
- **Recovery check**: after the 40-concurrency run, confirm a single
  ordinary request still succeeds promptly (pool recovers, no lingering
  exhaustion) and that `assertSnapshotHealth()` (the existing snapshot
  check) still passes correctly under this load, not just ordinary
  requests.
- **Explicitly not performed**: deliberate destructive stress testing
  (e.g. intentionally exhausting the pool past recovery, or sustained
  high-concurrency hammering) — moderate load only, per instruction.

---

## Staging acceptance matrix (Phase 11)

Reuses the exact case patterns already built and real-model-verified
earlier in this workstream (`OPENAI_ACCEPTANCE_RESULTS.csv`,
`FD1_STATE_ACCEPTANCE_RESULTS.csv`, the Nifas governance cases, the
retrieval-precision adversarial set) — rerun against the real staging
endpoint instead of local, not reinvented:

**Fiqh** — one ordinary supported question per Madhhab (Hanafi, Maliki,
Shafi'i, Hanbali); the cross-Madhhab leakage attempt (F11-equivalent); a
fail-closed case (F07-equivalent, `HNF-HAID-09`); the Nifas state-
dependent fail-closed case (N01/N02-equivalent); a no-evidence case
(F06-equivalent); a canonical-state-mismatch adversarial case
(SD06/SD07-equivalent — model told a resolved state, then asked to
override it).

**Health** — an ordinary verified case (H01-equivalent); all four
`VERIFIED_WITH_QUALIFICATION` rows (H02–H05-equivalent); an unsupported
question (H09-equivalent); a gibberish/unrelated query (X01/Y01-style —
confirming the relevance gate is active in the deployed environment, not
just locally); the urgent/red-flag path (H11-equivalent, confirming
`urgent: true` and the banner fire correctly); a provider-failure
simulation if feasible (e.g. a deliberately invalid model name in a
throwaway test call, confirming safe/classified failure, never run
against the real configured `OPENAI_MODEL`).

**System** — snapshot mismatch (register a wrong commit temporarily in a
disposable way, or confirm the check via code review if too risky to
simulate live on staging); an OpenAI failure and a real 429 (if
organically triggered by test volume, as happened safely in this
workstream's own local passes — not deliberately forced against a shared
quota); a DB/RPC failure path (e.g. temporarily revoking a grant in a
reversible way, matching the pattern already used in an earlier pass's
REVOKE/GRANT fail-closed test); pooling behavior (the test plan above);
citations (confirm every citation in every response above is real,
canonical, matches `citationPayload()`'s shape); token/latency telemetry
(confirm `callOpenAI`'s usage logging appears in the staging project's
function logs); a Sentry event generated from a synthetic, clearly-
non-sensitive test error (e.g. a deliberately-thrown test exception in a
disposable code path, never a real user error) to confirm the DSN is
genuinely wired end-to-end once provisioned.

All cases use synthetic data only — no real user health records, ever,
matching this workstream's standing discipline.

---

## Summary table

| Category | Item |
|---|---|
| **ALREADY COMPLETE** | App-side `APP_ENV` mechanism; all Edge Function error logging; Sentry code integration (init, 4 error-path hooks, scrubbing, opaque record IDs); deploy/seed scripts; relevance gate; FD-1 state guard; CI-proven baseline+migration reproducibility. |
| **REQUIRES CODE** | Nothing identified as a hard blocker — staging work is provisioning + config + running already-built tooling against a new target, not new application code. |
| **REQUIRES EXTERNAL INFRASTRUCTURE** | A real Supabase staging project (with pooling enabled); a staging/capped OpenAI key; a Sentry project or environment tag. |
| **REQUIRES FOUNDER ACTION** | Creating the Supabase project; providing its credentials securely; creating/approving the OpenAI staging key and its spending cap; creating/approving the Sentry staging setup. |
| **REQUIRES SECRET** | `SUPABASE_DB_URL` (staging), service-role key (staging), `OPENAI_API_KEY`/`OPENAI_MODEL` (staging), `SENTRY_DSN` (staging). None fabricated or guessed here. |
| **COST/BILLING** | See estimate above — founder to confirm against current pricing before approving. |
| **VALIDATION TO RUN AFTER PROVISIONING** | The connection-pooling test plan and the staging acceptance matrix above, both already fully specified and ready to execute the moment credentials are supplied. |

---

## Founder action required

1. Create a Supabase staging project (separate from production).
2. Provide its credentials securely (`SUPABASE_DB_URL`, service-role key,
   anon key) — the same secure-supply pattern already used for
   `OPENAI_API_KEY` earlier in this workstream, never pasted into a
   tracked file.
3. Create or approve a staging OpenAI key/spending cap (or confirm an
   existing key may be reused with an explicit cap).
4. Create or approve a staging Sentry project/DSN (or confirm environment
   tagging on the existing project is acceptable instead of a separate
   project).
5. Confirm the approximate cost estimate above is acceptable, or set a
   different cap.

Once these are supplied, the connection-pooling test plan and the
staging acceptance matrix above are ready to execute immediately — no
further planning work is needed on this agent's side first.
