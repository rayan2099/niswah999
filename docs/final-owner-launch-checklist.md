# Final Owner Launch Checklist

Produced by the Final Pre-Owner-Action Readiness Consolidation wave, 2026-09-07. This is an **execution document**, not a history — for the full evidence behind any step, see `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §39 and the wave sections it cites. No secrets appear anywhere below.

**Application-code remediation is complete.** Every remaining item here is owner action, external credential, remote verification, platform acceptance, or a legal/product decision — none is an engineering task this session can perform.

---

## How to use this document

Steps are numbered in the order that minimizes context-switching and dead time. Two steps (3 and 8) have an unavoidable wait — start them early and do other steps while waiting, then come back. Each step names the finding it closes and exactly what to check if it fails.

---

## Step 1 — Rotate the exposed Supabase database credential

**✅ DONE (2026-09-07)** — executed via `DELETE /v1/projects/jkmjobvxfrmuwafczvtw/cli/login-role` (Supabase Management API, direct `curl` using the CLI's own stored session token — never printed). `HTTP 200`, `{"message":"ok"}`. Verified via two independent Management API calls afterward (project-info, backups-list), both `200`, project `ACTIVE_HEALTHY`, no application-facing role/schema/data affected. SQL-level `DROP ROLE` via `supabase db query --linked` hung on three attempts (the CLI binary itself was unresponsive this session, even for previously-reliable read calls) and was abandoned in favor of the direct Management API endpoint, which succeeded immediately. No password — old or new — was ever printed or logged.

| | |
|---|---|
| **Why now** | `cli_login_postgres`'s password was inadvertently printed to session output during an earlier wave's tooling investigation. It is a **persistent** role — the exposure does not expire on its own. No dependency on anything else; do this first. |
| **Action** | ~~In `psql` or the Supabase SQL Editor, run: `ALTER ROLE cli_login_postgres WITH PASSWORD '<new-strong-password>';` — or drop the role entirely (`DROP ROLE cli_login_postgres;`) and let the Supabase CLI recreate it automatically on next use.~~ **Superseded — done via the Management API `DELETE /v1/projects/<ref>/cli/login-role` endpoint instead**, which succeeded where the SQL-level approach hung. |
| **Expected result** | The old password value (never printed in any document, including this one) no longer authenticates. |
| **Finding closed** | Standing security exposure noted in `00_09` §34-§37, §40. |
| **If it fails** | N/A — completed successfully this session. |

## Step 2 — Rotate the exposed Gemini API key

**✅ DONE (2026-09-07) — `SEC-001`/`ROOT-002` now `VERIFIED_CLOSED`.** New key generated and set as the Supabase secret; all 4 Edge Functions redeployed (`dr-niswah-chat` v9, others v3); two independent rounds of real production smoke tests — one before, one after you confirmed revoking the old key in Google Cloud Console — both passed identically (real Gemini replies from all 4 functions, red-flag safety exemption intact, Fiqh still safely degraded, correct 400/401, zero credential leakage). The post-revocation round is the decisive evidence: every function kept working with the old key gone, directly proving the new one is what's in use. See **Gemini Rotation Handoff** below for the full sequence as executed.

## Step 3 — Provision a real production backup (start early — this has a wait)

**✅ DONE (2026-09-08) — backups confirmed real and running.** `GET /v1/projects/<ref>/database/backups` now shows **7 consecutive `COMPLETED` daily physical backups** (`2026-09-01` through `2026-09-07`, ~16:24 UTC each day) — a genuine, verified change from the prior "zero backups" state. `W1-001`'s deployment authorization has cleared as a direct result (`SAFE_TO_AUTHORIZE_W1_001_DEPLOYMENT`). **`BR-001` is `PARTIALLY_REMEDIATED`, not fully closed** — its own native definition requires a real restore drill in addition to backup existence (see the BR-001 Owner Checklist below); that step remains outstanding.

| | |
|---|---|
| **Why now, first** | Daily backups can take up to 24 hours to first appear after upgrading. Starting this now means the wait happens in the background while you do Steps 4-6. |
| **Action** | ~~Supabase Dashboard → upgrade to Pro~~ Done. |
| **Expected result** | Plan shows Pro or above, backups appear. ✅ Confirmed — 7 real completed backups exist. |
| **Finding closed** | Provisioning half of `BR-001` — done. The restore-drill half remains (see BR-001 Owner Checklist). |
| **If it fails** | N/A — completed successfully. |

## Step 4 — Fix GitHub authentication and push

**✅ DONE (2026-09-07)** — pushed the complete local history to `origin/main`, then found and fixed four real CI-configuration defects live against real GitHub Actions runs (see `00_09` §41 for full evidence): a baseline-unaware `dart analyze` step, a missing placeholder `.env` in the analyze/test job, 12 platform-dependent golden-image test failures, and a Gradle configuration-time signing check that blocked even debug builds. **CI now passes fully on real infrastructure** — `Analyze & Test`, `Validate DB migration reproducibility (BR-002)`, `Build Android (debug)`, `Build iOS (no-codesign)` all green. The emergency workflow (`emergency-release.yml`) was also triggered twice via real `workflow_dispatch` calls, fixed the same way, and now correctly runs through checkout/analyze/test and stops precisely at its intended signing-secrets safety gate (see Step 5).

| | |
|---|---|
| **Why now** | No dependency on Steps 1-3; unblocks CI verification and the emergency-workflow secrets setup in one motion. |
| **Action** | ~~`gh auth login`...~~ Done — the owner's refreshed PAT (repo+workflow scope) is already stored in the git credential helper and was used directly. |
| **Expected result** | `git fetch origin && git log origin/main..HEAD` shows nothing outstanding. ✅ Confirmed. |
| **Finding closed** | GitHub authentication blocker — resolved, folded into `DC-006`'s closure (`VERIFIED_CLOSED`). |
| **If it fails** | N/A — completed successfully this session. |

See the **GitHub Recovery Checklist** below for the exact verification results.

## Step 5 — Configure emergency-workflow CI secrets

**Confirmed still outstanding (2026-09-07)**: checked via the GitHub API (`GET /repos/.../actions/secrets`, names/metadata only, never values) — `total_count: 0`. The emergency workflow was triggered twice this session and, after two real CI-defect fixes, now runs cleanly through checkout/analyze/test and stops exactly at the `Write .env from CI secret` step with a clear, correct error — proving the mechanism works and this is the one genuine remaining gap for `RD-009`'s full closure.

| | |
|---|---|
| **Why now** | While already in GitHub Settings from Step 4. |
| **Action** | Repository Settings → Secrets and variables → Actions. Add: `ANDROID_RELEASE_KEYSTORE_BASE64` (base64 of `android/app/niswah-release.jks`), `ANDROID_KEY_PROPERTIES` (contents of `android/key.properties`), `EMERGENCY_BUILD_ENV_FILE` (contents of your production `.env`). |
| **Expected result** | Three secrets present (values never visible again after saving — that's normal). |
| **Finding closed** | Enables `emergency-release.yml` to produce real signed builds — the last step to fully close `RD-009`. |
| **If it fails** | N/A — this is a data-entry step with no failure mode beyond a typo, caught by the next real emergency-workflow run (re-trigger via `gh workflow run emergency-release.yml -f git_ref=<sha> -f build_number=<N> -f app_env=production` once the secrets are set). |

## Step 6 — Select the Apple Developer Team in Xcode

See **DC-010 Handoff** below for the full sequence.

## Step 7 — Verify Gemini rotation took effect

See **Gemini Rotation Handoff** below — the verification half of Step 2.

## Step 8 — Verify the first real backup exists (come back to Step 3)

**✅ DONE (2026-09-08).** `GET /v1/projects/jkmjobvxfrmuwafczvtw/database/backups` confirmed 7 consecutive `COMPLETED` physical backups, most recent `2026-09-07T16:24:18Z`.

| | |
|---|---|
| **Why now** | At least several hours after Step 3 — daily backups need time to run. |
| **Action** | ~~`supabase backups list --project-ref jkmjobvxfrmuwafczvtw`~~ Verified via the Management API instead (the CLI itself has been unreliable this engagement for several command types) — same result either way. |
| **Expected result** | `backups` array is non-empty; at least one entry with a `completed`/success-equivalent status, a real timestamp, and `physical` type. ✅ Confirmed, 7 such entries. |
| **Finding closed** | The provisioning-existence half of `BR-001` — done. See **BR-001 Owner Checklist** below for the restore-drill half, which remains open. |
| **If it fails** | N/A — completed successfully. |

## Step 9 — Authorize and execute W1-001 deployment — ✅ DONE, 2026-09-08

`W1-001` was explicitly authorized and deployed to production on 2026-09-08. Migration applied via the Supabase Management API direct SQL endpoint; all 4 Edge Functions redeployed and confirmed (via source download-diff) to run the new RPC-based limiter; full smoke test, quota/concurrency/identity-isolation tests, and a real fail-closed `REVOKE`/`GRANT` production test all passed. See **W1-001 Deployment Handoff** below for the as-executed results, and `00_09` §44 for the full evidence trail. `W1-001`, `AB-002`, `SEC-005`, `AB-008` are now `VERIFIED_CLOSED`.

## Step 10 — Confirm Sentry deployed-environment event

See **OB-006 Handoff** below.

## Step 11 — AU-009 physical-device accessibility pass

See **AU-009 Handoff** below. Best done using the real signed builds produced in Steps 4-6 (Android from CI, iOS from Xcode), but can start with a local build sooner if preferred.

## Step 12 — PC-006 legal/product determination

See **PC-006 Handoff** below. No technical dependency on anything above — can happen in parallel with any other step, including by someone other than whoever executes the technical steps.

---

# Handoff packages

## GitHub Recovery Checklist

**Items 1-7 below: ✅ verified this session (2026-09-07)**, all against real GitHub infrastructure — see `00_09` §41 for the full evidence trail, including four real CI-configuration defects found and fixed along the way (a baseline-unaware `dart analyze` step, a missing placeholder `.env`, 12 platform-dependent golden-image failures, and a Gradle configuration-time signing check that blocked debug builds too). Note: `gh` itself refused to authenticate with the stored token (`error validating token: missing required scope 'read:org'`) — verification was instead done via direct GitHub REST API calls (`curl` with the same token from the git credential helper), which worked cleanly throughout. **Item 8 (a real signed emergency artifact) remains outstanding** — the workflow now runs correctly through checkout/analyze/test and stops precisely at its designed signing-secrets gate; Step 5 above (configuring the three CI secrets) is the one remaining action to complete it.

After Step 4, verify each of these — commands are exact, no credentials required beyond the `gh`/`git` session already authenticated:

```bash
# 1. All local commits pushed
git fetch origin
git log origin/main..HEAD --oneline
# Expected: empty output

