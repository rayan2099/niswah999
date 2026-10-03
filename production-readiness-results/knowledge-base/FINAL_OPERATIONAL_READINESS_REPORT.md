# Final Operational Readiness Report — Niswah Staging

**Date**: 2026-10-03. Closes the two operational gates left open by
`STAGING_VALIDATION_REPORT.md`: Sentry's operational event-delivery test
(previously `NOT_EXECUTED`) and real cloud-log observability (previously
`PARTIAL`, unconfirmed beyond behavioral inference). Production
(`jkmjobvxfrmuwafczvtw`) was never touched. No KB evidence, disposition,
retrieval architecture, relevance gate, provider architecture, Madhhab
boundary, canonical-state logic, or migration was modified. Staging
database contents were touched only by the same reversible synthetic
validation pattern used in the prior closure pass (none this pass —
everything below used read-only Management API calls and read-only live
HTTP requests against already-deployed functions).

---

## Phase 0 — PR #11 baseline

- PR #11: **OPEN**, `MERGEABLE`, base `main`. All 8 CI checks **green**
  (Analyze & Test, Build Android, Build iOS, migration reproducibility,
  local-bootstrap reproducibility, secret-redaction, KB review packets,
  KB retrieval Deno tests).
- Working tree clean except the same pre-existing, unrelated items noted
  throughout this engagement (`.claude/scheduled_tasks.lock` deletion,
  untracked `acceptance/` persona-testing harness from a separate
  workstream, untracked macOS SwiftPM workspace files) — none touched.
- All intended commits pushed; no unpushed work.
- Staging project re-verified via the Management API: ref
  `ovgvevzrcefloitgcsia`, name "Niswah Staging", `ACTIVE_HEALTHY` —
  confirmed distinct from the production ref `jkmjobvxfrmuwafczvtw`.
- Active snapshot re-confirmed: `eda4b96c7b2a77924a3dd86397cbcbba671440b3`,
  `is_current = t`, `254/211/43` — unchanged, no regression.

No trust-boundary gate had regressed. Proceeded.

## Phase 1 — Strongest available Flutter staging runtime

Discovery via `flutter devices`: no physical device, no Android
emulator, no iOS simulator running. Two usable targets found without
installing any new toolchain: **macOS (desktop)** and **Chrome (web)**.

- **macOS desktop** was attempted first (a true native runtime, closer
  to how iOS/Android would exercise Sentry's native layer than a
  browser). Its build stalled during Xcode's Swift Package Manager
  dependency resolution (`xcodebuild -resolvePackageDependencies`) —
  confirmed stuck, not merely slow: ~10 minutes elapsed with the process
  consuming only ~2.7 seconds of total CPU time, the same
  no-progress signature this engagement has already seen from this
  machine's Docker Desktop issues. Stopped rather than waiting further.
- **Chrome (web)** was tried next per the stated fallback order:
  `integration_test` does not support web targets in the installed
  toolchain ("Web devices are not supported for integration tests yet").
- Fell back to **plain `flutter test` (Dart VM / `flutter_tester`
  target)** — not explicitly listed in the five options, but a genuine
  existing non-production Flutter execution target requiring no new
  toolchain, no simulator, and no native compilation. This worked
  immediately.

No app-store build was produced; no production configuration was used;
nothing was installed beyond the `integration_test` dev dependency
(bundled with the Flutter SDK, no network download), which was removed
again afterward (see Phase 2).

## Phase 2 — Sentry operational event test

A temporary test file (`test/sentry_staging_operational_test.dart`, never
committed) called the exact same SDK surface `lib/main.dart` wires up —
`SentryFlutter.init` with a `beforeSend` scrub mirroring
`scrubSecretsForSentry`, then `Sentry.captureException` with the same
scope-tag pattern `AppErrorReporter.onReport` uses — against the real
staging DSN read from `.env.staging`. The thrown exception was a single
synthetic, clearly-labeled, non-sensitive test exception. No permanent
crash button or other change was made to any committed file.

