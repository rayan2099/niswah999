# PR #9 Closure and Staging Readiness Report — Niswah

**Date**: 2026-10-01. Branch `release/niswah-staging-readiness`, created
from `main` after PR #9 merged. This report is a point-in-time record;
it is not edited in place by future work.

---

## PR #9 reproducibility verification

The one unverified change carried into this pass —
`scripts/bootstrap_local_dev.sh` — was **not** treated as verified merely
because its logic looked correct, per explicit instruction. Instead:

- **Refactored** to remove duplicate logic: the "apply canonical
  baseline, then every active migration in order" sequence, previously
  copy-pasted between `scripts/validate_migrations.sh` and
  `scripts/bootstrap_local_dev.sh`, now lives in exactly one place
  (`scripts/lib/apply_baseline_and_migrations.sh`), called by both.
- **Extended** `scripts/verify_schema_contract.sql` (written before the
  KB migrations existed, verified nothing about them) with a Knowledge
  Base section: all 7 KB tables, all 3 KB/snapshot/rate-limit functions,
  and a functional smoke test that actually *calls*
  `retrieve_knowledge_v1` (not just checks its name exists).
- **New CI job** (`validate-local-bootstrap`, `.github/workflows/ci.yml`):
  runs the real, unmodified `bootstrap_local_dev.sh` on a clean,
  disposable `ubuntu-latest` runner, then the extended schema contract,
  then tears down.

**Real result, not shell-syntax validity**: the job **passed** —
`https://github.com/rayan2099/niswah999/actions/runs/36848153197/job/110323168658`,
2m7s elapsed. Recorded directly from the job's own logs:
- **Environment**: GitHub-hosted `ubuntu-24.04` runner (image
  `20260920.314.1`), Docker Engine Community `28.0.4` (`docker info`
  succeeded as its own explicit step).
- **Supabase CLI**: installed via `supabase/setup-cli@v1`
  (`version: latest`).
- **Startup result**: `supabase start` succeeded; baseline applied
  cleanly (`CREATE SCHEMA`/`CREATE TYPE`/`CREATE FUNCTION`/... through to
  `CREATE TRIGGER`, no errors); all 7 active migrations applied in order
  with no errors (one expected, harmless `NOTICE` —
  `function ... does not exist, skipping`, the same defensive
  `DROP FUNCTION IF EXISTS`-style guard already present and accounted for
  in the existing migrations).
- **Schema verification**: `==> Schema contract: all checks passed` —
  every required baseline table/column/function/trigger, every required
  KB table/function, the retired-object absence checks, and the
  `retrieve_knowledge_v1` callability smoke test all passed with zero
  `FAIL` rows.
- **Teardown result**: `supabase stop` completed cleanly
  (`Stopped supabase local development setup.`).
- **Elapsed time**: ~2m7s total (checkout → CLI setup → Docker check →
  bootstrap → contract → teardown).

This is the actual, demonstrated reproducibility the instruction asked
for — a local machine's Docker Desktop failure no longer leaves this
script permanently unverified; it is now provably correct, independent of
any one developer's machine, and re-checked on every future PR against
`main`.

## PR #9 full regression

All 7 PR #9 checks passed on the commit that was merged:

| Check | Result |
|---|---|
| Analyze & Test | pass (3m23s) |
| Build Android (debug, no release signing) | pass (6m21s) |
| Build iOS (no-codesign compile check) | pass (5m55s) |
| Validate DB migration reproducibility (BR-002) | pass (2m4s) |
| **Validate local dev bootstrap reproducibility** (new) | **pass (2m7s)** |
| verify-kb-retrieval-deno-tests | pass (8s) |
| verify-kb-review-packets | pass (10s) |

254/211/43 KB disposition reconfirmed exact both before and after this
pass's changes (none of which touch KB evidence); frozen checksum
(`e6dd52c8...9faafea`) unchanged; final secret scan on the full branch
diff — clean.

## PR #9 merge