# 2. Remote main == local HEAD
git rev-parse origin/main
git rev-parse HEAD
# Expected: identical SHAs

# 3. CI workflow exists remotely
git show origin/main:.github/workflows/ci.yml | head -1
# Expected: "name: CI" — no longer "fatal: path ... not in 'origin/main'"

# 4. Emergency workflow exists remotely
git show origin/main:.github/workflows/emergency-release.yml | head -1
# Expected: "name: Emergency Android Release Build"

# 5. CI actually runs (requires gh auth from Step 4)
gh run list --workflow=ci.yml --limit 5
# Expected: at least one run with status "completed" / conclusion "success"

# 6. Migration validation job runs and passes
gh run view --job=<job-id-from-the-run-above-for-validate-migrations>
# Expected: "Schema contract: all checks passed"

# 7. iOS no-codesign CI job runs
gh run view --job=<job-id-for-build-ios>
# Expected: green, ends with "Built ... Runner.app"

# 8. Emergency workflow artifact upload works (run it once manually to prove it, via workflow_dispatch)
gh workflow run emergency-release.yml -f git_ref=<a-real-commit-sha> -f build_number=<N> -f app_env=production
gh run list --workflow=emergency-release.yml --limit 1
# Expected: completes, artifact visible via `gh run download` or the Actions UI
```

## BR-001 Owner Checklist

**Two distinct conditions — do not conflate them. Confirmed status as of 2026-09-08:**

**W1-001 authorization condition** (lighter bar) — **✅ MET.** A real production backup exists, with a known timestamp, type, and retention window: 7 consecutive `COMPLETED` physical backups, `2026-09-01` through `2026-09-07`, most recent `2026-09-07T16:24:18Z`, confirmed via `GET /v1/projects/<ref>/database/backups`. **`W1-001` is now `SAFE_TO_AUTHORIZE_W1_001_DEPLOYMENT`.** No restore drill was required for this specific gate, and none was performed — deployment itself is still your explicit decision (Step 9 above).

**Full native `BR-001` closure** (the audit's own remediation category, `BR_findings.md`) — **⏳ NOT YET MET.** "confirm plan tier, backup schedule, and PITR status; document the finding; **then execute a real controlled restore test to prove the mechanism actually works**." The first half is now done with real evidence (above). **The restore-drill half remains outstanding**, and its exact requirement is now precisely known (investigated 2026-09-08 directly against the Supabase Management API's own spec — not assumed): there is **no API-drivable "restore backup to new project" endpoint** — every restore endpoint (`/database/backups/restore`, `/database/backups/restore-pitr`) restores **in place, on the source project**, which is production; restoring over production is explicitly forbidden. Two real paths exist, **either requiring your direct action**:

- **(A) Dashboard-only restore-to-new-project** (your Pro plan is entitled — `backup.restore_to_new_project` confirmed `true` on the org): Supabase Studio → your project → Database → Backups → select a backup → "Restore to new project." This is a human-driven UI action; no API token, including this session's, can trigger it.
- **(B) API-drivable Database Branch with production data** (`POST /v1/projects/<ref>/branches` with `{"branch_name": "br-001-restore-drill", "with_data": true, "persistent": false}`): creates an isolated, disposable, production-data-cloned Postgres instance reachable only via its own connection string — but requires provisioning a billed compute-instance addon (from ~$0.01344/hour, destroyed immediately after verification, likely under $0.10 total for a short drill). This is a real billing action and needs your explicit go-ahead before this session (or any automated session) provisions it, consistent with every other billing decision in this engagement.

Once either path produces a real restored/cloned environment, the existing 14-point behavioral verification suite (`00_09` §20 Phase E) runs against it, then it's destroyed. **This does not need to happen before `W1-001` is deployed** (already done — see Step 9) — it can follow at your own pace. Once done, `BR-001` moves to `VERIFIED_CLOSED` and `RTO` stops being `UNTESTED`.

**If you choose path (B)**: reply with explicit authorization to provision a temporary branch compute instance (e.g., "I authorize creating a temporary micro compute branch for the BR-001 restore drill, to be destroyed immediately after verification") and this can proceed via the API in a future session.

```bash
# Re-check current backup state at any time:
curl -s -H "Authorization: Bearer $(cat ~/.supabase/access-token)" \
  "https://api.supabase.com/v1/projects/jkmjobvxfrmuwafczvtw/database/backups"