**Result**: `SentryFlutter.init` succeeded with the real staging DSN;
`Sentry.captureException` returned a genuine, non-empty event ID; the
async `Sentry.close()` flush completed without a transport exception.
Separately, a plain unauthenticated HTTPS request to the DSN's ingest
host returned `HTTP 404` (not a connection/DNS failure) — confirming the
host itself is live and reachable from this network, ruling out silent
non-delivery due to connectivity.

What this does **not** establish: the Sentry Dart SDK's public API does
not expose the ingest server's actual HTTP response for a captured
event (by design, so a telemetry failure can never crash the host app),
and no Sentry-side read credential (API token, or dashboard access) was
available in this environment to query the project's issue list and
confirm the event was actually stored and is visible.

**SENTRY OPERATIONALLY VERIFIED: PARTIAL** — the app genuinely emitted
a real event through the real SDK with the real DSN; arrival cannot be
independently inspected from this environment. This is not a fabricated
PASS.

All temporary instrumentation was removed: the test file, the
`integration_test/` directory it initially lived in, and the
`integration_test` dev dependency from `pubspec.yaml` (reverted via
`git checkout` + `flutter pub get`, confirmed `pubspec.lock` back to its
committed state). `git status` is clean of any trace of this phase's
work.

### Follow-up attempt: independent arrival verification (post-merge, same date)

A dedicated follow-up pass attempted to close this gate per a specific
two-path instruction:

- **Path A — authenticated Sentry API access**: checked every local env
  file (`.env`, `.env.staging`, `supabase/functions/.env`) and the
  process environment for a Sentry API auth token, organization slug,
  or project slug. Only `SENTRY_DSN` exists anywhere — a write-only
  ingest identifier that cannot read events back (confirmed from
  Sentry's own documented threat model, consistent with how this DSN
  has been treated throughout this engagement). No `SENTRY_AUTH_TOKEN`
  or equivalent was ever provisioned. **Not available.**
- **Path B — Sentry dashboard/browser access**: this execution
  environment is a non-interactive terminal with no browser rendering
  surface (the same constraint that produced the `PARTIAL` result in
  the first place). **Not available.**

Per the explicit fallback for this case, stopping rather than
fabricating a verification. **The exact minimal manual action for the
founder**: open the Sentry dashboard for the project that owns the
staging DSN, filter the Issues stream by `environment:staging`, and
look for an exception beginning "Niswah staging operational readiness
test — synthetic, non-sensitive...". Two real events were actually sent
during Phase 2 with client-generated (non-secret) event IDs
`8ea27847be8c4a82a4e91bf1be562744` and `bb31d3967d624ec5837843a4615bc5f9`
— search by either directly if the UI supports it. On the event page,
confirm: it exists; `environment = staging`; the timestamp matches this
closure pass (2026-10-03); the stack trace renders; and the event body
contains only the synthetic test message plus the two tags
`context=staging_operational_readiness_test` /
`feature=observability_closure_pass` — no health/conversation text, no
Supabase/OpenAI keys, no Authorization header, no DB connection string,
no other user data.

**No gate below was changed by this follow-up attempt** — nothing new
was independently verified, so `SENTRY OPERATIONALLY VERIFIED` remains
`PARTIAL` and `TECHNICALLY PRODUCTION-READY` remains `NO`, exactly as
before. The Sentry DSN itself was not exposed in this follow-up attempt.

## Phase 3 — Supabase observability through supported paths

Per the prior pass, the installed CLI (2.119.0) has no `functions logs`
subcommand, and `/v1/projects/{ref}/analytics/endpoints/logs.all`
returns `410 Gone`. This pass fetched Supabase's current, authoritative
OpenAPI spec (`https://api.supabase.com/api/v1-json`) directly rather
than continuing to guess — confirming `logs.all` is genuinely gone (still
410 with zero query parameters, not a parameter-shape issue) but
surfacing two endpoints not tried before:

- **`/v1/projects/{ref}/analytics/endpoints/functions.combined-stats`**
  — **works** (`HTTP 200`). Returns real, per-function aggregate
  telemetry: request/success/client-error/server-error counts, log
  counts by level, execution-time percentiles, CPU/memory usage, bucketed
  by timestamp. This is a genuinely supported, current, machine-readable
  observability path for this project.