**Merged.** `gh pr merge 9 --merge` succeeded this time (the permission
that previously blocked this exact action for PR #6/#8 did not block it
here). Merge commit `32a1867bd981468e91d5e0da2ca98d05afde52e7`,
`2026-10-01T10:43:36Z`, a real merge commit (not squashed — "Merge pull
request #9 from rayan2099/release/niswah-production-readiness"). Local
`main` fast-forwarded `f7514a0` → `32a1867`, confirmed reachable, PR #9
confirmed `state: MERGED`.

---

## Observability: reconciliation against the existing NO-GO audit

Per instruction, the actual report
(`production-readiness-results/observability/OB_production_readiness_report.md`,
audited at commit `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` — a point
*before* the KB/OpenAI/FD-1/relevance-gate work in this entire later
engagement began) was read fresh, not summarized from memory, and its
individual findings (`OB-001`–`OB-010`) were checked against the current
repository, file by file, grep by grep — not assumed.

### Reconciliation

| Finding | Original claim | Current repository evidence | Status |
|---|---|---|---|
| `OB-001` (crash capture) | No Sentry/Crashlytics dependency anywhere | `pubspec.yaml:49`: `sentry_flutter: ^9.29.0`; full `SentryFlutter.init` in `lib/main.dart` | **Code resolved.** Operationally inactive — `SENTRY_DSN` not provisioned (config, not code). |
| `OB-002` (`runZonedGuarded` only `debugPrint`) | Stripped/invisible in release builds | `lib/main.dart:151`: `AppErrorReporter.report(error, stack, context: 'runZonedGuarded')` | **Code resolved.** Same DSN gap as `OB-001`. |
| `OB-003` (`dr-niswah-chat` provider-failure silent) | No logging of any kind on Gemini-call failure | `supabase/functions/dr-niswah-chat/index.ts`: 7 distinct `console.error` sites incl. `'model call failed'`; provider is now OpenAI, not Gemini, with its own classified error logging (`openai_client.ts`) | **Fully resolved**, independent of Sentry/DSN — visible today via `supabase functions logs`. |
| `OB-004` (outer catch + urgent-path insert silent) | No `console.error` anywhere in the outer catch; urgent red-flag insert failure invisible | `'flagged_conversations insert failed'` and `'unhandled error'` now explicitly, separately logged | **Fully resolved.** |
| `OB-005` (client AI call sites silent) | `ai_advisor_service.dart` catch swallows silently | Line 123: `AppErrorReporter.report(error, stack, ...)` | **Fully resolved.** |
| `OB-006` (no logging framework) | 18 `print`/`debugPrint` sites across 4 files | `AppErrorReporter` is now a real framework, used in 40+ sites — **but** `lib/core/services/cycle_log_repository.dart` (the exact file this finding cites, the DI-002 pattern) still has 8 bare `print()` calls, confirmed by direct grep | **Partially stale.** A real framework now exists; this specific, originally-cited file was never migrated to it. |
| `OB-007` (Failure hierarchy lacks code/context) | Not reviewed | — | Unchanged; outside this pass's AI/KB scope. |
| `OB-008` (no analytics/telemetry) | Not reviewed | No analytics SDK added anywhere in this entire engagement | Unchanged. |
| `OB-009` (no version/kill-switch) | No `package_info_plus` | `grep package_info pubspec.yaml` — zero matches | **Unchanged, still fully open.** |
| `OB-010` (RLS audit-trail blindness) | Not reviewed | — | Unchanged; outside this pass's AI/KB scope (DB audit logging, not AI/KB). |

**A new, confirmed-resolved item not in the original 10**:
`FlutterError.onError` (`main.dart:113`) and
`PlatformDispatcher.instance.onError` (`main.dart:120`) are both also
confirmed wired to `AppErrorReporter.report()` — all four of the
original "zero signal" hook points (`FlutterError`, `PlatformDispatcher`,
`runZonedGuarded`, repository catch sites) now funnel through one place.
Environment tagging is also present (`options.environment =
AppEnvironment.appEnvironment`, `main.dart:64`) — release/version tagging
is not (ties to the still-open `OB-009`).

### Mandatory gate table — reconciled

| Gate | Original | Now | Why |
|---|---|---|---|
| `LG-OB-01` (zero open OB0) | FAIL | **Still FAIL** | `OB-003`/`OB-004` closed; `OB-001`/`OB-002` code-complete but inactive pending one secret. |
| `LG-OB-02` (zero launch-blocking OB1) | FAIL | **Still FAIL** | `OB-005` closed; `OB-006` partial; `OB-009`/`OB-010` unchanged. |
| `LG-OB-03` (critical errors captured) | FAIL | **Still FAIL (whole-app)** | Depends on the same DSN gap; the AI/KB path specifically is captured today via Supabase function logs, independent of Sentry. |
| `LG-OB-04` (critical provider failures observable) | FAIL | **RESOLVED for the AI provider** | OpenAI failures are now explicitly classified and logged at every call site — a genuine, code-level fix, not stale wording. |
| `LG-OB-05` | N/A | N/A | Unchanged. |
| `LG-OB-06` (correlation IDs) | FAIL | **Still FAIL** | Not touched anywhere in this engagement. |
| `LG-OB-07` (release/environment tagging) | FAIL | **Partial** | Environment tagging now present; release/version tagging still absent. |
| `LG-OB-08` (critical metrics) | FAIL | **Still FAIL (whole-app)**, narrow improvement | AI token/latency are logged per-request; not aggregated into queryable metrics; nothing for the rest of the app. |
| `LG-OB-09` (alerts actionable) | FAIL | **Still FAIL** | No alerting exists anywhere. |
| `LG-OB-10` (health/readiness) | FAIL | **Still FAIL** | Not reviewed this pass; outside AI/KB scope. |
| `LG-OB-11` (no critical silent failures) | FAIL | **Still FAIL**, materially improved | `OB-003`/`004`/`005` closed; `OB-002` DSN-pending; `OB-010` unchanged. |
| `LG-OB-12` (no critical unknowns) | FAIL | **Unverified this pass** | The original report's §69 "critical unknowns" were not re-investigated — outside this pass's scope. |

**Not silently downgraded**: the mandatory whole-app observability
blocker remains real and open — roughly 9–11 of 12 gates still fail by
the same literal criteria the original audit used. What has changed,
proven from the current repository rather than assumed, is that the
**AI/KB-specific portion** of that picture (this entire engagement's own
scope) is now substantially better: provider failures are observable,
the client-side AI call path reports to a real error-tracking funnel,
and the one remaining piece for whole-app crash/error capture is a single
external secret, not missing code. The rest of the app (community,
messaging, general correlation IDs, alerting, analytics, version
tagging, RLS audit trail) is unchanged from the original audit and
remains genuinely open — this report does not claim otherwise.

### Categorized by remediation type

- **A. Code work**: none remaining for the AI/KB path specifically. For
  the rest of the app: `OB-006` (migrate `cycle_log_repository.dart` to
  `AppErrorReporter`), `OB-007` (give `Failure` a code/context field),
  `OB-009` (add `package_info_plus`), correlation-ID mechanism (`LG-OB-06`).
- **B. Secret/configuration work**: provisioning `SENTRY_DSN` (closes
  `OB-001`/`OB-002` operationally, no code change needed).
- **C. External service provisioning**: an alerting/dashboard layer on
  top of existing logs; a real Sentry project (see Phase 9 below).
- **D. Optional analytics**: `OB-008` (analytics/telemetry SDK) —
  explicitly the lowest-priority, "secondary signal" category per the
  original audit's own severity (`OB2`).

## Sentry readiness (verified by inspection, not invented)

- **Initialization**: `SentryFlutter.init` in `lib/main.dart`, DSN read
  from `AppEnvironment.sentryDsn` (empty-safe — a documented no-op
  transport when unset, per the code's own comment).
- **Environment tagging**: `options.environment =
  AppEnvironment.appEnvironment` — present.
- **Release/version tagging**: not present — no `options.release` set;
  ties directly to the still-open `OB-009` (`package_info_plus` absent).
- **FlutterError handling**: wired (`main.dart:113`) → `AppErrorReporter`.
- **PlatformDispatcher errors**: wired (`main.dart:120-121`) →
  `AppErrorReporter`.
- **Asynchronous errors**: wired via `runZonedGuarded` (`main.dart:151`)
  → `AppErrorReporter`.
- **Sanitization**: `_scrubBeforeSend`/`scrubSecretsForSentry` redacts
  Bearer tokens and JWTs from exception text before any event is sent
  (`@visibleForTesting`, covered by a real unit test per its own code
  comment).
- **Health-data/privacy boundaries**: `AppErrorReporter.report()`'s own
  `recordId` parameter is documented as "an opaque identifier (e.g. a
  `CycleLog.id`) *only* when safe to log — never the record's content" —
  no health content is passed to Sentry anywhere in the reviewed call
  sites.

No `SENTRY_DSN` was created, invented, or guessed.

**FOUNDER ACTION REQUIRED: Create/provide a staging and/or production
Sentry DSN.** No real DSN was pasted into any committed file.

---

## Staging / pooling / production-readiness status

See `STAGING_PROVISIONING_AND_VALIDATION_PLAN.md` (this same branch) for
the full specification — minimum required Supabase/OpenAI/App/
Observability configuration, exactly what this agent can execute itself
versus what requires founder action, the connection-pooling test plan
(request counts, concurrency levels, pass criteria), and the staging
acceptance matrix (Fiqh/Health/System cases, synthetic data only). No
paid infrastructure was created. No staging environment exists yet.

---

## Final gates

**PR #9 REPRODUCIBILITY VERIFIED: YES** — real CI execution on a clean
runner, not shell-syntax validity; see above.

**PR #9 CI: PASS** — 7/7 checks.

**PR #9 MERGE-READY: YES** (was, prior to merging).

**PR #9 MERGED: YES** — `32a1867`, `2026-10-01T10:43:36Z`.

**STAGING EXISTS: NO.**

**POOLING VALIDATED: NO** — never validated anywhere in this workstream;
test plan fully specified and ready the moment staging exists.

**OBSERVABILITY MANDATORY GATES CLOSED: NO** — genuine, proven progress
on the AI/KB-specific path (4 of the original 10 findings fully
resolved, 2 more code-complete pending one secret); the broader
whole-app mandatory gate set remains open, not silently downgraded.

**SENTRY CODE READY: YES** — fully wired, verified by inspection (4/4
error-path hooks, environment tagging, sanitization, privacy-safe
`recordId` discipline).

**SENTRY OPERATIONALLY ACTIVE: NO** — `SENTRY_DSN` not provisioned;
founder action required, not fabricated here.

**TECHNICALLY PRODUCTION-READY: NO** — unchanged from the prior report;
staging and pooling validation remain the two items never completed
anywhere in this entire workstream.

**READY FOR PRODUCTION DEPLOYMENT: NO.**

**PRODUCTION DEPLOYMENT AUTHORIZED: NO.**

---

## Founder action required

1. Create a Supabase staging project (separate from production) and
   provide its credentials securely (`SUPABASE_DB_URL`, service-role
   key, anon key) — see `STAGING_PROVISIONING_AND_VALIDATION_PLAN.md`.
2. Create or approve a staging OpenAI key/spending cap.
3. Create/provide a staging and/or production Sentry DSN — no real DSN
   should ever be pasted into a committed file; supply it the same
   secure way `OPENAI_API_KEY` was supplied earlier in this workstream.
4. Confirm whether a separate OpenAI staging project/key should be used,
   or an existing key reused with an explicit cap.
5. Approve (or adjust) the approximate cost estimate in
   `STAGING_PROVISIONING_AND_VALIDATION_PLAN.md` before any
   infrastructure is created.

Once these are supplied, the connection-pooling test plan and staging
acceptance matrix in that same document are ready to execute immediately.

---

*This branch (`release/niswah-staging-readiness`) contains only
documentation (this report and the staging plan) — no code changes, no
KB evidence changes, no production access of any kind. Not merged
automatically — for founder review.*
