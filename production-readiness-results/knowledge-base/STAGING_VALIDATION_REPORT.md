# Staging Validation Report — Niswah Staging

**Date**: 2026-10-03. Covers the live provisioning of the Niswah Staging
Supabase project and the closure pass across all ten validation phases
(qualified-health acceptance, provider-failure, snapshot-failure,
DB/RPC-failure, citation-shape, Sentry, observability, secret-handling
recheck, restore/health check). Production (`jkmjobvxfrmuwafczvtw`) was
never touched at any point — every apply/deploy/failure-injection step
re-verified the target project identity first.

---

## Staging project identity

| Field | Value |
|---|---|
| Project name | Niswah Staging |
| Project ref | `ovgvevzrcefloitgcsia` |
| Organization | `aoimfdtlagrbqwrkvkgl` (same org as production, separate project) |
| Region | `ap-southeast-1` (matches production) |
| Postgres | engine 17, version `17.11.0.002` |
| Compute | Micro (`ci_micro`), ~$10/month — matches the approved budget exactly; zero other add-ons |
| Status | `ACTIVE_HEALTHY` |

## Migration result

Canonical baseline (`supabase/canonical_baseline/00_public_baseline_draft.sql`)
applied to a genuinely empty database, followed by all 7 active migrations
in filename/timestamp order. `scripts/verify_schema_contract.sql`: **zero
FAIL rows** (29 object checks, 4 column-property checks, 4 constraint
checks, 3 constraint-logic checks, 2 function-body checks, 10 KB
object checks, 1 live RPC-callability smoke test — all OK).

## KB snapshot result

211 production candidates generated from the frozen disposition master
(snapshot commit `eda4b96c7b2a77924a3dd86397cbcbba671440b3`) and loaded.
`scripts/verify_kb_live.sql`: **PASS** — "211 active items = 74
Health/Safety + 137 Fiqh; publication/source gates clean."
`scripts/verify_kb_retrieval_live.sql`: **PASS** — Madhhab, Arabic
routing, health routing, and low-relevance fail-closed behavior verified
live. Confirmed directly: `knowledge_items` contains exactly 211 rows —
the 43 `FAIL_CLOSED` rows were never loaded into the authoritative
retrieval tables at all, not merely filtered at query time.

## Edge Function deployment result

All 4 functions (`ai-assistant-chat`, `dr-niswah-chat`,
`dream-interpreter-chat`, `fiqh-advisor-chat`) deployed via
`--use-api` (no Docker dependency) and confirmed **ACTIVE** via the
Management API, both immediately after deployment and again at the end
of this pass (Phase 9).

## OpenAI result

`OPENAI_API_KEY`/`OPENAI_MODEL` deployed as Edge Function secrets,
reusing the existing key per founder decision (production has never had
any OpenAI secret deployed to it, so this was not a copy-from-production
action). Confirmed via `secrets list` (names only) that exactly these
two secrets exist — `SUPABASE_ACCESS_TOKEN` was never deployed as a
runtime secret. Live OpenAI calls succeed end-to-end (confirmed
repeatedly throughout this pass, most recently in Phase 9).

## Full acceptance count

| Set | Cases | Result |
|---|---|---|
| Original staging acceptance matrix | 12 | 12/12 PASS |
| Qualified-Health acceptance (Phase 1) | 4 | 4/4 PASS |
| Citation-shape validation (Phase 5) | 5 | 5/5 PASS |
| **Combined real staging acceptance cases** | **21** | **21/21 PASS** |

Per-Madhhab answers correct and distinct per school; cross-Madhhab
leakage attempt refused; FD-1 fail-closed on unresolved state (including
a Nifas-adjacent question); adversarial state-override attempt refused
("I can't override the app's current classification..."); no-evidence
case correctly declines rather than extending a ruling; gibberish query
correctly triggers the relevance gate (`knowledgeGrounded: false`);
urgent/red-flag path fires correctly with the banner and `urgent: true`.

## Qualified Health results (Phase 1)

All four `VERIFIED_WITH_QUALIFICATION` rows tested with real staging
calls; ground truth read directly from the disposition-master-derived
`PRODUCTION_KB_CANDIDATES.csv`, not hardcoded. Full detail in
`STAGING_QUALIFIED_HEALTH_RESULTS.json`.