- **`/v1/projects/{ref}/analytics/endpoints/logs`** (without `.all`) —
  reachable (`HTTP 200`) and functionally live (it returns specific
  `Table "X" does not exist` errors for wrong table names, rather than a
  generic failure, proving the underlying query engine runs). However,
  none of the plausible table names tried (`edge_logs`,
  `function_edge_logs`, `function_logs`, `functions_logs`,
  `postgres_logs`, `edge_function_logs`, `supabase_functions_logs`)
  resolved — raw per-request log *line content* could not be retrieved
  this way. This may be a naming convention not covered by the public
  OpenAPI spec, or a feature of the log-table provisioning that isn't
  yet populated for a freshly-created Micro-tier project; it was not
  resolved further rather than continuing to guess table names.

**Conclusion**: the Supabase Dashboard's Logs/Observability UI is almost
certainly still the supported route for raw log-line content
specifically — this execution environment has no browser/dashboard
access to confirm that directly. What the founder would need to verify
visually, if raw log-line inspection is wanted: open the staging
project's Dashboard → Edge Functions → Logs, and confirm log lines are
visible and match the sanitized shape documented in Phase 5 below.

## Phase 4 — Actual staging signals

Totals pulled from `functions.combined-stats` for every function
(`interval=1day`, summed across returned buckets) — this reflects real
traffic generated by this and the prior closure pass's real test calls:

| Function | request_count | success_count | client_err | server_err | log_error_count |
|---|---|---|---|---|---|
| ai-assistant-chat | 0 | 0 | 0 | 0 | 0 |
| dr-niswah-chat | 20 | 20 | 0 | 0 | 9 |
| dream-interpreter-chat | 0 | 0 | 0 | 0 | 0 |
| fiqh-advisor-chat | 167 | 166 | 0 | 1 | 4 |

The single `fiqh-advisor-chat` `server_err_count = 1` lines up exactly
with the one deliberate `502` provider-failure test run in the prior
pass — an independent, external confirmation that Supabase's own
telemetry accurately captured that specific event, not just that the
code *should* have logged it.

| Signal | Classification | Basis |
|---|---|---|
| Successful Edge Function invocation | **VERIFIED** | `functions.combined-stats`, matches real test volume exactly |
| Edge Function failure | **VERIFIED** | `server_err_count` matches the known deliberate failure exactly |
| OpenAI provider failure | **VERIFIED** (via the same mechanism — the 502 above *is* an OpenAI-provider-failure case) | same |
| 429/retry event | NOT_TESTED | not organically triggered this pass; per the staging plan, not to be deliberately forced against a shared quota |
| Snapshot-missing failure | CODE_PRESENT_NOT_OPERATIONALLY_VERIFIED (behaviorally VERIFIED via live HTTP response in the prior pass; log-store content not independently retrieved) | `console.error('kb snapshot ...')` call site; prior pass's Phase 3 |
| Snapshot-mismatch failure | same as above | same |
| Relevance/no-evidence rejection | **VERIFIED** (behaviorally, via the functions' own response contract: `knowledgeGrounded:false`, empty citations) | prior pass's acceptance matrix + this pass's Phase 7 |
| DB/RPC failure | **VERIFIED** (behaviorally, via response contract during the REVOKE/GRANT test) / reflected in the `server_err`/`log_error` aggregate above | prior pass's Phase 4 |
| Urgent Health path | **VERIFIED**, and via a stronger-than-logs mechanism: every `urgent=true` exchange is durably persisted to the `flagged_conversations` table, not just logged | code + live tests across both passes |
| Request latency | **VERIFIED** | `functions.combined-stats` avg/max/min execution time |
| Function status/result | **VERIFIED** | `functions.combined-stats` success/error breakdown |
| Token/cost metrics | CODE_PRESENT_NOT_OPERATIONALLY_VERIFIED | `console.log('callOpenAI: usage', ...)` exists and executes on every successful call (confirmed via non-zero `log_info_count`), but the actual logged numeric values aren't retrievable via any endpoint found this pass |

Nothing above is marked VERIFIED merely because a log statement exists
in the source — each VERIFIED row has either an independent Management
API number matching a known real event, or a direct behavioral
confirmation from the function's own HTTP response.

## Phase 5 — Observability privacy review

No raw log-line content was retrievable this pass (Phase 3), so this
review is a direct source-code audit of every `console.error`/
`console.log` call site across all four deployed functions and their
shared libraries (20 call sites total) — the determinative check, since
it's the code that generates whatever Supabase's logs ultimately store.

Every call site logs only: opaque `userId`/`threadId` (UUIDs), `urgent`
(boolean), `error.message` strings, domain/model/status/category labels,
and (in exactly one place, `callOpenAI: usage`) token counts explicitly
scoped as *"Token counts only — never the prompt/response content
itself"* per the code's own comment. None of the 20 sites log
`question`/`content`/`reply`/health or Fiqh text, Authorization headers,
API keys, or DB connection strings — confirmed by reading every call
site's argument list directly, not inferred.

**One residual, non-blocking observation** (not something directly
observed in any real log, since none was retrievable — a code-level
caveat): `openai_client.ts`'s `NonRetryableOpenAiError` carries
`errorBody?.error?.message` taken directly from OpenAI's own API error
response. OpenAI's error bodies for some failure classes (e.g. an
invalid-API-key error) are documented to include a truncated fragment
of the submitted key in their message text. This message is logged via
`console.error('dr-niswah-chat: model call failed', { error: error.message })`
(and the Fiqh/other functions' equivalents) — never returned to the
client, but potentially reaching the log store server-side. This is an
existing code characteristic, not a new architecture change, and
nothing in this pass's own fail-injection tests (which used an obviously
fake key, not a realistic-looking one) actually triggered or confirmed
this path firing. Flagged for completeness per Phase 5's instruction to
audit every log call site, not elevated to a blocker since no sensitive
content was actually found in any sample (none was retrievable) and the
code's clear intent and 19/20 sites are unambiguously clean.

