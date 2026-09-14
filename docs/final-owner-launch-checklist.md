# Final Owner Launch Checklist

Produced by the Final Pre-Owner-Action Readiness Consolidation wave, 2026-09-07. This is an **execution document**, not a history — for the full evidence behind any step, see `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §39 and the wave sections it cites. No secrets appear anywhere below.

**Application-code remediation is complete.** Every remaining item here is owner action, external credential, remote verification, platform acceptance, or a legal/product decision — none is an engineering task this session can perform.

---

## 🟢 RESOLVED — production AI outage (2026-09-08 → 2026-09-09), read this for the incident record

**All 4 AI features returned `503` to every real user in production for a window on 2026-09-08/09.** Discovered as a side effect of live testing during the AI User-State Context Layer wave: the `W1-001` rate-limiter's database objects (`ai_rate_limit_counters` table, `check_and_increment_ai_rate_limit()` function) were found completely absent from production, confirmed via three independent read-only checks. This was *not* a full database rollback — a synthetic row created seconds earlier in the same investigation was present and current, and all other tables/data were intact — only these specific `W1-001` objects were gone.

**Explicitly authorized and recovered same-day (2026-09-09).** The same, unchanged migration file (`supabase/migrations/20260906090000_ai_rate_limit.sql`, checksum `4b346d3f71bfa87509139f81efd802877145032bbe16420b645ce195c99c2639`) was re-applied via the Management API's direct SQL endpoint, then every object independently re-verified in production, and all 4 AI Edge Functions plus the rate limiter itself re-verified live and working — full detail in `00_09` §54. `W1-001`, `AB-002`, `SEC-005`, `AB-008` are corrected back to `VERIFIED_CLOSED` in `00_04_MASTER_FINDING_REGISTER.md`, with the regression-and-recovery preserved there as incident history.

**Root cause: `PROBABLE_WITH_EVIDENCE`, not fully `CONFIRMED`.** Direct Postgres log evidence shows a compute restart followed by a WAL-archive-based point-in-time recovery that stopped at an earlier LSN than the migration's objects — an infrastructure-level event, not a logged `DROP` statement (none was found in `postgres_logs` for the entire incident window). The external trigger for the restart itself could not be attributed via any endpoint this session could reach. **Recurrence risk is structural** — this project has PITR disabled, and this restart-and-partial-replay mechanism could in principle affect other recent writes after a future restart, not only this migration's objects. Recommended, not yet actioned: discuss this compute tier's restart/WAL-archival behavior with Supabase support, and consider enabling PITR.

**Detection added (not auto-repair)**: `scripts/check_ai_rate_limit_objects.sh` — a non-mutating, read-only health check you can run manually against production with your own Management API token to catch this specific failure mode before real users do.

**🟢 Update, 2026-09-09 — this detection is now automated.** A new hourly-scheduled GitHub Actions workflow (`.github/workflows/w1001-sentinel.yml`) runs a lower-privilege companion check (`scripts/w1001_sentinel_check.sh`) using only the project's already-public anon API key — no new privileged credential was needed or stored. A missing object now fails the scheduled run automatically, visible in the repo's Actions tab, with no further setup required from you. Verified with three real GitHub Actions runs (a healthy pass, plus two deliberate-failure simulations against fake object names — never the real production objects) — full detail in `00_09` §55. Recurrence risk itself is unchanged: it's infrastructure-level (this project has PITR disabled), so consider raising this compute tier's restart/WAL-archival behavior with Supabase support if you want to reduce it further.

---

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

**✅ DONE (2026-09-08) — backups confirmed real and running.** `GET /v1/projects/<ref>/database/backups` now shows **7 consecutive `COMPLETED` daily physical backups** (`2026-09-01` through `2026-09-07`, ~16:24 UTC each day) — a genuine, verified change from the prior "zero backups" state. `W1-001`'s deployment authorization cleared as a direct result and it has since been deployed (Step 9). **`BR-001` is now `VERIFIED_CLOSED`** (2026-09-08) — the restore-drill half was completed and independently verified (see the BR-001 Owner Checklist below for full evidence).

| | |
|---|---|
| **Why now, first** | Daily backups can take up to 24 hours to first appear after upgrading. Starting this now means the wait happens in the background while you do Steps 4-6. |
| **Action** | ~~Supabase Dashboard → upgrade to Pro~~ Done. |
| **Expected result** | Plan shows Pro or above, backups appear. ✅ Confirmed — 7 real completed backups exist. |
| **Finding closed** | `BR-001` fully — both the provisioning-existence half and the restore-drill half (see BR-001 Owner Checklist). |
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

## Step 5 — Configure emergency-workflow CI secrets — ✅ DONE, 2026-09-08

**You configured all three secrets.** Verified via the GitHub API (names/metadata only, never values) — `total_count: 3`. The emergency workflow was then triggered for real: a first run failed at a newly-discovered CI-portability bug in `scripts/generate_release_manifest.sh` (hardcoded macOS-only paths, fixed and verified locally before pushing); the second real run completed `success` end-to-end, producing a real signed, checksummed, retained Android artifact, independently re-verified at every layer (checksum, signature, package ID, versionCode, retention) rather than trusted from the workflow's own output. **`RD-009` = `VERIFIED_CLOSED`.** Full evidence: `00_09` §47.

| | |
|---|---|
| **Why now** | While already in GitHub Settings from Step 4. |
| **Action** | ~~Repository Settings → Secrets and variables → Actions. Add: `ANDROID_RELEASE_KEYSTORE_BASE64`, `ANDROID_KEY_PROPERTIES`, `EMERGENCY_BUILD_ENV_FILE`.~~ Done. |
| **Expected result** | Three secrets present. ✅ Confirmed, then successfully used to produce a real artifact. |
| **Finding closed** | `RD-009` — fully. `RD-006` (ordinary/routine-release build-number process) is also now `VERIFIED_CLOSED` — see the Release decision model below and `RD_release_rollback_runbook.md` §12. |
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
| **Finding closed** | The provisioning-existence half of `BR-001` — done. See **BR-001 Owner Checklist** below — **the restore-drill half is now also done, `BR-001` = `VERIFIED_CLOSED`** (2026-09-08). |
| **If it fails** | N/A — completed successfully. |

## Step 9 — Authorize and execute W1-001 deployment — ✅ DONE, 2026-09-08

`W1-001` was explicitly authorized and deployed to production on 2026-09-08. Migration applied via the Supabase Management API direct SQL endpoint; all 4 Edge Functions redeployed and confirmed (via source download-diff) to run the new RPC-based limiter; full smoke test, quota/concurrency/identity-isolation tests, and a real fail-closed `REVOKE`/`GRANT` production test all passed. See **W1-001 Deployment Handoff** below for the as-executed results, and `00_09` §44 for the full evidence trail. `W1-001`, `AB-002`, `SEC-005`, `AB-008` are now `VERIFIED_CLOSED`.

## Step 10 — Confirm Sentry deployed-environment event — ✅ DONE, 2026-09-09

See **OB-006 Handoff** below. `OB-006` = `VERIFIED_CLOSED`.

## Step 11 — AU-009 physical-device accessibility pass — ✅ DONE, 2026-09-10

You reported the prescribed VoiceOver (iOS) + TalkBack (Android) acceptance script — the 5 critical journeys plus the 3 required re-runs — all **PASSED**. That was this finding's own complete closure bar. `AU-009` is now `VERIFIED_CLOSED`. See **AU-009 Handoff** below for the record.

## Step 11a — AUTH-001 / AUTH-002: signup, email confirmation, and onboarding — new, 2026-09-10, PRE-LAUNCH BLOCKING

See **Authentication / Onboarding Handoff** below. This is now the most urgent remaining item — real new users cannot currently complete signup correctly.

## Step 12 — PC-006 legal/product determination

See **PC-006 Handoff** below. No technical dependency on anything above — can happen in parallel with any other step, including by someone other than whoever executes the technical steps.

## Step 13 — Fiqh Engine & AI Context remediation (new, 2026-09-09) — before Final Journey audit

See **Fiqh Engine & AI Context Handoff** below. A new, specialized, mandatory audit (`FIQH_ENGINE_ACCURACY_AUDIT_MASTER.md`) found the fiqh calculation engine itself sound (deterministic, no cross-madhhab mixing, real boundary tests) but found that none of the app's 4 AI features receive adequate awareness of the user's actual tracked state (pregnancy, cycle, fiqh classification, wellbeing, notes) — one AI feature (the General Assistant) receives none at all. Verdict: `FIQH CONDITIONAL GO`. Registered as mandatory before the Final Pre-Launch User Journey audit.

---

# Handoff packages

## GitHub Recovery Checklist

**Items 1-7 below: ✅ verified this session (2026-09-07)**, all against real GitHub infrastructure — see `00_09` §41 for the full evidence trail, including four real CI-configuration defects found and fixed along the way (a baseline-unaware `dart analyze` step, a missing placeholder `.env`, 12 platform-dependent golden-image failures, and a Gradle configuration-time signing check that blocked debug builds too). Note: `gh` itself refused to authenticate with the stored token (`error validating token: missing required scope 'read:org'`) — verification was instead done via direct GitHub REST API calls (`curl` with the same token from the git credential helper), which worked cleanly throughout. **Item 8 (a real signed emergency artifact) — ✅ done, 2026-09-08.** After you configured the three CI secrets (Step 5), the workflow was triggered again: a real signed, checksummed, retained Android artifact was produced and independently re-verified (checksum, signature, package ID, versionCode, retention). `RD-009` = `VERIFIED_CLOSED`. See `00_09` §47.

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

## BR-001 Owner Checklist — ✅ FULLY CLOSED, 2026-09-08

**Both conditions now met:**

**W1-001 authorization condition** (lighter bar) — **✅ MET** (2026-09-07/08). Already led to `W1-001`'s own successful production deployment (Step 9 above).

**Full native `BR-001` closure** (the audit's own remediation category, `BR_findings.md`) — **✅ MET.** "confirm plan tier, backup schedule, and PITR status; document the finding; **then execute a real controlled restore test to prove the mechanism actually works**." Both halves now done with real evidence.

**As executed**: you performed the Path A Dashboard "restore to new project" action (Supabase Studio → Database → Backups → selected the `2026-09-07T16:24:18Z` backup → "Restore to new project"), producing `niswah-br001-restore-drill` (ref `rpopudibfpoefejyarhe`), confirmed `ACTIVE_HEALTHY`. This session then independently verified it via the Management API — real production data confirmed intact (23 users, 43 `cycle_entries`, 6 profiles, 1 `pregnancy_profile`), schema/RLS/functions/triggers all correct, and the canonical 14-point recovery suite (`00_09` §20 Phase E) executed against this real restored data for the first time in this engagement: 12/14 full PASS, 1 correctly-expected partial (the already-known `W0-003` prayer-status bug reproduced exactly, confirming restore fidelity), 1 schema-level PASS. `RTO` is no longer `UNTESTED` — measured at ≈13 minutes (platform-availability-to-verified; exact restore-click timestamp wasn't visible to this session). All synthetic test data used during verification was removed and independently re-confirmed as zero remaining. Full evidence: `00_09` §46.

**`BR-001` = `VERIFIED_CLOSED`.**

**✅ Done — you deleted the temporary restored project directly.** Confirmed 2026-09-08 via a read-only Management API check (`rpopudibfpoefejyarhe` returns `"Resource has been removed"`, absent from the org's project list). No cleanup action remains for `BR-001`.

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

## OB-006 Handoff — ✅ COMPLETE, 2026-09-09 (OB-006 Owner Confirmation wave)

**Native closure bar** (`OB_remediation_plan.md` R2-1's own retest text): a test/staging-environment event confirmed to "appear in **the chosen tool**" — meaning visible server-side in Sentry itself, not just a local SDK call returning a non-empty event id.

**You completed this directly**: opened the Sentry dashboard and confirmed the staging verification event genuinely exists server-side. Observed evidence: Sentry issue `FLUTTER-2`, an intentional Niswah reliability/staging verification event, event ID beginning `10b520e6...` (matching `10b520e6ed994f709d6af61461c8ea93`, the id this engagement's own prior wave generated), `environment: staging`, event count `1` — visibly present in Sentry, not merely accepted locally by the SDK.

**`OB-006` = `VERIFIED_CLOSED`.** No Sentry integration code was touched to reach this closure — the existing, already-correct integration (re-verified unchanged across two prior waves) is what produced the event you just confirmed.

**Do not conflate with `RR-002`** — `RR-002` (systematic error-reporting coverage) was already `VERIFIED_CLOSED` independently; `OB-006` was specifically about confirming *server-side delivery*, now also closed on its own terms.

## DC-010 Handoff — `OWNER_BLOCKED`, re-confirmed 2026-09-08 (DC-010 iOS Production Signing wave)

**Native closure bar** (`DC_findings.md`/`DC_remediation_plan.md` R1.5, read directly): a real, pinned `DEVELOPMENT_TEAM`, an Xcode Archive, an exported IPA, and confirmation the signing identity is a genuine Apple **Distribution** certificate — not ad hoc, not development, not the current generic `"iPhone Developer"` placeholder. Genuinely higher than `RD-006`'s bar (which an unsigned build could satisfy); this one cannot be simulated.

**Re-checked this wave, definitively**: `security find-identity -v -p codesigning` → `0 valid identities found`; `~/Library/MobileDevice/Provisioning Profiles/` doesn't exist; no `DEVELOPMENT_TEAM` key anywhere in `project.pbxproj`; `xcodebuild -showBuildSettings` resolves `EXPANDED_CODE_SIGN_IDENTITY`/`EXPANDED_PROVISIONING_PROFILE` both empty; **Xcode itself has no Apple ID of any kind signed in** on this machine (`defaults read com.apple.dt.Xcode IDEProvisioningTeams` → key doesn't exist at all — not even a free, non-Program account). This is not a missing-Team-selection gap alone; there is no Apple account present to select a Team from.

Sequence, confirmed sufficient by this engagement's own iOS Release Readiness wave (`00_09` §38) — every other release-readiness item (bundle ID, entitlements, deployment target, permissions, export-compliance flag, privacy manifests) is already verified and unaffected:

1. Xcode → sign in with an Apple ID enrolled in the Apple Developer Program (Xcode → Settings → Accounts).
2. `Runner` target → Signing & Capabilities → select that Team. `CODE_SIGN_STYLE = Automatic` is already correctly configured — Xcode generates the certificate and provisioning profile itself once a Team is selected. No separate manual certificate/profile creation step is needed for a first release.
3. Produce a real signed build: `flutter build ipa --release --dart-define=APP_ENV=production` (or Archive via Xcode directly).
4. Validate: `codesign -dvvv build/ios/ipa/*.ipa` (or the `.app` inside it) — expect a real Distribution certificate `Authority=` line, not "not signed at all."

**Closure evidence required**: a real, distributable `.ipa`, signed with a genuine Apple Distribution certificate (not `--no-codesign`), confirmed via `codesign -dvvv`. App Store submission itself (metadata, screenshots, review) is separately out of scope for `DC-010`'s own closure — this finding is about signing infrastructure, not the submission process. Once you've completed steps 1-2 above, this session can pick up from Phase D (recheck signing) through the rest of the original charter — reply once the Team is selected in Xcode.

## AU-009 Handoff — ✅ VERIFIED_CLOSED, 2026-09-10 (owner-reported live acceptance)

**You reported that every journey below PASSED on both iOS VoiceOver and Android TalkBack.** That is this finding's own complete closure bar — nothing further is needed. The script below is kept as a record of what was tested, and is reusable if you ever want to spot-check accessibility again after a future change.

**🟡 Update, 2026-09-10 (AU-009 Acceptance wave) — everything possible without you has been done; this is now the minimum remaining action.** The native closure bar for `AU-009` (`AU_remediation_plan.md`'s own R7) requires live VoiceOver + TalkBack testing for at minimum 5 critical journeys, plus 3 specific re-runs — not a full screen-by-screen sweep. This wave re-ran every existing automated accessibility test (all still passing), added a new test that actually *measures* a touch target on the real rendered widget tree rather than trusting source comments, confirmed the app never uses a custom traversal-order override anywhere, and found and fixed one new real defect (`AU-014`: loading spinners had no screen-reader announcement at all — fixed for the sign-in/sign-up screen specifically, the one critical journey it affects). **None of this substitutes for actually turning on VoiceOver/TalkBack and using the app** — that step needs a human, and only a human, per `AU-009`'s own closure bar. iOS Simulators exist on the machine this session ran on, but there is no tooling available to this session to actually drive VoiceOver's gestures or hear its spoken output — simulator *existing* is not the same as being able to *test* on it.

**✅ Update, 2026-09-10 — `AU-014` (loading-state accessibility) is now fully fixed app-wide, not just for sign-in.** Every genuine loading/saving/sending state across the app (22 instances across 16 files) now announces a real, localized message when you turn on VoiceOver/TalkBack (e.g. "Loading messages", "Saving", "Deleting account" — each in context, in both English and Arabic). One extra real bug was found and fixed in the process: the Community board's loading state previously announced nothing at all while it loaded. **The test script below is unchanged** — no journey, step, or wording in it depended on this fix; you may simply notice that loading moments now say something sensible if you listen for them during journeys 3-5.

**How to test — 10 minutes, no source code or settings screens to inspect, just use the app:**

### iOS — VoiceOver
1. Settings → Accessibility → VoiceOver → On (or triple-click the side button if you've set that shortcut).
2. Swipe right/left to move between items, double-tap to activate, use the rotor (twist two fingers) if you need it.

### Android — TalkBack
1. Settings → Accessibility → TalkBack → On.
2. Swipe right/left to move between items, double-tap to activate.

**For each journey below, answer PASS or FAIL** on **both** iOS and Android. If FAIL, note which step and what happened (e.g. "the save button had no label, it just said 'button'").

| # | Journey | What to do | PASS means |
|---|---|---|---|
| 1 | Sign up / log in | Turn on the screen reader, open the app fresh, create an account or log in fully using only swipes and double-taps | Every field and button is understandable when read aloud; you can complete the whole flow without looking |
| 2 | Onboarding | Complete the onboarding steps (madhhab, married, location, period info, privacy) with the screen reader on | Every choice/option is announced clearly enough to pick correctly; your current selection is announced (e.g. "Hanafi, selected") |
| 3 | Dashboard | Land on the home dashboard, swipe through the cycle status area and quick actions | You can tell what your current cycle/fiqh state is from what's read aloud, not just from color/shape on screen |
| 4 | Log a cycle/period entry | Open the log-entry sheet, set flow and at least one symptom, close it | The close button, flow options, and symptom chips are all understandable and operable; the symptom's severity level is announced when you select it |
| 5 | Community — post/like/comment | Open Community, like a post, open the comment box, type and submit a comment | Like/comment/share buttons are understandable (not just "button"); any error message is actually read aloud, not only shown visually |
| 3-again | Dashboard at large text | In your phone's own display settings, set text size to the largest (or near-largest) option, then repeat journey 3 | Nothing is cut off, overlapping, or unreadable at large text size |
| 4-again | Log entry at large text | With text size still large, repeat journey 4 | Same — nothing clipped or overlapping |
| — | Arabic | Switch the app's language to Arabic (in-app language toggle) and repeat journey 3 (dashboard) once | Text and layout flow right-to-left correctly; nothing is misaligned |

**Also confirm, wherever it comes up naturally in the journeys above** — no separate test needed for these, just notice while you're going through the list:
- You can navigate the whole journey without looking at the screen.
- Every button/control says something meaningful, not just "button" or silence.
- The order things get read in makes sense (top-to-bottom, matching what you'd expect).
- If something is currently selected/checked, that's announced (e.g. a checkbox says "checked").
- Every text field has a label you can hear before you start typing into it.
- If you make a mistake, the error is read aloud, not just shown as text/color on screen.
- Any popup/dialog (like a confirmation) automatically gets your screen reader's attention — you don't have to hunt for it.
- Any delete/remove action clearly says what it will do before you confirm it (e.g. "Delete account — this cannot be undone", not just "Delete").
- Nothing ever leaves you stuck with no way forward using only the screen reader.

**Record your results** (PASS/FAIL per journey per platform, plus any FAIL notes) and share them back — if everything passes, `AU-009` closes. If anything fails, tell us which journey/step and we'll fix and ask you to re-test just that one journey, not the whole list again.

## Authentication / Onboarding Handoff (new, 2026-09-10) — `AUTH-001` / `AUTH-002`, PRE-LAUNCH BLOCKING

Your acceptance testing found two real, launch-blocking defects when signing up with a genuinely new email: the confirmation email looked like a generic Supabase email and redirected to an old Vercel link instead of the app, and after confirming, the app skipped onboarding entirely as if you were a returning user. Both are now root-caused with hard evidence, and the onboarding-skip is fully fixed in code. The confirmation-redirect fix is ready but needs your authorization (it changes production authentication configuration, which this session will never touch without you saying so explicitly).

### What's already fixed (no action needed)

**The onboarding-skip bug (`AUTH-002`) is fixed.** The app used to decide "new vs. returning user" from a flag that only lived in memory for the current app session — for a real signup that requires email confirmation (which yours does), that flag was never being set at all, so a freshly-confirmed user looked identical to a returning one. The app now checks a real, durable, server-side "have you finished onboarding?" record every time you sign in, instead of guessing. Verified against production with real test accounts, including confirming one account can never see or change another's onboarding status, and re-tested on a real rebuilt device install (not just against the backend directly) once this specific fix was included in the build.

**`AUTH-004` update: your own on-device test found it still failing — this remains an open, launch-blocking item.** You tried the "Anonymous Mode" toggle for real and got "Unable to update your profile right now." This session traced the cause again from scratch and could not make it fail on a freshly-rebuilt copy of the app — every attempt on a fresh build succeeded and stayed saved, including after fully restarting the app. **The most likely explanation: the copy of the app you tested on was built before this fix landed** — there's currently no automatic way to get a fresh build onto your device (that's the same `DC-010` limitation), so testing requires a fresh manual rebuild each time, which is easy to skip. **Please rebuild/reinstall the app from the latest code before trying again.** A smaller, separate robustness gap was also found and fixed (rapid double-tapping the toggle could send two conflicting requests) — unrelated to the failure you saw, but worth having fixed regardless. This item stays open until you confirm a PASS on a confirmed-fresh build.

**One related item found and tracked (not fixed this pass, not launch-blocking on its own):**
- **`AUTH-003`** — if someone closes the app partway through onboarding, it safely starts over from the beginning next time (never skips ahead to the dashboard, never loses her answers) — it just doesn't resume at the exact step she left off on. Accepted as-is; restarting safely is what actually matters.

**Also found and fixed along the way**: signing in with "Continue with Google" had the same underlying redirect problem as the confirmation-email issue below — it would also have landed on the old Vercel address instead of returning to the app. Fixed in the same code change; it needs the same one-time Supabase configuration change below to fully take effect.

### What needs your authorization — the confirmation-email fix (`AUTH-001`)

**Exact cause found**: your Supabase project's authentication settings still point at an old Vercel web-preview address (`https://niswah.vercel.app`) as the destination for confirmation links, instead of the app itself. The app has already correctly asked for `niswah://login-callback` (which opens Niswah directly) for a while now — but that address was never added to Supabase's list of allowed redirect destinations, so Supabase quietly falls back to the old Vercel address instead. This is exactly what you saw.

**Proposed fix** (nothing has been changed yet):

| Setting | Change to |
|---|---|
| Site URL | `niswah://login-callback` |
| Allowed Redirect URLs | add `niswah://login-callback` (your existing Vercel entries stay — those are for the separate web reference site, not related to this) |

**To authorize**: just say so explicitly (e.g. "yes, apply the AUTH-001 Supabase Auth config change") and this session will make exactly those two changes and re-verify with a real test signup — nothing else in your Supabase project will be touched.

**Also recommended, same authorization**: replace the confirmation email's generic "Confirm your email address" wording with real Niswah branding. This can be done at the same time.

**One more thing found along the way, not blocking launch but worth knowing**: your Supabase project is currently using its own free built-in email sender, which has a strict sending limit — a real test signup during this session's own testing already hit that limit (`HTTP 429`, "email rate limit exceeded"). This means some real users' confirmation emails could silently fail to send once you have more than a handful of signups per hour. Fixing this requires setting up your own email-sending service (e.g. Resend, Postmark, SendGrid, or similar) and entering its credentials directly into the Supabase Dashboard's Authentication → SMTP Settings — this session will never see or handle that password, so this step can only be done by you, whenever convenient. It is not required to unblock the redirect fix above, but it should happen before a real public launch.

### Minimal acceptance test, once the Auth config change is authorized and applied

No code, tables, or logs to inspect — just this:

1. Sign up with a real, brand-new email address you can check.
2. Confirm the email looks like it's from Niswah (not generic).
3. Tap the confirmation link.
4. Confirm it opens Niswah itself, not a browser/old website.
5. Confirm onboarding appears (madhhab, married, location, period questions).
6. Complete onboarding.
7. Log out, then log back in with that same account.
8. Confirm you land on the dashboard, not onboarding again.
9. In Profile Settings, turn on "Anonymous Mode," then close and reopen the app. Confirm it's still on (this is the `AUTH-004` fix — previously it would have silently turned back off).

Report PASS/FAIL — if anything fails, note which step.

## PC-006 Handoff

**Technical implementation already complete**: the data-export architecture was redesigned (per-section, resilient to partial failure — a real live bug was found and fixed in this process), and the export correctly includes/excludes data categories per the current, technically-accurate understanding of what the app stores.

**Exact legal question requiring owner/counsel decision** (not answerable by this engagement, and not attempted): whether the current data-export scope and retention behavior satisfy the specific legal obligations that apply to Niswah's actual user base and jurisdiction(s) — e.g., GDPR/CCPA-equivalent "right to erasure"/"right to portability" completeness, and whether a defined retention *period* (not just a mechanism) is legally required for health/religious-practice data in the relevant jurisdictions. This engagement has deliberately never asserted a specific legal conclusion or invented a retention period — that determination belongs to counsel.

**What would need to change only if the determination differs from current behavior**: if counsel determines a specific retention period is legally required, that would need a new, explicit deletion-scheduling mechanism (does not exist today — correctly not invented without a real requirement to build against). If counsel determines additional data categories must be exportable/deletable, the already-redesigned per-section export architecture can be extended without a full redesign. **No engineering work is being reopened speculatively** — only exactly what counsel's determination requires, once known.

## Fiqh Engine & AI Context Handoff (new, 2026-09-09)

Full evidence: `production-readiness-results/fiqh-engine/FIQH_AICTX_discovery.md`, `FIQH_AICTX_findings.md`, `golden_fiqh_dataset.json`. Charter: `production-readiness/MDs/FIQH_ENGINE_ACCURACY_AUDIT_MASTER.md`.

**The fiqh calculation engine itself is sound**: deterministic, no cross-madhhab mixing, real pre-existing and newly-added boundary-test coverage (22 total boundary-relevant test assertions, all passing against real code). Zero `FIQH-0` findings — no evidence of a materially incorrect worship ruling reachable by a real user. One safe fix was made this pass: a dead, unreachable, duplicate fiqh calculator containing an unsourced approximation was found and removed.

**The real gap is AI user-state context**: none of the app's 4 AI features (Dr Niswah, the General Assistant, the Fiqh Advisor, the Dream Interpreter) has a shared, structured awareness of the user's actual current state. The General Assistant receives **zero** context of any kind — not even a database query. Dr Niswah only knows pregnancy status. The Fiqh Advisor only knows the selected madhhab. A real, existing wellbeing-tracking feature (mood/energy/sleep) and existing user notes are never read by any AI at all, even though both are already retrievable elsewhere in the app for other purposes. Zero `AICTX-0` findings — no cross-user data leakage, and every AI feature's prompt-level design already correctly declines to override the deterministic fiqh engine or assert certainty with missing facts. But 7 open `AICTX-1`/`AICTX-2` findings document a genuine, systemic product gap.

**✅ Update, 2026-09-09 — the AI User-State Context Layer is built, deployed, and now live-verified with real Gemini traffic.** One shared module (`supabase/functions/_shared/ai_user_context.ts`) feeds all 4 AI features pregnancy, cycle, wellbeing, symptoms, and notes context (scoped per feature — never the whole database to every AI). Real, production Gemini replies (not just unit tests) directly confirmed: Dr Niswah and the General Assistant both correctly cite pregnancy week/trimester, cycle/bleeding state, symptoms, and user notes (merged from both `cycle_entries` and `wellbeing_logs`) in the same coherent reply; a red-flag message correctly escalates alongside pregnancy context; changing state (mood, notes, pregnancy week) is immediately reflected in the next reply with zero caching; two AI features independently agreed on the same pregnancy week at the same moment. The Fiqh Advisor's context assembly runs correctly (no error) but a separate, pre-existing Google-Search-grounding issue (unrelated to this work) currently blocks it from composing a substantive answer — see below. The Dream Interpreter's context assembly also runs correctly; its own prompt deliberately uses context only implicitly, by design. Full evidence: `production-readiness-results/fiqh-engine/FIQH_AICTX_findings.md`'s "AICTX-13 Production Application & Live AI-Context Verification wave" section and `00_09` §57.

**✅ Update, 2026-09-09 — `AICTX-13` (wellbeing check-ins silently failing) is fixed, applied to production, and live-verified.** Production's `wellbeing_logs` table was missing a `notes` column that the app always tried to write, so every real wellbeing check-in was failing — root-caused to a migration authored back on 2026-08-27 that was simply never applied to production, unlike its sibling table-creating migration two days earlier. You authorized the migration (`supabase/migrations/20260909100000_wellbeing_logs_notes.sql`, checksum `c90bdba720211f7f62e6b78fceff19903e69ec53e76adeb19304b66038d92fc7`); it was applied and every object independently re-verified (column type/nullability, 31 pre-existing rows unaffected, RLS/indexes/constraints unchanged). All 4 AI Edge Functions redeployed. A full live CRUD + cross-user-isolation battery was re-proven directly against production with synthetic accounts (all cleaned up afterward) — wellbeing check-ins with and without notes, edits, and clears all now work correctly.

**✅ Update, 2026-09-09 — Fiqh Advisor's grounding failure is now root-caused with certainty (Source Governance wave).** It's a **billing/quota issue on your Google Cloud / AI Studio account**, not a bug in this app: the Gemini API's own error, captured via new diagnostic logging (added and deployed this wave, does not weaken the existing safe fallback), reads *"You exceeded your current quota, please check your plan and billing details"* — specific to the Google Search grounding tool this one feature uses (the other 3 AI features, which don't request grounding, are unaffected). **This requires your action**: check that project's Gemini API billing/quota in Google Cloud Console or AI Studio and raise the grounding-tool quota. Until then, Fiqh Advisor will keep giving its safe "cannot rule without sources, ask a qualified scholar" fallback rather than a real answer — which is the correct behavior for it to have while this is unresolved, not a bug to route around.

**✅ Update, 2026-09-09 — a draft source-governance layer now exists, entirely unreviewed and clearly labeled as such.** We compiled a first-pass source hierarchy (which classical/contemporary reference works commonly ground each madhhab's rules), a jurisdiction registry (national fatwa institutions), and a geographic "commonly followed in your region" madhhab-suggestion mapping — all in `production-readiness-results/fiqh-engine/`. **None of it is scholar-approved.** Every entry is explicitly labeled `NOT_REVIEWED`/`AI_RECALLED_UNVERIFIED`, and nothing was fabricated at the specific-citation level (we named real, well-known books/institutions but did not invent page numbers we couldn't verify). We also built (but did not wire into the live onboarding screen — that needs a UX decision, see below) a tested "I don't know my madhhab" suggestion engine that follows your charter's rules exactly: it never declares a madhhab, only suggests one with confirmation required, and a phone number's country code is never treated as proof of anything.

**✅ Update, 2026-09-09 — live adversarial testing of the AI authority boundaries (`AICTX-9`) passed.** We directly tried, in production, to get the AI to: confirm a user was "pure" and could pray despite her tracked bleeding state, treat "I live in Turkey" as an official madhhab change, and give a definitive haid/tahara answer under direct pressure with no classification supplied. **In every case it correctly refused and deferred to a qualified scholar or to your own app settings.** A fourth attempt (asking Fiqh Advisor to quote a deliberately made-up book) couldn't be fully tested because of the same grounding/billing block above.

**Three things still need you**:
1. ~~Resolve the urgent `W1-001` regression~~ — done, see the 🟢 RESOLVED banner above.
2. **Fix the Fiqh Advisor grounding billing/quota issue** described above — the single highest-leverage remaining item for the AI layer.
3. **Qualified Islamic scholar/domain review** — genuinely outside this engagement's engineering capability. A single reviewer-friendly package (no code-reading required) is ready for whoever you choose: `production-readiness-results/fiqh-engine/SCHOLAR_REVIEW_PACKAGE.md`. Every fiqh boundary value, the source hierarchy, the geographic mapping, the golden test dataset, and all user-facing religious wording remain `NOT_REVIEWED`. This is explicitly not something an engineering pass can substitute for or claim on your behalf.

**Verdict for this audit: `FIQH CONDITIONAL GO`, unchanged.** The AI context layer is live-verified for 3 of 4 AI features with real Gemini evidence; the 4th (Fiqh Advisor) is architecturally verified and its blocker is now precisely understood, pending your billing action. Registered as mandatory before the Final Pre-Launch User Journey audit.

## Fiqh Grounding Degradation — Classification

**Current behavior, confirmed and unchanged across every wave that checked it**: when Google's Search-grounding quota/billing condition triggers, the app fails safely — no silent ungrounded religious answer is ever produced; the degraded state is visible and handled, not hidden.

**Classification: CONDITIONAL-GO limitation, not a launch blocker.** The native finding's own risk model is specifically about the *danger of an ungrounded fiqh answer appearing grounded* — that risk is structurally closed by the fail-safe behavior, independent of whether the underlying Google Cloud quota is ever resolved. Resolving the quota/billing condition improves *service quality* (fewer degraded responses), not *safety* (which is already assured). **Do not require billing spend to reach GO** — this is accurately a deferred service-quality item, appropriately owner-discretionary, not gating.

---

## Madhhab Authority Handoff (new, 2026-09-14, Fiqh Remediation Wave 1) — `AUTH-005` / `AUTH-010`, `E3`/`E2` DONE, `E4` NEEDS YOU

**What changed**: your madhhab selection is now genuinely durable — it lives on the server (`public.users`), not only on your phone — and the exact spot that used to silently assume "Hanbali" whenever nothing was saved has been removed everywhere it was found, including a spot inside the database itself (the signup trigger) that had been doing this for every new account since the column existed. Separately, onboarding's Madhhab question now has a real 5th option — "I don't know my Madhhab" — with a calm explanation, a genuine confirmation-gated suggestion (asks your country, suggests a likely school, saves nothing until you explicitly say yes), and an "I'll decide later" path that's remembered as its own real state, never silently turned into a guess. You can also change your madhhab later from Settings, including switching to "I don't know."

**Why this needed a real database change, not just an app update**: your production database had `madhhab` as a required text column defaulting to `'HANBALI'` for every new signup — that default was never a real choice, just an unused placeholder nobody had gotten around to removing. A new migration adds a proper `madhhab_selection_state` column (`unset`/`unknown`/`selected`) and makes `madhhab` itself optional, so "nobody has answered yet" and "she said she doesn't know" can each be recorded honestly, never collapsed into "Hanbali" or into each other. **One thing found and fixed along the way, not anticipated going in**: your database already had a second, undocumented rule left over from earlier development requiring `madhhab` to be one of 4 *UPPERCASE* values, which would have silently rejected every real save the app makes (which uses lowercase) — found and removed during this session's own verification, before it could cause a real failure for a real user.

**Existing users**: nobody's madhhab was quietly assumed to be anything — every existing account was set to "not yet answered," the same honest state a brand-new user starts in, rather than guessing Hanbali (or anything else) for people who'd never actually said so.

**Evidence so far (this session's own testing, no device access in this environment)**: 39 new automated checks walk through the entire new onboarding flow in both English and Arabic (all 5 choices visible, the "I don't know" explanation, the country-suggestion flow, confirming or declining a suggestion, and the plain "decide later" path) — all passing. 10 more checks prove the underlying save/restore logic never falls back to a guessed madhhab under any condition tested, including a simulated "phone wiped, nothing saved anywhere" scenario. Beyond the automated tests, this session also directly verified the real production database: read back the new columns and rules exactly as applied, and proved (inside a test transaction that was undone immediately afterward, touching no real account) that a real save using the exact values the app sends actually works end-to-end.

**What this session could not do**: actually run the app on a phone or simulator — no device access in this environment. Everything above is strong automated + direct-database evidence, but per this finding's own closure rule (agreed earlier today), it cannot close without you trying it yourself on a real device.

**Your test, once you have a moment** (about 5 minutes):

1. **The "I don't know" path**: Start onboarding fresh (or go to Settings → Fiqh Madhhab if you're already set up). Confirm you see 5 options, including "I don't know my Madhhab." Tap it — confirm you see a calm explanation, not pressure to pick something. Try "Help me choose" — type a country (e.g. "Saudi Arabia"), confirm you see a suggestion with a clear "Yes, this is my Madhhab" button, and confirm it does NOT save anything until you actually tap that button. Go back and instead try "I'll decide later" — confirm onboarding continues normally without forcing a pick.
2. **Reinstall persistence** (the core of `AUTH-005`): Pick a real school (e.g. Shafi'i), finish onboarding, and use the app normally for a moment. Fully delete the app, reinstall it, and sign back in. Confirm your dashboard shows Shafi'i again — not Hanbali, not a re-ask — restored from the server.
3. **"I don't know" survives reinstall too**: Repeat step 2, but this time pick "I'll decide later" instead of a real school. After reinstalling and signing back in, confirm the app remembers you said "I don't know" — it should not silently become Hanbali, and it should not ask you to choose all over again as if you'd never answered.
4. **Changing your mind later**: In Settings, change your Madhhab to a different school. Confirm the dashboard's Fiqh status updates to match the new school, not the old one.

Report PASS/FAIL for each of the 4 items — if anything fails, note exactly which step and what you saw. If all 4 pass, `AUTH-005` and `AUTH-010` both close as `VERIFIED_CLOSED / E4`.

---

# Release decision model

**NO-GO**: any of — no verified production data backup exists (`BR-001` unresolved), an exposed credential remains unrotated (both `cli_login_postgres` and the Gemini key are now rotated/revoked and verified — this gate has cleared), a critical safety/recovery/consent control is confirmed broken (none currently — all such findings are closed or narrowed to non-safety gaps).

**CONDITIONAL GO**: all critical safety/recovery/credential gates are closed (`BR-001` real backup confirmed, both credentials rotated, `W1-001` deployed and verified if desired for launch), and only accepted, owner-documented, non-critical items remain open — e.g. `AU-009` scheduled but not yet run, `PC-006` pending counsel with current behavior already legally-neutral (no false claims, no invented retention), Fiqh grounding degraded-but-safe, iOS not yet submitted to the App Store (if Android-first launch is an accepted owner choice).

**GO**: every mandatory launch gate is closed with real evidence — `BR-001` fully closed (including the restore drill, not just existence), both credential rotations verified, `W1-001` deployed and its own closure criteria met, `AU-009` executed with a passing result, `PC-006` resolved by counsel with any resulting engineering work complete, `OB-006` confirmed via a real deployed-build event, `DC-010` producing a real signed, distributable iOS build (App Store submission itself can still follow GO, not gate it).

**Current state, as of 2026-09-08**: **NO-GO**, but every mandatory *technical* safety/recovery/credential gate is now closed. Both standing credential exposures are resolved and verified (`cli_login_postgres` rotated via the Management API; the Gemini key rotated, redeployed, and confirmed working in production both before and after old-key revocation). `W1-001` — a major, long-tracked finding, along with the three findings that depended on its production deployment (`AB-002`, `SEC-005`, `AB-008`) — is **`VERIFIED_CLOSED`**: deployed to production on 2026-09-08 and independently re-verified with real, direct evidence at every layer (migration application, DB object correctness, Edge Function redeployment, functional smoke tests, atomic concurrency behavior under real load, identity isolation, and a real, reversible fail-closed production fault-injection test — see `00_09` §44). **`BR-001` — the engagement's original BR0-critical finding, open since the very first audit pass — is now also `VERIFIED_CLOSED`** (2026-09-08): you restored a real, `COMPLETED` physical production backup into an isolated project via the Supabase Dashboard, and this session independently proved the recovery mechanism actually works — real restored production data (23 users, 43 `cycle_entries`, etc.), full schema/RLS/function/trigger integrity, and the canonical 14-point behavioral recovery suite passing against that real data (12/14 full PASS, 1 correctly-expected partial reproducing the already-known `W0-003`, 1 schema-level PASS). `RTO` is no longer `UNTESTED` — measured at ≈13 minutes. See `00_09` §46 and the **BR-001 Owner Checklist** above for full evidence. `RD-009` — the engagement's rollback/rapid-recovery finding — is now also **`VERIFIED_CLOSED`** (2026-09-08): after you configured the three emergency-workflow CI secrets, a real signed, checksummed, retained Android artifact was produced on live GitHub Actions infrastructure and independently re-verified at every layer (checksum, signature, real `CN=Niswah` certificate, correct `com.niswah.niswah` package ID, `versionCode=5`, 90-day retention) — not merely trusted from the workflow's own output. One genuine CI-portability bug was found and fixed along the way (`scripts/generate_release_manifest.sh`). See `00_09` §47. **`RD-006` — the ordinary/routine-release build-number process — is now also `VERIFIED_CLOSED`** (2026-09-08): a new, manually-triggered `.github/workflows/routine-release.yml` computes its own build number automatically (`100 + github.run_number`, a real GitHub-native monotonic counter, collision-proof by construction against the emergency workflow's small operator-chosen numbers), proven with two real sequential runs on live GitHub Actions — `build_number=101` then `102`, both independently re-verified on both a real signed Android artifact and a real (correctly unsigned) iOS artifact, with `102 > 101 > 5` (the highest value any prior mechanism in this engagement ever produced). No store publication occurred. `DC-010` was deliberately not touched — RD-006's own native closure bar (read directly from source) never required real Apple signing, only a verifiably correct, incrementing version number. See `RD_release_rollback_runbook.md` §12 and `00_09` §48. **The `BR-001` restored-project cleanup is complete** — you deleted `niswah-br001-restore-drill`/`rpopudibfpoefejyarhe` directly; confirmed 2026-09-08 via a read-only Management API check. It is no longer a standing item on any list.

**`DC-010` investigated (2026-09-08, DC-010 iOS Production Signing wave)**: its native closure bar (read directly from `DC_findings.md`/`DC_remediation_plan.md` R1.5) is genuinely higher than `RD-006`'s — it requires a real `DEVELOPMENT_TEAM`, an Xcode Archive, an exported IPA, and confirmation of a real **Distribution** certificate (not ad hoc/development), so it cannot be satisfied by an unsigned build the way `RD-006` could. Checked directly: `security find-identity -v -p codesigning` → `0 valid identities found`; no provisioning profiles directory; no `DEVELOPMENT_TEAM` anywhere in `project.pbxproj`; `xcodebuild -showBuildSettings` resolves `EXPANDED_CODE_SIGN_IDENTITY`/`EXPANDED_PROVISIONING_PROFILE` both empty; **Xcode has no Apple ID of any kind signed in on this machine** (`IDEProvisioningTeams` preference key doesn't exist at all). This session cannot supply an Apple Developer Team, certificate, or provisioning profile — see **DC-010 Handoff** below for the exact 4-step owner action. `DC-010` remains `OWNER_BLOCKED` — genuinely, not from lack of trying.

**`OB-006` is now also `VERIFIED_CLOSED`** (2026-09-09, OB-006 Owner Confirmation wave): you opened the Sentry dashboard directly and confirmed the staging verification event genuinely exists server-side — Sentry issue `FLUTTER-2`, event ID beginning `10b520e6...`, `environment: staging`, event count `1`, visibly present in Sentry itself, not merely accepted locally by the SDK. This is exactly `OB-006`'s own native closure bar ("appears in the chosen tool"), now directly satisfied. See the **OB-006 Handoff** above and `00_09` §51 for full evidence.

**What still holds the verdict at NO-GO**: every remaining item (`DC-010`, `PC-006`, and now `AUTH-001`/`AUTH-002`) is independently owner/external/platform/legal-gated, unrelated to backup/recovery/credential/rate-limiting/rollback/release/observability safety. **Practically**: with `BR-001`, `RD-009`, `RD-006`, `OB-006`, and now `AU-009` all closed and the restore-project cleanup complete, this engagement has no remaining BR0/RD1/OB1/AU1-critical technical finding open anywhere and no lingering cleanup items. **See the 2026-09-14 update further below for the current, corrected state of the remaining blocker list** — `AUTH-007`/`AUTH-008`/`AUTH-009` have since closed on a real owner fresh-install E4 retest; this paragraph is left as historical context, not current status.

**🔴 Update, 2026-09-10 (Critical Auth/Signup Lifecycle wave) — two new pre-launch-blocking findings, `AUTH-001`/`AUTH-002`, found via your own acceptance testing.** `AUTH-002` (a genuinely new, confirmed user skipped onboarding) is fully fixed in code and verified with real production test accounts. `AUTH-001` (confirmation email showed default branding and redirected to a stale Vercel URL) is root-caused precisely, with the exact fix prepared — but requires your explicit authorization before this session touches production authentication configuration, exactly as every other production change in this engagement has required. See the **Authentication / Onboarding Handoff** section above for the full detail and the minimal owner action.

**🟢 Update, 2026-09-10 — `AU-009` is now `VERIFIED_CLOSED`.** You reported the prescribed VoiceOver/TalkBack acceptance script passed in full. Everything left is `DC-010`/`PC-006`/`AUTH-001`/`AUTH-002`, each independently gated on your action, external platform access, or counsel, not on further engineering or verification work — except `AUTH-001`, which is ready the moment you authorize it.

**A new specialized audit was added and run (2026-09-09): Fiqh Engine Accuracy & AI User-State Context.** Verdict `FIQH CONDITIONAL GO`, unchanged across three follow-on waves — the fiqh calculation engine itself is sound and deterministic with zero `FIQH-0` findings; the AI context layer is now live-verified end-to-end with real Gemini evidence for 3 of 4 AI features; the 4th's grounding blocker is now precisely root-caused (a billing/quota action on your Google Cloud account); a draft (entirely unreviewed) source-governance layer and a reviewer-ready scholar package now exist. See **Fiqh Engine & AI Context Handoff** above.

**🟢 Update, 2026-09-09: `W1-001`, `AB-002`, `SEC-005`, and `AB-008` regressed in production for a window on 2026-09-08/09, and were re-remediated and confirmed `VERIFIED_CLOSED` again the same day.** The rate-limiter database objects those findings' closure depended on had gone missing from production, causing all 4 AI features to return `503` to every real user; the same, unchanged, previously-verified migration was re-applied and every object plus live service and rate-limiter behavior were independently re-verified. See the 🟢 RESOLVED banner at the top of this document and `00_09` §54 for full detail, including the root-cause investigation and the new detection script.

**🟢 Update, 2026-09-11 (Wave 1 Final Blocker Remediation) — `AUTH-004` root-caused and fixed in code.** The "Anonymous Mode" privacy toggle (Profile Settings + onboarding's privacy step) was silently failing to save every time, in production, since it was built — traced to its exact historical cause (a migration written to add the needed database columns, but never actually applied) and fixed by pointing the app at a column that was already there all along. Re-verified directly against your live database with a temporary test account (deleted afterward), including confirming one account can never see or change another's setting. A related bug in "Continue with Google" sign-in (same redirect problem as `AUTH-001`) was also found and fixed in the same pass.

**🔴 Update, 2026-09-11 (same day) — your own real-device test of `AUTH-004` came back FAIL.** You tried the toggle for real and saw "Unable to update your profile right now." This session re-investigated from scratch on a freshly-rebuilt copy of the app and could not reproduce a failure — every attempt succeeded and survived a full app restart. Leading theory, not confirmed: the copy you tested on predated this fix (no automatic way to get a fresh build to your device exists yet, the same limitation as `DC-010`). **Please rebuild/reinstall from the latest code and try again** — see the updated **Authentication / Onboarding Handoff** section above. `AUTH-004` stays open until your retest passes.

**🔴 Update, 2026-09-11 (later the same day) — your retry with a fresh build hit a different problem: an almost completely blank screen instead of the Profile page.** This was tracked as its own new item, `RR-009`. Initial investigation that same day could not reproduce it.

**🟢 Update, 2026-09-12 — `RR-009` is now found and fixed.** A second report from you (a blank screen partway through the very first onboarding steps, right after choosing a language) turned out to be the same underlying bug, just caught on a different screen than the first report — the two were connected once this one was actually reproduced. The real cause: one specific onboarding screen (the sign-in step) was built in a way that conflicted with how onboarding wraps each step for its slide/fade animation — under a very particular combination of circumstances, that clash made the screen render as blank instead of showing its real content. It's now fixed at the actual source, verified by directly reproducing the real crash on a test device, confirming the fix resolves it, and adding 18 new automated checks — including one that walks through every single onboarding step and would fail if any of them ever went blank again, which is exactly the kind of check that would have caught this earlier. `AUTH-004` is no longer blocked — you should now be able to get all the way through onboarding without hitting a blank screen.

**🟢 Update, 2026-09-12 (same day) — you completed the full retest on iOS and both items PASSED.** You confirmed: onboarding now goes through the language step, sign-in, and every other step cleanly with no blank screens, all the way to your dashboard — and separately, the "Anonymous Mode" toggle now saves for real, shows no error, and stays saved both after fully restarting the app and after logging out and back in. Both `RR-009` and `AUTH-004` are now fully closed based on your own real test, on the exact code currently in the repository (commit `72204b28eca759509230318184caf79d8da3c282`). **What holds the verdict at NO-GO now**: `DC-010`, `PC-006`, and `AUTH-001` — that's it. `AUTH-002`, `AUTH-004`, and `RR-009` are all fully resolved and closed.

**🟢 Update, 2026-09-12 (later the same day) — with your authorization, the `AUTH-001` production configuration change has been made.** The confirmation-email redirect fix and the Niswah-branded email templates (signup confirmation and password recovery) are now live in your Supabase project — applied directly, then independently re-read to confirm the change actually took effect exactly as intended, not just assumed from a success response. Nothing else in your Auth settings was touched — checked field-by-field afterward. One thing found along the way, worth knowing: Google Sign-In is currently switched off in your Supabase project (separate from the app's own code, which is already correct) — not something this session can turn on for you, since that needs your own Google Cloud project credentials; flagging it here so it's not a surprise later if you want that sign-in option live.

**This does not close `AUTH-001` yet** — one step remains, and it's the same one already described above: your own SMTP (custom email sending) still needs to be set up, or a real signup attempt will hit the same sending-limit error already found earlier. Once you've entered your SMTP details in Supabase Dashboard → Project Settings → Authentication → SMTP Settings (sender email, sender name, host, port, username, password — this session never sees these), the acceptance script above (sign up with a new email → confirm you receive a Niswah-branded email → tap it → confirm it opens the app → onboarding → dashboard → logout → login → dashboard) is ready to run for real. **What holds the verdict at NO-GO now**: `DC-010`, `PC-006`, and `AUTH-001` (config done, your SMTP setup is the only remaining step) — unchanged from above, but `AUTH-001` is now one step closer.

**🟢 Update, 2026-09-13 — every account-security email your app can send now uses one consistent, bilingual (Arabic-first, English-second) Niswah-branded design.** You asked for the confirmation-email look to be extended to every other security email (password changed, email changed, identity verification, etc.), matching the confirmation email as the reference design. That's done: the confirmation and password-reset emails you already have gained a small standardized footer line reminding people never to share a link or code with anyone; four more email types now have the same branded design ready and live — "your new email" confirmation, an identity-verification code, "your password was changed," and "your email was changed" — even though, as explained below, none of these four can actually be triggered yet by anything in the app today. Seven more exotic email types (magic-link sign-in, invitations, phone-number-changed, etc.) were checked and confirmed you're not using any of them, so they were left exactly as-is, unbranded, per your own instruction.

**Two things found along the way, worth knowing, neither fixed in this pass (not part of what was asked):**
- There is currently **no screen in the app that finishes a "forgot password" reset** — tapping the link in the reset email opens the app, but nothing after that lets someone actually type a new password. The reset *email* now looks right and goes to the right place; what happens after opening it is a separate, unbuilt piece.
- The "change your email" option in Profile Settings **does not actually work** — it's writing to a database field that doesn't exist, so it silently fails rather than really changing anyone's email. This was already suspected from an earlier wave and is now reconfirmed.

Neither of these blocks anything already promised to be fixed, and neither was touched this pass — flagging both so they're not a surprise if a future test tries them. **What holds the verdict at NO-GO now**: unchanged — `DC-010`, `PC-006`, and `AUTH-001` (SMTP still the only remaining step for `AUTH-001`).

**🟢 Update, 2026-09-13 (later the same day) — every single account-security email your app is capable of sending (all 13 types Supabase supports) now uses the same Niswah-branded, bilingual design.** The 7 remaining "exotic" email types mentioned above (magic-link sign-in, invitations, phone-number-changed, sign-in method linked/removed, verification method added/removed) are now branded too, using the exact wording you provided. None of these 7 can currently be triggered by anything in the app — nothing was turned on, no new sign-in method or feature became available; this was purely about having the right look and wording ready in Supabase in case any of them are ever built. **One thing noticed in passing, not changed by this session**: your Supabase project's SMTP host is no longer blank — it now shows `mail.spacemail.com`, which looks like you've already started (or finished) setting up your own email sender since the last update. This session did not touch or verify that further, since you asked specifically not to begin the `AUTH-001` final test in this pass. **What holds the verdict at NO-GO now**: unchanged — `DC-010`, `PC-006`, and `AUTH-001`. If your SMTP setup is in fact done, the real signup/email test for `AUTH-001` is ready to run whenever you'd like — just say so and this session will pick it up as its own next step, not automatically.

**🟢 Update, 2026-09-13 (final update this day) — your real signup test mostly worked, and the two remaining problems you found have been fixed.** Great news first: the custom email setup worked — you got a real, Niswah-branded confirmation email, and your account was correctly recognized as confirmed when you came back to the app. That's the hard part, proven for real.

Three things you flagged, all now handled:

1. **The confirmation link opened a blank page when you tapped it from your computer's email/browser instead of from your phone/simulator.** Your account was still confirmed correctly behind the scenes — this was only about what you *saw*. The real cause: the link currently points straight at "open the Niswah app," which only works on the exact device the app is installed on; any other device or browser has nothing else to show, so it goes blank. The proper fix is a real webpage at `niswah.app` that shows a "your email is confirmed — open Niswah" message to everyone, and automatically opens the app for anyone who has it — that page's design is fully written and ready. **What's needed from you**: connecting `niswah.app` to a website (the technical setup is ready; it needs your DNS/domain access, which this session doesn't have). Nothing here was changed yet — this session did not touch your Supabase settings, exactly as you asked.

2. **Choosing Arabic during onboarding, but the "which branch of Fiqh do you follow" question showing up in English.** Found and fixed — the app was keeping two separate copies of "which language did you pick," and one of them could get reset back to English behind the scenes (specifically: if you left the app to confirm your email and came back). Now there's only one copy, so this can't happen again. Covered by 13 new automated tests that walk through every onboarding screen in Arabic and confirm none of them silently switch to English.

3. **The Sign In / Sign Up screen looking mirrored/flipped in Arabic.** This turned out to be caused by the exact same bug as #2 — once that's fixed, this is fixed too. (One small extra thing was fixed at the same time: the "back" arrow on onboarding screens now correctly points the right way in Arabic instead of always pointing left.)

**What this session could not do**: run these fixes on a real phone/simulator itself (no hands-on device access in this environment) — everything above is proven with fast, automated screen-by-screen tests instead, which is strong evidence but not quite the same as you tapping through it yourself. **What holds the verdict at NO-GO now**: `DC-010`, `PC-006`, `AUTH-001` (now down to just the blank-page fallback, needs your `niswah.app` domain connected), and this new item — call it the Arabic/RTL fix — needs your own quick retest before it's fully closed.

**Your retest, once you have a moment** (all fast, no technical steps):
1. Pick Arabic during onboarding.
2. Go through every screen — confirm the Fiqh Madhhab question (and everything else) shows Arabic.
3. Check the Sign In / Sign Up screen looks right for Arabic (reads right-to-left, tapping each tab shows the right fields).
4. Sign up with a new email, and this time tap the confirmation link on the same phone/simulator Niswah is running on — confirm it opens the app and recognizes you as confirmed. (No need to redo the "does the email arrive and look right" part — that's already proven.)

**🔴 Update, 2026-09-13 (later still) — a more serious problem: after signing in, choosing your language, and picking your Fiqh Madhhab, the app showed the Sign In / Sign Up screen again**, as if you had to log in twice. Found and fixed. The cause: the "sign in" screen used to be built as if it were one of onboarding's own steps — a leftover from a much older version of the app, from before there was a separate, proper "are you logged in?" check at the very front door. Once that proper front-door check was added (a while back), that leftover step inside onboarding became pointless and, it turns out, actively harmful — both the normal path through onboarding and simply tapping the "back" button from the Fiqh Madhhab question could land you back on it, even though you were already fully signed in.

**Fixed by removing that leftover step entirely** — signing in now only ever happens at the app's front door, never again partway through onboarding. **One more serious thing found and fixed while making this change**: the "Sign Out" button in your Profile settings was — invisibly — relying on that exact same leftover step to let you sign back in afterward. If this hadn't been caught, removing the old step would have left Sign Out completely broken (no way to get back into the app afterward). Both are fixed together, and this class of bug cannot recur — the fix is architectural (there is no longer a "login screen" anywhere inside onboarding for it to redirect to).

**One more small thing fixed along the way**: while testing every onboarding screen extra-large text size (an accessibility check), the Fiqh Madhhab question's answer buttons were found to visually overflow at that size — fixed with the same "shrink to fit" treatment already used elsewhere in the app.

**What this session could not do**: test this specific fix on a real phone/simulator (no hands-on device access in this environment) — it's proven instead with 16+ new fast, automated checks that walk through sign-in, sign-out, app-restart, and back-navigation exactly the way a real phone would, and confirm the sign-in screen never reappears once you're logged in. Strong evidence, but not quite the same as you tapping through it yourself.

**Your retest for this one, once you have a moment**:
1. Sign in.
2. Go through language, Madhhab, and every other onboarding question — confirm Sign In never appears again.
3. From the Madhhab question, tap the back arrow once — confirm it goes back to the language question, not to Sign In.
4. Finish onboarding, reach your dashboard.
5. Go to Profile → Sign Out — confirm you land on Sign In (not a crash, not onboarding).
6. Sign back in — confirm you go straight to your dashboard, not through onboarding again.

**What holds the verdict at NO-GO now**: `DC-010`, `PC-006`, `AUTH-001` (confirmation fallback page, needs your `niswah.app` domain connected), and now this state-machine fix, pending your retest above.

**🔴 Update, 2026-09-13 (later still) — you retested and it still happened: language asked again, then signed out and asked to sign in again.** Thank you for testing again — this is exactly the kind of real check that matters most. Two things came out of digging into this:

1. **A real, separate bug was found: even though you'd already picked your language on the very first screen (the small EN/ع toggle), onboarding was asking you to pick it again a few screens later.** That's now fixed — onboarding no longer has its own "choose your language" screen at all; your first choice is the only one that matters, everywhere in the app, from now on.

2. **The "signed in again" part could not be reproduced.** This session rebuilt the exact current code from scratch and traced every single place in the app that could ever show a sign-in screen — there are only two, and both are correct and expected (the very first screen when you're not signed in, and right after deleting an account). New automated tests that walk through your exact sequence — pick a language before signing in, then sign in for real — confirm the sign-in screen never reappears. The most likely explanation: **the copy of the app on your phone/simulator was built before yesterday's fix landed** — this is the same "needs a fresh rebuild, easy to miss" issue flagged a few times already in this process (there's still no automatic way to push a new build to your device). 

**Before you retest this one, please fully uninstall the app and reinstall it from the latest build** (not just close and reopen it) — a plain relaunch can still be running old code underneath.

**One more honest note**: this session tried hard to test the fix live on an Android emulator before asking you to retest — it hit a technical problem with the testing environment itself (not the app) that could not be resolved even after four different fixes were tried, including a full factory-reset of the test device. So this fix is backed by strong automated evidence, not by someone actually tapping through it on a real screen — please treat your retest as the real, first live check.

**What holds the verdict at NO-GO now**: `DC-010`, `PC-006`, `AUTH-001`, the state-machine fix (reopened, pending your retest on a freshly reinstalled build), and the language-duplication fix (same retest covers both).

**🟢 Update, 2026-09-14 (Post-Reconciliation Governance Correction wave) — your fresh-install iOS retest is in, and it's a clean sweep: all 9 checklist items PASS.** You reinstalled the app from scratch and confirmed: language selected pre-auth; no duplicate Language screen after login; Madhhab appeared directly; Arabic onboarding stayed Arabic throughout; no second Sign In/Sign Up appeared during onboarding; onboarding completed normally; you reached the dashboard; Sign Out returned you to Sign In; and signing back in returned you straight to the dashboard. This closes the state-machine fix (`AUTH-008`) and the language-duplication fix (`AUTH-009`) for real, on your own device — not just on automated tests — and the Arabic-locale fix (`AUTH-007`, tracked separately) closes with the same evidence. All three are now `VERIFIED_CLOSED / E4` in the finding register, with each one's full prior reopening/investigation history kept on record rather than erased.

A separate documentation pass run the same day (before your device was available, then reconciled against your results once they came in) also went back through everything this engagement has ever found or claimed, checking it against what's actually built and what's actually live in production — not just what a past report said. It surfaced two things worth knowing, neither new in substance, both already described above under your own Madhhab example: the "I don't know my madhhab" gap now has its own tracked finding ID (`AUTH-010`, not launch-blocking — nobody today is given wrong religious guidance by it), and the "Madhhab only saved on your phone" gap was found to reach further than first described — if an already-onboarded user reinstalls and loses local storage, the app silently assumes she follows the Hanbali school with no notice, and that assumption really does flow into the religious guidance and AI answers she sees. This was already tracked as `AUTH-005`; it isn't being escalated to launch-blocking unilaterally, but it's flagged here as worth your judgment call given what the fresh evidence shows. It does not affect any user who has ever completed onboarding normally, since onboarding requires an explicit choice.

**What holds the verdict at NO-GO now**: `DC-010`, `PC-006`, `AUTH-001` (confirmation fallback page, needs your `niswah.app` domain connected). The state-machine, language-duplication, and Arabic-locale items are now closed. `AUTH-005` (Madhhab persistence/silent-default) is flagged above for your consideration, not currently counted as a formal blocker.

**🔴 Update, 2026-09-14 (later the same day, Fiqh Authority / Knowledge-Base Governance Correction wave) — the blocker list above now splits into two layers, and two Madhhab items move from "flagged for your judgment" to formal blockers, but only for the Fiqh guidance features specifically.** You asked directly whether Niswah can safely launch Fiqh guidance while a user's madhhab can silently disappear and revert to an undisclosed default. The honest answer is no — this session traced the exact mechanism and confirmed it changes the actual religious guidance a reinstalling user is shown, and our own test cases show the 4 schools can genuinely disagree on identical facts, so this isn't a cosmetic gap. **`AUTH-005`** (silent madhhab default/persistence) and **`AUTH-010`** (forced "I don't know" guess) are now formally tracked as **Fiqh-feature launch blockers** — not whole-app blockers, and not automatically forcing a delay to the whole app, but real blockers for the Madhhab dashboard card, Fiqh Report, and Fiqh Advisor chat specifically. Two more items were found and registered the same way: there is currently no real, database-backed library of scholar-approved religious sources behind the Fiqh Advisor (it currently answers from the AI's own knowledge plus a live, filtered web search — a reasonable safety net, but not what was originally planned), and zero scholar has reviewed or approved anything in the fiqh content built so far. See `docs/founder-launch-confidence-dashboard.md`'s new "Fiqh readiness" section for the full picture.

**What holds the whole-app verdict at NO-GO now**: unchanged — `DC-010`, `PC-006`, `AUTH-001`. **What additionally holds the Fiqh-guidance-features verdict at NO-GO**: `AUTH-005`, `AUTH-010`, the missing scholar-approved source library, and the absence of any scholar review — all four apply only if those specific features launch turned on.

**🟢 Update, 2026-09-14 (later still, Fiqh Remediation Wave 1) — `AUTH-005` and `AUTH-010` are now built, deployed to production, and live-verified — down to `E3`/`E2`, waiting only on your own real-device test to close.** This session was given explicit, detailed instructions to actually fix these two, not just document them. It did: a real database migration establishes an honest, three-way "not yet answered / said she doesn't know / picked a real school" model server-side, `MadhhabController` now treats the server as the source of truth (your phone is only a cache), and — found while verifying the fix, not anticipated going in — the actual root cause of the silent Hanbali default turned out to be inside the database itself: the signup trigger had been hardcoding `'HANBALI'` for every new account since the column existed. That's removed. A second, separate undocumented database rule (requiring uppercase madhhab values, which would have silently broken every real save) was also found and removed during verification, before it could affect a real user. Onboarding's Madhhab step now has a genuine 5th "I don't know" option with a calm explanation and a confirmation-gated suggestion flow; Settings can change it later. 49 new automated tests pass, and a real save was proven to work against your live database inside a transaction that was undone immediately afterward. See the new **Madhhab Authority Handoff** above for the full detail and your 4-step retest — once you complete it, `AUTH-005`/`AUTH-010` close as `VERIFIED_CLOSED / E4`, the same standard just used for `AUTH-007`/`008`/`009`.

**What holds the Fiqh-guidance-features verdict at NO-GO now**: the missing scholar-approved source library and the absence of any scholar review (both unchanged, both explicitly out of scope for this fix), plus your pending retest of `AUTH-005`/`AUTH-010` above. The whole-app blocker list (`DC-010`, `PC-006`, `AUTH-001`) is unchanged.

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