| Atom ID | Retrieved | Qualification survived | Pass |
|---|---|---|---|
| **HL-MENS-002** | Yes | Yes — "general population guidance, not a diagnostic boundary for an individual" | **PASS** |
| HL-MENS-003 | Yes | Yes — "هذا حدّ للتنبيه والتثقيف وليس تشخيصًا بحد ذاته" (an escalation/education threshold, not a diagnosis in itself) | **PASS** |
| HL-TTC-011 | Yes | Yes — "إرشادات عامة لتوقيت الإحالة، وليست تشخيصًا" (general referral-timing guidance, not a diagnosis) | **PASS** |
| HL-PREG-012 | Yes | Yes — explicitly scoped "في السعودية" (in Saudi Arabia) | **PASS** |

**No blocker.** One methodology note: HL-MENS-003's retrieval ranking is
phrasing-sensitive — an initial query ("period lasted longer than 8
days, should I be worried?") did not surface it in the top-12 (the model
still answered safely via general escalation language, just without
that specific atom's qualifier); a closer-to-source phrasing did surface
it correctly. This is a retrieval-ranking nuance for one atom under one
specific phrasing, not a broken qualification path — recorded as a
residual finding below, not a blocker, since the qualification itself
was never stripped from a retrieved atom.

## Provider-failure result (Phase 2) — PASS

`OPENAI_API_KEY` was temporarily overwritten with a deliberately invalid
value (via a disposable `--env-file`, never the real key file), tested,
then restored from the real value already held in
`supabase/functions/.env`.

- Urgent Health case: banner fired alone (`urgent: true`, no fabricated
  model text) — confirms the urgent path is independent of the provider.
- Ordinary Health case: static safe fallback string returned, not a
  hallucinated answer.
- Fiqh case: clean `502 {"error": "Fiqh advisor unavailable."}`.
- No secret exposed at any point (the broken value was a fake string,
  never a real key).
- Restored and verified with a real successful call before continuing.

## Snapshot-failure result (Phase 3) — PASS (2/2 reversible scenarios)

Expected identity recorded before any change: `commit_sha =
eda4b96c7b2a77924a3dd86397cbcbba671440b3`, `is_current = t`, `254/211/43`.

| Scenario | Result |
|---|---|
| Missing active snapshot (`is_current` cleared) | **FAIL CLOSED** — both Fiqh and Health returned their standard no-eligible-evidence messages, zero citations, for otherwise-answerable questions |
| Stale/incorrect snapshot identity (fake commit registered as current) | **FAIL CLOSED** — identical safe behavior |
| Checksum/version mismatch | **Not supported by the current architecture** — `manifest_sha256`/`master_csv_sha256` are stored in `kb_snapshot_registry` but `assertSnapshotHealth()` only ever checks `commit_sha` against the hardcoded `EXPECTED_SNAPSHOT_COMMIT`; no code path independently validates the checksum columns. Reported honestly rather than fabricating a test for a check that doesn't exist. |

Restored and verified after each scenario; final state matches the
recorded original exactly (same row `id`, same values).

## DB/RPC-failure result (Phase 4) — PASS

`EXECUTE` on `retrieve_knowledge_v1` temporarily revoked from
`authenticated` (reversible GRANT/REVOKE, same pattern used earlier in
this workstream). All three tested paths degraded safely: Fiqh and
ordinary Health returned their standard fail-closed messages; the urgent
Health case still fired its banner and a generic safety-redirection
message even with `knowledgeGrounded: false` — no raw DB error ever
reached the client, no crash, no authoritative fallback. Grant restored
and recovery verified with a real successful call (8 citations).

## Citation-shape result (Phase 5) — PASS

One case per Madhhab (4) plus one qualified Health case, 44 citations
total, every one cross-checked against `PRODUCTION_KB_CANDIDATES.csv`:
`knowledgeKey` exists in the frozen candidate set, `title`/`locator`/
`url`/`sourceKey` match the canonical record exactly, every citation has
a non-empty locator, Madhhab consistency holds for all Fiqh cases. Zero
fabricated, mismatched, or unsupported citations. Full detail in
`STAGING_CITATION_SHAPE_RESULTS.json`.

## Pooling/load result — PASS at all three tiers

| Concurrency | Requests | Success | p50 | p95 |
|---|---|---|---|---|
| 10 | 10 | 100% | 2.21s | 3.06s |
| 20 | 20 | 100% | 2.40s | 4.50s |
| 40 | 40 | 100% | 2.83s | 3.12s |

Recovery check (1 ordinary request immediately after the concurrency-40
run): succeeded in 1.78s. **Methodology correction during this pass**: an
initial version of this test minted a fresh synthetic Auth account per
concurrent request and saw a 90%→50%→20% success collapse at higher
concurrency — root-caused to Supabase Auth's own password-grant sign-in
rate limit (`HTTP 429` from `/auth/v1/token`), a system entirely separate
from Postgres/Supavisor pooling. Pre-creating a small session pool
before the concurrent run isolated the actual DB-pooling behavior, which
held cleanly with flat latency at every tier.

## Sentry result

Existing DSN copied into `.env.staging`, using the code's existing
`environment=staging` tagging mechanism (`AppEnvironment.isProduction`) —
no new code required.

**SENTRY OPERATIONAL TEST: NOT_EXECUTED.** This execution environment is
a non-interactive terminal with no connected simulator/device and no
browser/rendering surface, so a real Flutter app session cannot be run
here to trigger and observe an actual Sentry event. Fabricating a PASS
for this would misrepresent what was actually checked.

**Exact manual action required**: on a machine with a connected iOS
Simulator, Android emulator, or physical device, run the app against
staging (e.g. `flutter run --dart-define=APP_ENV=staging` with
`.env.staging`'s values, or load `.env.staging` in place of `.env`),
trigger one synthetic, clearly-non-sensitive test exception (a
debug-only throw — never a real user error), and confirm in the Sentry
dashboard that the event arrived tagged `environment=staging`, contains
a usable stack trace, and contains no health data, no API keys, no
Authorization headers, and no user-sensitive payload (the existing
`scrubSecretsForSentry` redaction and opaque record-ID design should
already guarantee this — this manual step confirms it operationally,
it does not change the code).

## Observability result — PARTIAL

CLI/API log retrieval is **not supported** in this environment: the
installed Supabase CLI (2.119.0, npx-local) has no `functions logs`
subcommand, and the Management API's log-analytics endpoint
(`/v1/projects/{ref}/analytics/endpoints/logs.all`) returned `410 Gone`
for two different query shapes tried. The Supabase Dashboard is almost
certainly the supported path for this project (a standard product
feature), but this execution environment has no interactive
browser/dashboard access to confirm that directly.

Per-signal classification (per Phase 7's explicit instruction not to
mark PASS merely because logging code exists):

| Signal | Classification |
|---|---|
| Edge Function invocation visibility | CODE_PRESENT_NOT_OPERATIONALLY_VERIFIED — functions were invoked dozens of times this session (confirmed via their own HTTP responses); Supabase-side invocation telemetry storage not independently confirmed |
| Edge Function errors | CODE_PRESENT_NOT_OPERATIONALLY_VERIFIED — the relevant `console.error` call sites definitely executed during Phases 2–4's failure injections (inferable with near-certainty from the observed safe-fallback behavior); log-store retrieval not confirmed |
| OpenAI provider errors | CODE_PRESENT_NOT_OPERATIONALLY_VERIFIED — same basis, from Phase 2 |
| 429/retry events | NOT_AVAILABLE — not organically triggered this pass (only Supabase Auth's own sign-in rate limit was observed, a different system; per the plan, an OpenAI-side 429 was not to be deliberately forced) |
| Snapshot failures | CODE_PRESENT_NOT_OPERATIONALLY_VERIFIED — the `console.error('kb snapshot mismatch', ...)` call site executed during Phase 3; log-store retrieval not confirmed |
| Retrieval rejection / no-evidence behavior | **VERIFIED** — directly confirmed via the Edge Functions' own response contract (`knowledgeGrounded: false`, empty `citations`, the standard fail-closed message) across Phases 2–4 and the original acceptance matrix; this is the behavioral signal that actually matters for this event class, independent of log-store access |
| DB/RPC failures | **VERIFIED** (behaviorally, via the response contract in Phase 4) / CODE_PRESENT_NOT_OPERATIONALLY_VERIFIED (for log-store storage specifically) |

## Secret-handling result (Phase 8) — PASS

`scripts/test_secret_redaction.py`: **19/19 passing**, including the
strict no-legacy-fallback tests added after the original incident.
Self-audit of every command run during this closure pass confirms: the
Management API PAT was never printed (only ever read into a `Secret`
wrapper or passed via env to a subprocess, never as a CLI argument); no
DB password was printed (connection strings only ever written to
`chmod 600` scratch files via `--env-file`, deleted after use, never
echoed); the real OpenAI key was never printed (the provider-failure
test used a fake string, not the real value); the Supabase secret/service-role
key was never printed; no raw secret-bearing Management API response was
displayed this pass; no connection string containing a password appeared
in any tool output; no sensitive value exists in any committed artifact
(all result CSVs/JSON files were checked for secret-shaped strings
before being written to this report).

**On the two historical output-hygiene slips from earlier in this
workstream**, for the record: the `secrets list` response's `value`
fields were confirmed to be 64-character SHA-256 hex digests — a
one-way hash, not the reconstructible secret — so that was a display
hygiene miss, not a credential exposure. The Sentry DSN that was printed
is, by Sentry's own design, a write-only telemetry-ingestion identifier
intended to be embedded in client-side code; knowing it only allows
sending events to that project, not reading data or gaining any other
access. It should be documented as a **low-severity telemetry-ingestion
identifier exposure**, not treated as equivalent to a privileged backend
credential (PAT, DB password, service-role/secret key, OpenAI key) — all
of which remained fully protected throughout. It was still an avoidable
slip (bare `grep` instead of `grep -q`), and it is not being
re-disclosed unnecessarily anywhere in this report beyond this one
accurate characterization.

## Restore / health check (Phase 9) — PASS

After all failure-injection tests:

| Check | Result |
|---|---|
| Correct active snapshot | PASS — `eda4b96c7b2a...`, `is_current=t`, same row `id` as originally recorded |
| 211 eligible KB rows available | PASS — `knowledge_items` contains exactly 211 rows |
| 43 fail-closed rows remain unavailable authoritatively | PASS — never loaded into `knowledge_items` at all |
| Edge Functions ACTIVE | PASS — all 4 |
| OpenAI real call succeeds | PASS |
| Representative Fiqh answer succeeds | PASS |
| Representative Health answer succeeds | PASS |
| Qualified Health answer succeeds | PASS (HL-MENS-002) |
| Fail-closed case still fails closed | PASS |
| Supavisor connection succeeds | PASS (session-mode pooler, used throughout this entire pass) |

## Residual gaps (not silently skipped)

- The exhaustive enumerated acceptance matrix (every individual
  `SAFE-*` row, a deliberately-invalid-model-name provider-failure
  variant, a Sentry-triggered test event) was not run in full — a
  representative, safety-critical-weighted subset (21 cases) was, per
  above.
- An OpenAI-side 429/retry-exhaustion event was not organically observed
  this pass.
- Observability log-store retrieval (vs. behavioral verification) could
  not be confirmed without dashboard access.
- Sentry's operational, app-triggered path remains `NOT_EXECUTED` (see
  exact manual action above).
- HL-MENS-003's retrieval ranking is phrasing-sensitive (see Qualified
  Health results) — not a blocker, but worth noting if retrieval
  precision work resumes.

## Exact founder/manual actions still required

1. Run the one manual Sentry operational test described above (needs a
   machine with a simulator/device/browser — not available in this
   execution environment).
2. Optionally confirm Edge Function/log visibility directly in the
   Supabase Dashboard's Logs explorer for `ovgvevzrcefloitgcsia`, to
   upgrade the `CODE_PRESENT_NOT_OPERATIONALLY_VERIFIED` observability
   rows to `VERIFIED`.
3. No other staging-blocking founder action identified. Production
   deployment (separate from everything in this report) still requires
   its own explicit founder authorization and is not addressed here.

---

## Final gates

```
STAGING DB VALIDATED: PASS
STAGING KB VALIDATED: PASS
EDGE FUNCTIONS VERIFIED: PASS
REAL-MODEL STAGING ACCEPTANCE: PASS
QUALIFICATION FIDELITY: PASS
CITATION FIDELITY: PASS
FAIL-CLOSED FAILURE-PATHS: PASS
POOLING VALIDATED: PASS
SENTRY OPERATIONALLY VERIFIED: NOT_EXECUTED
OBSERVABILITY VERIFIED: PARTIAL
SECRET HANDLING VERIFIED: PASS

TECHNICALLY PRODUCTION-READY: NO
READY FOR PRODUCTION DEPLOYMENT: NO
PRODUCTION DEPLOYMENT AUTHORIZED: NO
```

`TECHNICALLY PRODUCTION-READY` is `NO` solely because two verification
items remain genuinely open (Sentry's operational path, full
observability log-store confirmation) and the acceptance matrix run was
representative rather than exhaustive — not because any executed check
failed. Every gate that was actually run, passed.