**No sensitive content was found.** This does not trigger Phase 5's stop
condition.

## Phase 6 — Alerting / detection readiness

| Mandatory signal | Detectable? | Where | Auto/manual | Alerting? | Sanitized? |
|---|---|---|---|---|---|
| Invocation / success / error counts, latency | Yes | Management API `functions.combined-stats` | Manual pull (on demand) | None configured | Yes — aggregate numeric only |
| Urgent/red-flag exchanges | Yes, durably | `flagged_conversations` table (DB row, not just a log line) | Manual pull (a query) | None configured | Yes — opaque ids + matched category labels, per existing schema |
| Provider/DB/snapshot failures | Yes, behaviorally confirmed; log-store detail unconfirmed | Function response contract (always safe) + aggregate error counts | Manual pull | None configured | Yes |
| Sentry app-crash events | Partially (this pass) | Sentry project (once dashboard-confirmed) | Manual (today) | Unknown — Sentry's own alert rules were not configured in this pass (out of scope: no new paid/governance decision was made) | Yes — scrubbed per Phase 5 of the prior pass |

**No automated alerting (paging/Slack/email) exists anywhere in this
codebase or this provisioning pass.** Every detection path above is
real and pull-available, but nothing pushes a notification to a human
today. This is a genuine gap, not a fabricated one.