```

## W1-001 Deployment Handoff — ✅ EXECUTED, 2026-09-08 (see `00_09` §44 for full evidence)

**As executed** (differs from the originally-prepared package in two respects, both noted below):

1. **Checksum verification**: `shasum -a 256 supabase/migrations/20260906090000_ai_rate_limit.sql` → `4b346d3f71bfa87509139f81efd802877145032bbe16420b645ce195c99c2639`, confirmed unchanged immediately before applying. ✅
2. **SQL apply** — applied via the Supabase Management API's direct SQL-query endpoint (`POST /v1/projects/<ref>/database/query`, the file's exact contents as the query body) rather than the Dashboard SQL Editor — an equally isolated, single-file apply with the advantage of being scriptable and auditable inline. `HTTP 201`, ~2 seconds. `supabase db push` was not used. ✅
3. **Ledger bookkeeping**: **not performed this wave** — `supabase migration repair` was intentionally left out of scope (the charter's hard rules explicitly prohibited touching the historical migration ledger). The migration is applied and verified in the live schema; ledger bookkeeping remains a separate, optional, non-schema-mutating cleanup step that can be done at any time without urgency.
4. **Smoke checks**: table confirmed present; all 4 AI functions called with a real authenticated synthetic test account — 3 returned real Gemini replies, `fiqh-advisor-chat` remained in its already-approved safe degraded state. ✅
5. **Edge Function deployment**: `supabase functions deploy` completed cleanly this time (~15s, no hang) for all 4 functions; confirmed via download-diff that all 4 now call the RPC. ✅
6. **Concurrency test**: run as 10 concurrent requests against quota 5 (not 25/15 as originally sketched — an equivalent, smaller-footprint version of the same atomicity proof) directly against the production RPC. Result: exactly 5 allowed / 5 rejected, no duplicates, no gaps. ✅
7. **Fail-closed test**: real `REVOKE`/`GRANT` cycle performed exactly as planned — `503`, no Gemini call, then fully restored and re-verified. ✅
8. **Red-flag exemption test**: confirmed live via the smoke test — `dr-niswah-chat` correctly returned `urgent: true` for red-flag phrasing. ✅
9. **Rollback path**: unchanged, still documented in `RD_release_rollback_runbook.md` §6.2 — not needed this wave (no failure occurred).
10. **Result**: all checks passed — `W1-001`, `AB-002`, `SEC-005`, `AB-008` are now **`VERIFIED_CLOSED`**. All synthetic test accounts/threads/counter rows created during verification were deleted; final `ai_rate_limit_counters` count = 0.

## Gemini Rotation Handoff (SEC-001 / ROOT-002) — ✅ COMPLETE, 2026-09-07

**As executed**:
1. Google Cloud Console / AI Studio → new Gemini API key generated (owner action).
2. Supabase secret updated — confirmed via metadata only (`updated_at` changed from `2026-09-04T20:27:29Z` to `2026-09-07T10:51:48Z`; value never seen or requested).
3. All 4 functions redeployed (`dr-niswah-chat` v8→v9, `fiqh-advisor-chat`/`dream-interpreter-chat`/`ai-assistant-chat` v2→v3) — note: `supabase functions deploy` hung locally (0% CPU, 3 attempts, killed each time) but a version check confirmed the redeploy completed server-side regardless; reported as an honest, unexplained-but-verified tooling discrepancy, not glossed over.
4. **Round 1 (pre-revocation)** smoke test: all 4 functions returned real Gemini replies via a synthetic admin-created test account; red-flag exemption intact; Fiqh safely degraded; 400/401 correct; zero credential leakage.
5. Old key revoked in Google Cloud Console (owner action, confirmed).
6. **Round 2 (post-revocation)** smoke test — a second, independent full round, new synthetic account: identical results. **This round is the decisive evidence** — every function kept returning real Gemini output after the old key was no longer valid anywhere, directly proving the new key is in use, not inferring it from the rotation action alone.

**Closure evidence, achieved**: both rounds passed; the old key is revoked; client artifact remains clean (re-confirmed via source-level scan — zero `AIza…` matches, zero direct Gemini call paths). `SEC-001`/`ROOT-002` → **`VERIFIED_CLOSED`**. No secret value appeared in any report at any point.

## OB-006 Handoff

Current evidence: a real, server-confirmed Sentry event ID was already produced from a `development`-environment test (`00_09` §18) — the `AppErrorReporter → Sentry.captureException` code path is proven end-to-end. What's not yet confirmed is the same delivery specifically from a **release/deployed** build.

**Two paths to closure — either is sufficient, pick whichever is faster**:
- **A (likely already done, just needs checking)**: search the Sentry project dashboard for events tagged `feature:sentry_staging_verification` — if one exists from a prior wave's attempt, that alone can close `OB-006` on the owner's discretion, per `00_09` §25's own closure note.
- **B (if A finds nothing)**: install a real signed release build (Android `.apk`/`.aab` from Step 4's CI, or the iOS build once Step 6 produces a signed one) on a **real physical device** (not an emulator — every session-side emulator attempt hit genuine platform storage/logging limitations, not application defects, per `00_09` §19 Item 8's full account), trigger any real error path, and confirm the event arrives in the Sentry dashboard with `environment: production`.

**Do not conflate with `RR-002`** — `RR-002` (systematic error-reporting coverage) is already `VERIFIED_CLOSED`; `OB-006` is specifically about confirming *delivery from a deployed build*, a narrower, still-open bar.

## DC-010 Handoff

Sequence, confirmed sufficient by this engagement's own iOS Release Readiness wave (`00_09` §38) — every other release-readiness item is already verified:

1. Xcode → sign in with an Apple ID enrolled in the Apple Developer Program (Xcode → Settings → Accounts).
2. `Runner` target → Signing & Capabilities → select that Team. `CODE_SIGN_STYLE = Automatic` is already correctly configured — Xcode generates the certificate and provisioning profile itself once a Team is selected. No separate manual certificate/profile creation step is needed for a first release.
3. Produce a real signed build: `flutter build ipa --release --dart-define=APP_ENV=production` (or Archive via Xcode directly).
4. Validate: `codesign -dvvv build/ios/ipa/*.ipa` (or the `.app` inside it) — expect a real Distribution certificate `Authority=` line, not "not signed at all."

**Closure evidence**: a real, distributable `.ipa`, signed with a genuine Apple Distribution certificate (not `--no-codesign`), confirmed via `codesign -dvvv`. App Store submission itself (metadata, screenshots, review) is separately out of scope for `DC-010`'s own closure — this finding is about signing infrastructure, not the submission process.

## AU-009 Handoff

Concise physical-device script — critical journeys only, not exhaustive:

| Journey | iOS (VoiceOver) | Android (TalkBack) | Pass criteria |
|---|---|---|---|
| Signup/login | Navigate all fields, submit, error states announced | Same | Every interactive element has a spoken label; errors are announced, not just visually shown |
| Dashboard | Cycle ring, phase timeline, quick actions all reachable and labeled | Same | No unlabeled icon-only buttons (`AU-001` should already prevent this — confirm it holds live) |
| Cycle tracking (log entry) | Log sheet fully operable via swipe navigation | Same | Flow/symptom selection and save are all reachable without sight |
| Dr. Niswah chat | Message input, send, red-flag banner all announced | Same | The safety banner text is actually spoken, not just visually styled |
| Doctor's Report | PDF generation button reachable, loading state announced | Same | No silent/invisible loading state |
| Profile | Settings, delete-account row all reachable | Same | Delete-account confirmation dialog is fully operable via screen reader |
| Account deletion | Full flow completable start to finish | Same | No step requires sight to complete |

**Pass criteria overall**: every journey above is completable start-to-finish using only the screen reader, with no unlabeled control and no visually-only-conveyed information (color-only status, icon-only unlabeled buttons). A journey that requires sighted assistance at any step is a fail for that journey — record which step, not just pass/fail for the whole row.

## PC-006 Handoff

**Technical implementation already complete**: the data-export architecture was redesigned (per-section, resilient to partial failure — a real live bug was found and fixed in this process), and the export correctly includes/excludes data categories per the current, technically-accurate understanding of what the app stores.

**Exact legal question requiring owner/counsel decision** (not answerable by this engagement, and not attempted): whether the current data-export scope and retention behavior satisfy the specific legal obligations that apply to Niswah's actual user base and jurisdiction(s) — e.g., GDPR/CCPA-equivalent "right to erasure"/"right to portability" completeness, and whether a defined retention *period* (not just a mechanism) is legally required for health/religious-practice data in the relevant jurisdictions. This engagement has deliberately never asserted a specific legal conclusion or invented a retention period — that determination belongs to counsel.

**What would need to change only if the determination differs from current behavior**: if counsel determines a specific retention period is legally required, that would need a new, explicit deletion-scheduling mechanism (does not exist today — correctly not invented without a real requirement to build against). If counsel determines additional data categories must be exportable/deletable, the already-redesigned per-section export architecture can be extended without a full redesign. **No engineering work is being reopened speculatively** — only exactly what counsel's determination requires, once known.

## Fiqh Grounding Degradation — Classification

**Current behavior, confirmed and unchanged across every wave that checked it**: when Google's Search-grounding quota/billing condition triggers, the app fails safely — no silent ungrounded religious answer is ever produced; the degraded state is visible and handled, not hidden.

**Classification: CONDITIONAL-GO limitation, not a launch blocker.** The native finding's own risk model is specifically about the *danger of an ungrounded fiqh answer appearing grounded* — that risk is structurally closed by the fail-safe behavior, independent of whether the underlying Google Cloud quota is ever resolved. Resolving the quota/billing condition improves *service quality* (fewer degraded responses), not *safety* (which is already assured). **Do not require billing spend to reach GO** — this is accurately a deferred service-quality item, appropriately owner-discretionary, not gating.

---

# Release decision model

**NO-GO**: any of — no verified production data backup exists (`BR-001` unresolved), an exposed credential remains unrotated (both `cli_login_postgres` and the Gemini key are now rotated/revoked and verified — this gate has cleared), a critical safety/recovery/consent control is confirmed broken (none currently — all such findings are closed or narrowed to non-safety gaps).

**CONDITIONAL GO**: all critical safety/recovery/credential gates are closed (`BR-001` real backup confirmed, both credentials rotated, `W1-001` deployed and verified if desired for launch), and only accepted, owner-documented, non-critical items remain open — e.g. `AU-009` scheduled but not yet run, `PC-006` pending counsel with current behavior already legally-neutral (no false claims, no invented retention), Fiqh grounding degraded-but-safe, iOS not yet submitted to the App Store (if Android-first launch is an accepted owner choice).

**GO**: every mandatory launch gate is closed with real evidence — `BR-001` fully closed (including the restore drill, not just existence), both credential rotations verified, `W1-001` deployed and its own closure criteria met, `AU-009` executed with a passing result, `PC-006` resolved by counsel with any resulting engineering work complete, `OB-006` confirmed via a real deployed-build event, `DC-010` producing a real signed, distributable iOS build (App Store submission itself can still follow GO, not gate it).

**Current state, as of 2026-09-08**: **NO-GO**, but narrowed substantially further. Both standing credential exposures are resolved and verified (`cli_login_postgres` rotated via the Management API; the Gemini key rotated, redeployed, and confirmed working in production both before and after old-key revocation). `W1-001` — a major, long-tracked finding, along with the three findings that depended on its production deployment (`AB-002`, `SEC-005`, `AB-008`) — is now **`VERIFIED_CLOSED`**: deployed to production on 2026-09-08 and independently re-verified with real, direct evidence at every layer (migration application, DB object correctness, Edge Function redeployment, functional smoke tests, atomic concurrency behavior under real load, identity isolation, and a real, reversible fail-closed production fault-injection test — see `00_09` §44). **`BR-001` remains `PARTIALLY_REMEDIATED`, deliberately unchanged by W1-001's deployment** — it now has a real, verified production backup (7 consecutive `COMPLETED` daily physical backups), a genuine, hard-won change from every prior wave's "zero backups" state, but its own native closure bar requires a real restore drill in addition to backup existence, per its own remediation category, and that drill has not been performed. Per the GO criteria above (which require `BR-001` "fully closed, including the restore drill, not just existence") this alone keeps the verdict below GO. Every other remaining item (`DC-010`, `AU-009`, `PC-006`, `OB-006`, the emergency workflow's CI secrets) is independently owner/external/platform/legal-gated and unaffected by this wave. **Practically**: the restore drill is now the single remaining step to fully close `BR-001` itself; nothing else stands between the current state and a `CONDITIONAL GO` besides that drill and the independently-gated items listed above.

---

# Post-owner verification pass (run once all steps above are complete)

```bash
# GitHub
git fetch origin && git log origin/main..HEAD --oneline   # expect empty
gh run list --workflow=ci.yml --limit 3                    # expect success

# BR-001
supabase backups list --project-ref jkmjobvxfrmuwafczvtw   # expect non-empty, completed

# W1-001 (Step 9 executed 2026-09-08 — see 00_09 §44)
supabase migration list --linked                            # expect 20260906090000 remote != empty
# + re-run the concurrency/fail-closed/red-flag tests from the handoff above if further confidence is desired

# Gemini
# Call all 4 AI functions with a real test account, confirm 200 + real replies
# Confirm old key shows revoked in Google Cloud Console

# Sentry
# Search dashboard for a real deployed-build event with environment: production

# iOS signing
codesign -dvvv <path-to-real-.ipa-or-.app>                  # expect a real Authority= line

# AU-009 / PC-006
# No command — confirm both handoffs above were actually executed and their results recorded
```

Once every check above passes: re-run this document's Release Decision Model section and update `production-readiness-results/master/00_04_MASTER_FINDING_REGISTER.md`/`00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` with the final verdict. Do not update those documents based on assumption — only on the actual command output/dashboard state observed at that time.
