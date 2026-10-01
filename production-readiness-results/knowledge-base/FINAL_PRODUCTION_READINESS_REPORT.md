# Final Production-Readiness Report — Niswah KB v1

**Date**: 2026-09-30/10-01. Branch `release/niswah-production-readiness`
(PR to be opened against `main`). This report is a point-in-time record;
it is not edited in place by future work.

---

## 1. PR #8 merge result

**Merged.** Found already merged at the start of this pass (by the
founder, after the prior founder-closure review — this session's own
earlier merge attempts had been blocked by Claude Code's "Merge Without
Review" permission classifier). Verified directly via `gh pr view 8`
(`state: MERGED`) and via `git log origin/main`, not assumed.

## 2. Merge SHA

`f7514a0` — "FD-1 canonical menstrual-state authority + deployment-
readiness validation (#8)", merged `2026-09-30T16:27:17Z`. Confirmed
nothing was lost: `git diff origin/main f120e4c` (the branch's last
reviewed commit) is empty — no new, unreviewed commits landed on the
branch between the founder-closure review and the merge.

## 3. New production-readiness branch

`release/niswah-production-readiness`, created from freshly-pulled `main`
(fast-forwarded `bb16b50` → `f7514a0`). Did not already exist (checked via
`git ls-remote` before creating). Current tip: `dbe46d9`.

## 4. Staging availability

**NOT_AVAILABLE**, reconfirmed. No Supabase staging project, staging
database, staging Edge Functions, staging secrets, staging Flutter
config, connection pooler, or monitoring integration was found. Same
documentary evidence as the prior pass
(`RD_production_readiness_report.md`: "staging-vs-production project
separation — UNKNOWN / NOT VERIFIED"; `DC_findings.md`: "the app has no
real dev/staging/prod separation at the application-logic layer"), and
`supabase projects list` still cannot complete from this sandbox (no
verified outbound path to the Supabase Cloud Management API). No paid or
external infrastructure was created, per instruction. Local Docker was
used as the strongest available disposable environment where it was
reachable this pass — explicitly never represented as staging.

## 5. Staging validation results

N/A — no staging environment exists to validate against (§4). In its
place: (a) extensive live validation was already performed against a
production-shaped local environment earlier in this same workstream
(full baseline+migration rebuild, 211/74/137 KB counts, snapshot registry
identity, RLS-backed Edge Function calls, 20+ real end-to-end HTTP cases
including FD-1 and the relevance gate, a 20-request moderate load test —
all previously documented in `PRODUCTION_DEPLOYMENT_READINESS_REPORT.md`
and `RETRIEVAL_PRECISION_REMEDIATION_REPORT.md`); (b) this pass
additionally re-confirmed, live, that Nifas/postpartum state-dependent
questions fail closed correctly (§8–§9) and re-ran the KB
candidate-generation portion of the deploy pipeline fresh (§14). A fresh
full live re-run of every check was interrupted partway through by a
local Docker Desktop infrastructure failure (§16) — see that section for
exactly what could and could not be freshly re-confirmed in this specific
pass.

## 6. Pooling validation

**NOT_AVAILABLE.** Unchanged from the prior report: local
Supavisor-equivalent pooling is disabled by config
(`db.pooler.enabled = false`), and Edge Functions call Postgres via
PostgREST/RPC over HTTPS rather than holding raw connections, so this
mainly affects the deploy script's own direct `psql` usage. No
production-representative pooling behavior has been validated at any
point in this workstream. A local pooler was not enabled or tested this
pass (the Docker infrastructure failure, §16, would have blocked this
attempt regardless).

## 7. Load test results

Carried forward, not re-run this pass (CI was green and re-running was
explicitly out of scope per instruction, and the Docker outage would have
blocked a fresh run regardless): 20 requests, concurrency 5, synthetic
Fiqh/Health questions, real OpenAI calls, a fresh test user per request —
**20/20 succeeded (100%), wall-clock 14.15s, p50 2.60s, p95 4.39s**, zero
database/RPC/Edge Function/OpenAI failures. See
`PRODUCTION_DEPLOYMENT_READINESS_REPORT.md` §14 for the original record.

## 8. Nifas/postpartum governance result

**Adopted policy applied successfully, with no code changes required.**
Per this pass's policy ("Nifas/postpartum state must not be independently
inferred by OpenAI... any Fiqh answer whose authoritative result depends
on unresolved postpartum/Nifas state must remain fail-closed"): a
repository-wide trace found no active canonical Nifas/postpartum engine
(§9), so none was built. Live verification (fresh test user, real HTTP
calls) confirmed the required fail-closed behavior already holds as an
emergent property of the existing FD-1 implementation:

| Case | Result |
|---|---|
| "I just gave birth 3 days ago and I'm still bleeding, can I pray?" (EN) | Fails closed — `isStateDependentQuestion()` matches "can I pray"; no Nifas state is ever supplied, so the canonical-state check correctly treats it as unresolved. |
| Arabic equivalent | Same — fails closed. |
| Adversarial: `clientFiqhState: "nifas"` sent with "Can I pray right now?" | Fails closed — `"nifas"` is not one of `FiqhCycleState`'s real 5 enum values, so `normalizeClientFiqhState()` rejects it to `null` before the state-dependence check even runs. |
| "What is the maximum duration of Nifas?" (general/definitional) | Answers normally, grounded in real Hanbali KB evidence, unaffected — confirming the policy narrows correctly and does not over-block. |

## 9. Whether a canonical Nifas/postpartum engine exists

**No.** A well-designed, Madhhab-aware schema exists —
`public.nifas_records` (`madhhab_max_days` constrained to `40`/`60`,
plus `breastfeeding_started`, `expected_end`/`actual_end`) and
`public.istihadah_episodes` — captured in
`supabase/canonical_baseline/00_public_baseline_draft.sql` from the real
production database. That file's own header comment already flags both
tables as "NOT referenced by any current code path," independently
re-confirmed by a repository-wide grep (`nifas_records`/
`istihadah_episodes`/`madhhab_max_days`: zero matches in `lib/` or
`supabase/functions/`). The only live postpartum computation is
`PregnancyStatusEngine`/`pregnancy_status.ts`'s flat, non-Madhhab-aware
40-day window — Health-context-only, never wired to `fiqh-advisor-chat`.
Building a real engine around the dormant schema would require mapping
`madhhab_max_days`/`tamyiz_applied`/`reverted_to_adah` semantics — genuine
Fiqh judgment the adopted policy explicitly puts out of scope for this
pass.

## 10. Whether Nifas remains fail-closed

**Yes**, verified live (§8). No fail-closed rule was relaxed; the 3 joint
pregnancy-loss/nifas `FAIL_CLOSED` rows are untouched and unaffected by
this finding (they concern KB evidence disposition, not this state-guard
question, and remain blocked — reconfirmed, §14).

## 11. Observability readiness

Classified per this pass's requested severity scale:

| Gap | Severity | Basis |
|---|---|---|
| No aggregation/alerting on top of existing sanitized Edge Function logs (OpenAI errors, snapshot mismatch, retrieval failures, rate-limit fail-closed, relevance-gate rejections — all already logged) | **MEDIUM** | Visible post-incident via `supabase functions logs`, not proactively surfaced. Pull-based, not push-based. |
| `SENTRY_DSN` not provisioned (code is fully wired: `AppErrorReporter` → `SentryFlutter`, funneled from every repository catch site, `FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`, with secret-scrubbing and opaque-ID-only record references) | **HIGH** | Whole-app crash/async-error capture is inactive until this one secret is set — a configuration task, not an engineering one, but high-impact while open. |
| Whole-app observability launch-readiness (`OB_production_readiness_report.md`'s own verdict: NO-GO, 11/12 mandatory gates failing) | **Not re-classified here** | A separate, larger, already-owned audit track. This report does not re-adjudicate it and does not treat it as resolved — its own severity stands on its own terms. |
| No analytics/telemetry secondary signal (`OB-008`, from the older audit) | **LOW** | A weak, secondary proxy signal at best; absence is a missed mitigating layer, not a primary detection gap. |

No sensitive health content or raw conversation text is logged anywhere
in the reviewed code paths — confirmed by re-reading the actual
`console.error`/`console.log` call sites this pass (model/status/category/
token-counts only) and by `AppErrorReporter`'s own design (`recordId` is
an opaque identifier only, by explicit code comment, never record
content).

## 12. Sentry readiness

Code-complete, operationally inactive (§11). No DSN was fabricated or
guessed — the missing configuration is documented, not worked around.

## 13. OpenAI operational readiness

Reconfirmed via the existing, unchanged, currently-passing
`openai_client.test.ts` suite (part of the 138/138 Deno total, §16): 401
fails immediately with no retry; 429 retries exactly once on the same
model then fails if still rate-limited; a transient 5xx followed by
success returns the successful result; a network-level `TypeError` is
classified and fails safely. `maxAttempts` is bounded
(`1 + maxRetries`, default `maxRetries = 1`) — no infinite-retry path
exists structurally. Urgent Health safety logic (`detectRedFlags()`) is
computed independently of the OpenAI call and before generation, so it is
unaffected by any provider failure, by construction — unchanged this
pass.

## 14. Migration dry-run

Performed as a **documentation/code consistency walkthrough** this pass
(live execution of the DB-dependent steps was blocked by the Docker
outage, §16; the DB-independent steps were freshly re-run):

- All three migration files, all six `deploy_kb_v1.sh`-referenced
  scripts, and both referenced acceptance-results CSVs confirmed present
  and consistent (fresh check this pass).
- **Freshly re-run this pass** (file-based, no DB required):
  `scripts/verify_kb_review_packets.py` → `KB REVIEW GATE: PASS`;
  `scripts/build_kb_production_candidates.py` → `74 Health/Safety + 137
  Fiqh = 211 production candidates (4 qualified); 43 quarantined;
  snapshot commit=eda4b96c7b2a`; `scripts/render_kb_seed_sql.py` →
  rendered cleanly from the same 211 candidates. All three exactly match
  every prior count in this entire workstream — zero drift.
- **Not freshly re-run this pass** (requires a live local or staging
  database, blocked by §16): `supabase db push`, the KB seed apply,
  `verify_kb_live.sql`, `verify_kb_retrieval_live.sql`, Edge Function
  deploy, and the full live smoke-test matrix. These were extensively
  executed and passed earlier in this same workstream (documented in
  `PRODUCTION_DEPLOYMENT_READINESS_REPORT.md` and
  `RETRIEVAL_PRECISION_REMEDIATION_REPORT.md`) against the exact same
  migrations and KB evidence — nothing in the KB evidence, disposition,
  or these migrations has changed since those runs completed
  successfully. This is disclosed as a partial-this-pass /
  complete-prior-pass result, not claimed as freshly re-verified
  end-to-end today.

## 15. Backup/rollback readiness

Per `PRODUCTION_DEPLOYMENT_RUNBOOK.md` (unchanged this pass): Edge
Functions are stateless, rollback is redeploying prior code. All three
migrations are additive only (`CREATE TABLE`/`CREATE OR REPLACE
FUNCTION`, no `DROP TABLE`/`DROP COLUMN` against any pre-existing
object) — confirmed again by re-reading all three this pass. No
down-migration has been written (out of scope unless requested). Backup
prerequisites reference the separate, existing BR-001 backup/recovery
workstream, not re-verified here.

## 16. Local reproducibility

**Real gap confirmed again, real fix built, fix not fully live-verified
this pass — disclosed honestly, not glossed over.**

The gap: `supabase/config.toml` references a `supabase/seed.sql` that
does not exist; a bare `supabase db reset` prints a `WARN` and silently
skips seeding, leaving only migration-created tables (`cycle_entries`,
`pregnancy_profile`, `users`, etc. all absent) — reconfirmed by directly
running `supabase db reset` this pass and observing exactly this.

The fix: `scripts/bootstrap_local_dev.sh` (new), sharing
`scripts/validate_migrations.sh`'s proven, CI-verified sequence (same
canonical baseline, same migrations, same order) but left running rather
than torn down, since its purpose is handing back a working dev
environment. One real defect found and fixed during this pass's own
testing: the script originally removed Docker volumes without first
stopping the containers using them, so the removal silently failed when a
stack was already running (a running container holds its volume) —
fixed by adding an explicit `supabase stop` before volume removal, and by
removing a `|| true` that had been silently masking that exact failure.

**What was and wasn't confirmed this pass**: mid-testing, this session's
local Docker Desktop daemon crashed (`failed to connect to the docker API
...: no such file or directory`) and, after a restart, `supabase start`
hung indefinitely during container startup with zero containers ever
created (confirmed via `docker ps -a` showing nothing, for 13+ minutes,
across two separate attempts) — independently confirmed to be a local
Docker Desktop/container-runtime issue, not a network or script problem,
via direct `docker info` (succeeded) and registry-connectivity checks
(`https://public.ecr.aws/` responded normally). This could not be
resolved from within this session. **The fixed script's logic was
reviewed line-by-line and partially exercised** (both attempts correctly
reached and completed the "stop stack" and "remove volumes" steps before
Docker itself hung on the subsequent container-start step) **but a full,
live, end-to-end run was not completed this pass.** This is recorded
plainly as a known residual verification gap — recommended as the first
thing to confirm in a future session once local Docker is stable (§24).

## 17. Flutter integration

Zero Dart/Flutter files changed on this branch relative to `main`
(confirmed via `git diff origin/main --stat -- lib/ test/`, empty).
`flutter analyze`: 43 pre-existing info-level issues, no errors/warnings
— identical to the established baseline, re-run fresh this pass. Full
`flutter test` not re-run this pass (no Dart changes to justify it,
consistent with "do not rerun unnecessarily"; last full run: 520/530,
10 pre-existing golden-image failures, documented in the prior report).

## 18. Security/trust-boundary recheck

Reconfirmed this pass, by the means available without a live DB:

- Secret scan: `git diff origin/main` across the full branch, scanned for
  `OPENAI_API_KEY=sk-...` / `Authorization: Bearer ...` patterns — clean.
  `.env` files remain gitignored. No production migration, secret, or KB
  snapshot was touched.
- Fail-closed/Madhhab/qualification/relevance-gate/FD-1-state invariants:
  re-confirmed via the full, currently-green 138-test Deno suite
  (`kb_relevance_gate.test.ts`'s 68 cases, `fiqh_state_guard.test.ts`'s 8
  cases, `kb_retrieval.test.ts`, `openai_client.test.ts`,
  `pregnancy_status.test.ts`, `ai_user_context.test.ts` — all
  deterministic, all passing, none weakened or modified this pass).
- Nifas/postpartum: live-reconfirmed this pass (§8).
- The 254/211/43 KB disposition and its checksum: reconfirmed via the
  freshly-re-run `build_kb_production_candidates.py` (§14) — exact match,
  zero drift.
- No Scholar-Approved or Medically-Approved status exists anywhere —
  structurally guaranteed (no such value is ever written; the disposition
  vocabulary itself only contains `PRODUCTION_ELIGIBLE`/`FAIL_CLOSED`),
  independently re-confirmed by direct CSV inspection in the prior
  founder-closure review (unchanged since).
- Live database-level checks (fail-closed atom retrieval, cross-Madhhab
  leak check, snapshot-mismatch-fails-safely) were **not** re-executed
  live this pass (§16) — these were extensively verified earlier in this
  workstream against the identical, unchanged evidence and code.

## 19. Regression totals (this pass)

- Python: `test_build_kb_production_candidates.py` 11/11,
  `test_trust_boundary.py` 14/14 — fresh this pass.
- Deno: **138/138** — fresh this pass. `deno check` clean on all 4 Edge
  Functions.
- Flutter: `flutter analyze` clean of errors/warnings (43 pre-existing
  info items) — fresh this pass. `flutter test` not re-run (no Dart
  changes).
- Live DB-dependent suites (`verify_kb_live.sql`,
  `verify_kb_retrieval_live.sql`, real-model HTTP acceptance): not
  re-run this pass (§16) — last confirmed passing earlier in this
  workstream against identical code and evidence.
- CI: PR #8's CI was green at merge time (6/6 checks, including migration
  reproducibility on a truly fresh database) — not re-run for this
  report, since CI only triggers on a push to a branch with an open PR
  against `main`, and this report precedes that PR's creation.

## 20. Remaining governance decisions

- `FD-2` (TTC in V1 scope) and `FD-3` (Dream Interpreter KB positioning)
  — reviewed this pass per explicit instruction not to silently decide
  them: both remain genuinely non-blocking (re-read directly from
  `FOUNDER_DECISIONS.md`; nothing in this pass's staging/pooling/Nifas/
  observability work touches either), left `PENDING_FOUNDER_REVIEW`,
  documented as follow-ups, not decided here.
- Whether to build a real canonical Nifas/postpartum engine around the
  dormant `nifas_records`/`istihadah_episodes` schema — explicitly a
  post-launch engineering/governance dependency per the adopted policy,
  requiring genuine Fiqh-scholar input on `madhhab_max_days`/
  `tamyiz_applied`/`reverted_to_adah` semantics.
- Whether to invest in a real staging Supabase project.
- Whether to adopt the LLM-based relevance classifier tested-but-not-shipped in the retrieval remediation pass.

## 21. Remaining expert-review dependencies

Unchanged: all 254 KB atoms remain `human_review_status = NOT_REVIEWED`
(FD-5's approved premise, not a blocker); the 43 `FAIL_CLOSED` Fiqh atoms
and the 3 pregnancy-loss/nifas joint-review atoms specifically require
qualified scholar/medical review before any future disposition change.
Nifas/postpartum canonical-engine design (§20) adds a new, explicit
future dependency on qualified Fiqh scholarly input, distinct from and in
addition to the existing 43+3.

## 22. Remaining operational blockers

- No staging environment exists or was reachable (§4).
- No connection-pooling validation against production-representative
  infrastructure (§6).
- Local Docker Desktop instability encountered this pass (§16) — an
  environmental issue on this specific machine/session, not a Niswah
  code defect, but it concretely blocked full live re-verification this
  pass and should be resolved (or staging substituted) before the next
  live validation pass.
- `scripts/bootstrap_local_dev.sh` needs one clean, live, end-to-end
  confirmation run once Docker is stable (§16).
- No alerting/dashboard on existing sanitized logs (§11, MEDIUM).
- `SENTRY_DSN` not provisioned for production (§11/§12, HIGH but
  trivial to close).

## 23. Remaining technical blockers

None identified in application code this pass. The one candidate (no
canonical Nifas/postpartum engine) is explicitly addressed by the adopted
fail-closed policy, not left as an unhandled gap — see §8–§10.

## 24. Recommended non-blocking follow-ups

- Confirm `scripts/bootstrap_local_dev.sh` end-to-end once local Docker
  is stable (highest-priority item in this list, given it was the one
  thing this pass could not finish verifying).
- Resolve `FD-2`/`FD-3`.
- Provision a real `SENTRY_DSN` for production.
- Add log-drain/alerting on top of existing sanitized Edge Function logs.
- Consider a real staging Supabase project before relying on local Docker
  for future validation passes.
- Consider the LLM-based relevance classifier (tested, not shipped) if
  the deterministic relevance gate's small documented residual gap is
  later judged worth its per-request cost.
- Begin scoping what a real canonical Nifas/postpartum engine would need
  (data model, Madhhab-specific day-limit rules, scholarly sign-off) as a
  post-launch project — not started here.

---

## Final gates

**PR #8 MERGED: YES** — `f7514a0`, `2026-09-30T16:27:17Z`, verified
directly, nothing lost.

**STAGING VALIDATION: NOT_AVAILABLE** — no staging environment exists or
was reachable this pass; not mislabeled as available.

**POOLING VALIDATION: NOT_AVAILABLE** — never validated at any point in
this workstream; local pooler remains disabled.

**NIFAS/POSTPARTUM AUTHORITY RESOLVED: DEFERRED_FAIL_CLOSED** — no
canonical engine exists (confirmed by repository-wide trace); the
adopted policy's required fail-closed behavior is confirmed live and
correct as an emergent property of the existing FD-1 implementation;
building a real engine is explicitly deferred as a post-launch
dependency requiring genuine Fiqh scholarly input, not invented here.

**OBSERVABILITY READY: PARTIAL** — within this workstream's scope,
sanitized structured logging exists on every relevant failure path with
no sensitive content logged; no alerting sits on top of it (MEDIUM); the
whole-app crash/error pipeline is code-complete but inactive pending one
secret (HIGH but trivial); whole-app observability launch-readiness
remains a separate, already-owned, NO-GO-rated audit track not resolved
by this report.

**REAL-MODEL ACCEPTANCE: PASS** — carried forward from extensive,
already-documented live verification earlier in this workstream (FD-1's
9/9 cases, the retrieval gate's 11 live end-to-end cases, the Nifas
governance's 4 live cases this pass); not contradicted or weakened by
anything found this pass.

**RETRIEVAL PRECISION GATE: PASS** — carried forward; reconfirmed this
pass via the full, green, 138-test Deno suite including all 68
`kb_relevance_gate.test.ts` cases, unmodified and unweakened.

**TECHNICALLY PRODUCTION-READY: NO** — distinct from, and not to be
confused with, the already-established "TECHNICALLY DEPLOYMENT-READY:
YES" (the deploy pipeline's own hard gates passing, from the prior
report, still true and unchanged). This broader gate asks whether the
*whole* system — including staging validation and connection-pooling
validation, both genuinely never completed anywhere in this workstream —
is production-ready, not just whether the deploy pipeline runs
correctly. It is not.

**READY FOR PRODUCTION DEPLOYMENT: NO** — unchanged across every report
in this entire workstream. Staging and pooling validation remain
undone; Nifas/postpartum governance is deliberately deferred-fail-closed,
not resolved; observability is partial; local Docker instability this
pass further underscores that infrastructure-level validation remains
incomplete.

**PRODUCTION DEPLOYMENT AUTHORIZED: NO.**

---

*Commits this workstream: `dbe46d9` on `release/niswah-production-readiness`,
plus this report. No merge of this branch, no deploy, no production
migration, no production secret change, no production KB snapshot
activation, no production access of any kind performed or required.*