**Classification**: **NON-BLOCKING BEFORE LAUNCH**, recommended as a
post-launch improvement — not because detection is absent, but because
(a) every failure mode exercised across both closure passes degrades
*safely* for the end user (a fail-closed message or a static fallback,
never a wrong/fabricated answer), so the cost of a delayed manual
discovery is "a user occasionally sees a safe retry message," not user
harm, and (b) the data needed to discover any of this already exists
and is one API call or one dashboard visit away. Setting up actual
paging/alerting is itself a product/ops decision (which channel, which
threshold, who's on call) that would be a new founder-level choice, not
something this narrow pass should decide unilaterally.

**BLOCKING BEFORE LAUNCH**: none identified in this phase.

## Phase 7 — Staging health reconfirmation

After every check in this pass (all read-only Management API calls and
read-only live HTTP requests — no failure was injected this pass, so no
restoration was needed, but full reconfirmation was still run):

| Check | Result |
|---|---|
| Expected active snapshot | PASS — `eda4b96c7b2a...`, `is_current=t`, `254/211/43` |
| 211 eligible rows available | PASS — `knowledge_items` = 211 |
| 43 fail-closed rows unavailable authoritatively | PASS — never loaded |
| All 4 Edge Functions ACTIVE | PASS |
| OpenAI normal request succeeds | PASS |
| Supported Fiqh request succeeds | PASS |
| Supported Health request succeeds | PASS |
| Qualified Health case succeeds | PASS (HL-MENS-002) |
| Fail-closed case still fails closed | PASS |
| Supavisor pooling succeeds | PASS (session-mode pooler, used throughout) |
| Staging client config points to staging only | PASS — `.env.staging` contains the staging ref, does not contain the production ref, `APP_ENV=staging` |

No production access occurred at any point.

## Phase 8 — Secret hygiene

`scripts/test_secret_redaction.py`: **19/19 passing**. Full diff of
every file PR #11 changes relative to `main` was scanned for
key/JWT/PAT/connection-string-with-password patterns: the only matches
are the connection-string *template* code (an f-string placeholder, not
a real password) and the test suite's own clearly-labeled
`FAKE_PUBLISHABLE_KEY`/`FAKE_SECRET_KEY` fixtures. A separate targeted
scan of all four result artifacts (CSV/JSON/MD) for PAT/OpenAI-key/
Authorization-header shapes found nothing. The Sentry DSN was referenced
only by its reachability status (`HTTP 404`) in this report, never
printed as a value.

## Phase 9 — Final gates

```
STAGING DB VALIDATED: PASS
STAGING KB VALIDATED: PASS
EDGE FUNCTIONS VERIFIED: PASS
REAL-MODEL STAGING ACCEPTANCE: PASS
QUALIFICATION FIDELITY: PASS
CITATION FIDELITY: PASS
FAIL-CLOSED FAILURE-PATHS: PASS
POOLING VALIDATED: PASS
SENTRY CODE READY: YES
SENTRY OPERATIONALLY VERIFIED: PARTIAL
OBSERVABILITY VERIFIED: PARTIAL
OBSERVABILITY MANDATORY LAUNCH GATES CLOSED: YES
SECRET HANDLING VERIFIED: PASS

TECHNICALLY PRODUCTION-READY: NO
READY FOR PRODUCTION DEPLOYMENT: NO
PRODUCTION DEPLOYMENT AUTHORIZED: NO
```

**`TECHNICALLY PRODUCTION-READY` is `NO` for exactly one remaining
reason**: Sentry's operational delivery is `PARTIAL`, not `PASS` — the
app was confirmed to genuinely emit a real event to the real staging
DSN, but arrival cannot be independently confirmed without Sentry-side
read access (a Sentry API token or dashboard login), neither available
in this execution environment. `OBSERVABILITY MANDATORY LAUNCH GATES
CLOSED: YES` because every signal that actually needs pre-launch
detectability has a real, confirmed, pull-available path (Management
API telemetry, the `flagged_conversations` table, and behavioral
fail-closed confirmation) — the remaining observability gap (raw
log-line retrieval, proactive alerting) is explicitly classified
non-blocking in Phase 6.

**Only remaining blocking item for `TECHNICALLY PRODUCTION-READY`**:
independently confirm, via the Sentry Dashboard (or a Sentry API read
token supplied to this environment), that the operational test event
from Phase 2 — or a fresh equivalent — actually arrived and is visible
in the project's issue stream, tagged `environment=staging`.

## Phase 10 — PR #11 closure — MERGED

All 8 CI checks were green on head commit `4ca4915`. Founder
authorization for merge was given explicitly in a separate instruction
after this report was first written. Pre-merge re-confirmed: PR still
`MERGEABLE`, head commit still `4ca4915`, all 8 checks still green, full
diff re-scanned for secrets (clean). Merged via the normal GitHub merge
mechanism (`gh pr merge --merge`, no protection bypass) — merge commit
`b5de74fce3dd2a4e1ea79e118b2e10fd0cddb9fd`. Local `main` pulled and
fast-forwarded to it; confirmed via `git merge-base --is-ancestor` that
the merge commit is reachable from `main`. The PR #11 staging-validation
workstream is closed.

Production deployment remains unauthorized regardless of this merge.
