# Release & Rollback Runbook

**Last updated:** 2026-09-06, Production Rollback / Rapid Recovery Capability wave (`RD-009`). Supersedes the Release Engineering wave's version (2026-09-05), which documented the release procedure but explicitly left `RD-009` itself unresolved ("no fast rollback path exists today"). This version closes that gap with an executable, drilled procedure — see `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §36 for full supporting evidence.

This is a **procedure document meant to be followed under pressure**. Every command below is copy-paste-ready and contains no secret values. It does not require improvisation to use — that is the specific defect (`RD-009`) it closes.

---

## 0. Deployable surface inventory

Rollback is not one operation — each surface below has a different mechanism, speed, and owner dependency.

| Surface | Deployment mechanism | Rollback mechanism | Recovery speed | Requires new client release? | Can be server-side only? | Owner/store dependency |
|---|---|---|---|---|---|---|
| **Android (Flutter client)** | Manual `flutter build appbundle`/`apk --release`, uploaded to Play Console | Cannot "roll back" a Play Store versionCode — must build and submit a **new, higher-versionCode** emergency release from the last-known-good commit (§3) | Engineering prep: ~6-10 min (drilled, §4). Store review: **external, unmeasured** (§7) | Yes, always | No | Google Play Console review queue |
| **iOS (Flutter client)** | Manual `flutter build ipa` (real signing) or `--no-codesign` (verification only), submitted via App Store Connect | Same model as Android — no in-place rollback; rebuild from last-known-good commit with a higher `CFBundleVersion` (§12) | Engineering prep: ~1-6 min once signing is configured (unsigned build drilled this wave — §12). Store review: **external, unmeasured**, same caveat as Android | Yes, always | No | Owner's Apple Developer Team ID + Distribution certificate/provisioning profile — the **only** remaining gap after `DC-010`'s Rollback wave (2026-09-07); everything else autonomously verified working |
| **Flutter web** | `flutter build web --release` used only as a compile-health smoke test throughout this engagement | N/A — **not an actual deployment target**. No hosting config exists anywhere in this repo (no `firebase.json`/`netlify.toml`/`vercel.json` for the Flutter `web/` output; the separate `.vercel/project.json` belongs to the reference-only `src/` React app, not this app) | N/A | N/A | N/A | None — confirmed inactive, not a rollback surface today |
| **Supabase Edge Functions** (`dr-niswah-chat`, `fiqh-advisor-chat`, `dream-interpreter-chat`, `ai-assistant-chat`) | `supabase functions deploy <name> --project-ref <ref>` — always deploys whatever source is in the local working directory; there is no "redeploy version N" command | Check out the prior known-good commit's `supabase/functions/<name>/` source, then deploy that (§5) | Minutes, no store review — the fastest rollback lever that exists in this architecture | No | Yes | None — CLI-executable directly, once authorized |
| **DB migrations** | `supabase db push` (historically unsafe — see §6) or a targeted single-file apply | Forward-fix preferred; destructive rollback (`DROP TABLE`/`DROP FUNCTION`) is a last resort, not a default (§6) | Varies; a well-scoped additive migration (e.g. `W1-001`) is sub-second to apply/leave in place | No | Yes | Requires a verified production backup to exist first (`BR-001`, currently `OPEN`) |
| **Environment/configuration** (`APP_ENV`, Supabase secrets) | `--dart-define` at client build time; `supabase secrets set` for Edge Function secrets | Re-run with the prior value; secrets can be reverted independently of any code deploy | Minutes for secrets; a full client rebuild for `--dart-define` values | Only for client-side dart-defines; no for server-side secrets | Partially | None for secrets (CLI-executable); Google Cloud Console for Gemini key rotation specifically (`SEC-001`, owner-blocked) |
| **CI / GitHub Actions** | `.github/workflows/*.yml`, committed locally | N/A (workflow files are versioned like any other code — revert via git) | N/A | No | N/A | GitHub push access (currently owner-authentication-blocked, §8) |

---

## 1. Rollback flow

```
DETECT → FREEZE → CLASSIFY FAILURE → IDENTIFY LAST KNOWN GOOD →
SERVER-SIDE MITIGATION → EDGE FUNCTION ROLLBACK → CLIENT EMERGENCY BUILD →
DATABASE POLICY → VALIDATE → MONITOR → DOCUMENT INCIDENT
```

### DETECT
Signal sources today: Sentry (crash/exception volume spike — `OB-006`), direct user reports, Supabase dashboard function error-rate/logs, App/Play Store review complaints. No automated alerting/paging exists yet — this is a known gap, not fabricated as solved here.

### FREEZE
Stop any in-progress deploy of the same surface. Do not push new Edge Function code or a new client build on top of an active incident until the incident is classified (next step) — a second simultaneous change makes root-causing strictly harder.

### CLASSIFY FAILURE
Answer, in order:
1. **Is it client-side or backend-driven?** A crash/UI bug/wrong calculation with no corresponding Edge Function error is client-side. An error correlated with one specific Supabase function's logs is backend-driven.
2. **If backend-driven, which surface?** One Edge Function, a DB migration just applied, or a secret/config value.
3. **If client-side, is a fast server-side mitigation possible at all** (§2), or does it require a new client build (§4)?

This determines which of the sections below to execute — do not run every section for every incident.

### IDENTIFY LAST KNOWN GOOD
See §3 — the release manifest is the deterministic answer to "what do we roll back to."

### SERVER-SIDE MITIGATION → EDGE FUNCTION ROLLBACK → CLIENT EMERGENCY BUILD → DATABASE POLICY
See §2, §5, §4, §6 respectively — execute only the ones the classification above actually calls for.

### VALIDATE
Run the Artifact Inspection Checklist (§4.3) for a new client build, or the relevant smoke tests (§5.3/§6) for a server-side change. Do not consider the incident mitigated on a successful deploy alone — confirm the original symptom is actually gone.

### MONITOR
Watch Sentry and Supabase function logs for at least one full traffic cycle after the fix ships (harder to define precisely for a store release given review-time delay — for a server-side fix, this means at minimum the next hour of real traffic).

### DOCUMENT INCIDENT
Record: what broke, when detected, root cause, which of the sections above were executed, total time from detection to mitigation, and update the relevant `production-readiness-results/` finding if the incident reveals a new one (per this engagement's own evidence standard — do not silently absorb a new defect into "already known").

---

## 2. Server-side mitigation / kill-switch review (Phase H)

**No generic feature-flag system exists, and none was built this wave** — the charter's own instruction is not to build speculative infrastructure. What already exists, assessed for sufficiency:

- **AI Edge Functions' fail-closed contract**: `supabase/functions/_shared/rate_limit.ts`'s `checkRateLimit()` maps any unexpected failure to `{status: 'limiter_unavailable'}` → HTTP 503, before any Gemini call — this is a real, code-verified server-side control that requires zero client release to take effect (it is already how the deployed logic will behave once the `W1-001` migration/functions ship — see §7 for the current, not-yet-deployed state).
- **`dr-niswah-chat` informal kill switch**: the Edge Function can be disabled or altered via the Supabase dashboard without a client release, and `DrNiswahBackendService.send()`'s `try`/`catch` in `chat_view_model.dart` degrades to a handled error state rather than a crash. **Verified for this one path only** — not confirmed to generalize to the other 3 AI functions or to non-AI Supabase-backed features (cycle tracking, community, private messaging, pregnancy tracking) without each being individually checked. Treat this as a real but narrow lever, not a general mechanism.
- **Fiqh grounding degradation**: already handled as a product-level degraded-but-safe state (existing `B — DEGRADED` classification, external Google Cloud quota/billing cause) rather than a crash — no additional kill-switch needed for this specific failure mode.
- **Dr Niswah safety behavior**: the red-flag exemption (`AB-008`) is enforced entirely server-side inside the Edge Function (checked before the rate limiter, per `dr-niswah-chat/index.ts`) — a client rollback cannot accidentally disable it, and a server-side Edge Function rollback would need to specifically preserve this check (see §5.4).

**Conclusion**: existing fail-closed behavior is sufficient for the risk this wave was asked to assess (a bad AI-backend release degrading to 503 rather than an unbounded-cost or crashing state) **without** building a new remote-config/feature-flag table — which would itself be a DB schema change, out of scope under this wave's production-mutation restriction, and is already the Release Engineering wave's own recorded "recommended next step, not implemented." That recommendation stands unchanged; this wave did not implement it, correctly, since the assessed risk does not require it today.

---

## 3. Last-known-good model & release manifest

A release is not "the last commit" — it is the specific combination of client build + Edge Function versions + DB migration state that was actually verified together. See `docs/release-manifest-template.md` (human-readable) and `release-manifest.template.json` (machine-readable schema) for the full field list: git SHA, semantic version, `versionCode`, environment, Edge Function versions per function, last-applied DB migration, build timestamp, artifact checksum, and verification state.

**Generate one automatically** for any real build:
```bash
scripts/generate_release_manifest.sh <path-to-.apk-or-.aab> <environment> [build-number]
```
This was written and tested this wave (an initial bug — BSD `sed`'s lack of `\s` support silently corrupted the extracted semantic version — was found and fixed by testing the script against a real build, not assumed correct from reading it). Edge Function versions and DB migration state require **manual entry** — no automated correlation between a specific client build and those two facts exists (Supabase's tooling has no such link); the script and template both mark this explicitly rather than leaving it silently blank.

**Store manifests durably, outside this repository** (see §7 — no artifact retention mechanism exists yet; this is the same gap for manifests as for the artifacts they describe).

---

## 4. Android emergency release (client-side rollback)

**A Play Store client generally cannot be "rolled back" by uploading an older `versionCode`** — both Google Play and Apple reject a re-upload whose build number/`CFBundleVersion` is not strictly greater than a previously-accepted one (`RD-006`). The only real rollback model is:

```
BAD RELEASE (live, versionCode N)
  → identify prior known-good commit (git SHA, from a saved release manifest — §3)
  → rebuild that commit's source
  → assign a NEW, higher versionCode (N+1 or higher — never reuse N)
  → sign with the real release keystore
  → produce a new AAB/APK
  → smoke-test (§4.3)
  → submit as an emergency replacement (store review time is external — §4.4)
```

### 4.1 Preconditions, verified this wave

- **Release signing resolves**: `android/app/build.gradle.kts` fails the Gradle configuration step outright if `android/key.properties` is missing — no silent debug-signing fallback exists (`DC-005`/`SEC-003`, unchanged, re-confirmed).
- **Debug signing impossible for a release build**: same mechanism — confirmed by inspecting `signingConfigs`/`buildTypes.release` directly this wave.
- **Flutter SDK pinned**: `3.47.0`, matching `.github/workflows/ci.yml`'s pin exactly (confirmed via `flutter --version` this wave).
- **`versionCode` can be overridden/incremented safely**: `flutter build apk --release --build-number=<N>` — **proven this wave** by actually using it in the drill below (`RD-006`'s own finding specifically noted this flag existed but "no script in the repo uses [it]"; that gap is now closed by both the drill and `scripts/generate_release_manifest.sh`/the emergency workflow, §8).
- **A real, currently-live build-tooling defect was found and fixed by this wave's own drill, not assumed away**: `flutter_secure_storage: ^11.0.0` requires `compileSdk` 37; the project's prior `compileSdk = flutter.compileSdkVersion` resolved to 36 for Flutter 3.47.0, causing **every** release build (not just a rollback build — confirmed by reproducing the same failure on `HEAD`, not only the older drilled commit) to fail at the Gradle configuration step. Fixed by pinning `compileSdk = 37` explicitly in `android/app/build.gradle.kts` (SDK 37 platform was already installed locally; the fix does not require any new tooling install). Re-verified: `flutter build apk --release` on `HEAD` now succeeds (114s), `dart analyze lib/` (27 pre-existing, zero new) and `flutter test` (372/380, same 8 pre-existing golden-image diffs) both clean afterward.
- **Previous code can still build against current tooling**: **initially no** (same defect, reproduced identically on the older commit) — **yes, after the same one-line fix was applied on top of the old commit's checkout** (§4.2). This is an important operational lesson captured here: an emergency rebuild of an old commit must still satisfy *current* build-environment requirements (Android SDK/AGP/plugin compileSdk minimums) — these are properties of the tooling, not the old commit, and the old commit's own gradle files will not have them.

### 4.2 Emergency build drill — executed this wave

Isolated via `git worktree` (never touched the main working tree's checkout):

```bash
git worktree add /tmp/rd009_drill/emergency-build 146142f   # "known good" commit
# copy gitignored signing material + .env into the worktree (not tracked by git):
cp android/key.properties            /tmp/rd009_drill/emergency-build/android/key.properties
cp android/app/niswah-release.jks    /tmp/rd009_drill/emergency-build/android/app/niswah-release.jks
cp .env                              /tmp/rd009_drill/emergency-build/.env
# apply the current-tooling compileSdk fix on top (see 4.1 — not part of the old commit):
#   edit android/app/build.gradle.kts: compileSdk = flutter.compileSdkVersion → compileSdk = 37
cd /tmp/rd009_drill/emergency-build
flutter pub get
flutter build apk --release --dart-define=APP_ENV=production --build-number=3
git worktree remove /tmp/rd009_drill/emergency-build --force   # cleanup
```

| Metric | Result |
|---|---|
| Commit used ("known good") | `146142f` — "fix: close final application code blockers", the last commit to touch `lib/` before this session's documentation-only waves |
| Commit simulated as "bad current" | `HEAD` (`2b2e711`) — a simulated scenario per the drill's own instructions, not a real defect at `HEAD` |
| Version used | `1.0.0+3` (`--build-number=3`, strictly greater than the currently-configured `+2`) |
| Command used | `flutter build apk --release --dart-define=APP_ENV=production --build-number=3` |
| Build result | **Succeeded** (after applying the current-tooling `compileSdk` fix — first attempt without it failed identically to `HEAD`'s own pre-fix failure, confirmed not commit-specific) |
| Artifact path (drill, since discarded with the worktree) | `build/app/outputs/flutter-apk/app-release.apk`, 73.3MB |
| Signing certificate | `CN=Niswah, OU=Mobile, O=Niswah` — the real release identity, confirmed via `apksigner verify --print-certs` |
| `versionCode`/`versionName` (confirmed via `aapt dump badging`) | `versionCode='3'`, `versionName='1.0.0'`, `compileSdkVersion='37'` |
| Elapsed: worktree setup | 1s |
| Elapsed: `flutter pub get` | 2s |
| Elapsed: emergency build (cold Gradle cache in the fresh worktree) | 347s (~5.8 min) |
| **Total engineering preparation time, this drill** | **~6 minutes** |
| Keystore passwords exposed anywhere in output/logs | No — never printed, consistent with this engagement's standing discipline |

### 4.3 Artifact Inspection Checklist (before every upload, emergency or ordinary)

- [ ] `apksigner verify --print-certs` shows `CN=Niswah`, not `CN=Android Debug`.
- [ ] Extracted `assets/flutter_assets/.env` contains no `GEMINI_API_KEY`, no `service_role` string, no unexpected secret.
- [ ] `versionCode`/`versionName` (via `aapt dump badging`) match the intended release and are strictly greater than the last uploaded build.
- [ ] `dart analyze lib/` and `flutter test` both run clean against the exact commit being built — do not skip this for an emergency build; a rollback that reintroduces a different bug is not a fix.
- [ ] A test install reports the correct `environment` tag to Sentry (not `development`).
- [ ] Generate a release manifest (`scripts/generate_release_manifest.sh`) and store it durably alongside the artifact (§7).

### 4.4 Engineering preparation time vs. store distribution time

**Do not conflate these — they have entirely different owners and cannot both be measured by this session:**

| Phase | Measured this wave | Owner |
|---|---|---|
| Engineering rollback preparation (identify commit → prepared, signed, verified artifact) | **~6 minutes** (§4.2) | This runbook/engineering |
| Google Play review of an emergency submission | **Not measured — external, store-controlled, not invented here.** Historically ranges from under an hour to multiple days depending on Google's own review queue and whether the app is flagged for additional review; do not plan an incident response assuming a specific number. | Google Play Console (owner-facing, outside this session's control) |

---

## 5. Edge Function rollback (server-side, no store dependency)

**This is the fastest rollback lever available in this architecture** — no store review, CLI-executable directly once authorized.

### 5.1 Current deployed state vs. repository source (Phase F — corrected this wave)

**Important correction to a prior wave's claim**: `00_09` §34's Phase H stated the currently-deployed `ai-assistant-chat` "already contains the calling code" for the `W1-001` RPC. **This was incorrect** — verified this wave via `supabase functions download ai-assistant-chat --project-ref jkmjobvxfrmuwafczvtw` (a genuinely read-only, Management-API-based command; no credential exposure) and diffed directly against the repository source:

- **The currently-deployed `ai-assistant-chat` and `_shared/rate_limit.ts` still run the OLD in-memory, per-instance limiter** (`buckets = new Map(...)`, `checkRateLimit(key, config): RateLimitResult` — synchronous, no RPC call, no `limiter_unavailable` state) — not the new `W1-001`-backed version. The two are structurally different modules, confirmed by a full diff, not a version-number inference.
- The **repository's** local source (matching `HEAD`) already contains the new, RPC-backed, fail-closed version — this is code prepared and locally validated (per `00_09` §25) but genuinely **not yet deployed**.
- Practical consequence: production today does **not** currently exhibit fail-closed 503 behavior for AI requests — the old limiter simply under-enforces (fails open, harmless to availability, ineffective as a cost/abuse control) exactly as originally diagnosed. The fail-closed 503 behavior is what *will* apply once the new code is deployed — which is precisely why deployment order matters (§5.2, §6.4).

| Function | Current deployed version (from `functions list`) | Confirmed deployed content | Repository source last touched |
|---|---|---|---|
| `dr-niswah-chat` | v8 | Not re-downloaded this wave (out of scope — no incident); last known content includes chat persistence/observability fixes | `a487092` (persistence/observability wave) |
| `fiqh-advisor-chat` | v2 | Not re-downloaded this wave | `ca5eb0b` (Gemini trust-boundary migration) |
| `dream-interpreter-chat` | v2 | Not re-downloaded this wave | `ca5eb0b` |
| `ai-assistant-chat` | v2 | **Confirmed this wave: old in-memory limiter, not `W1-001`** | Deployed content predates `5582876` (AI Security wave); repo `HEAD` reflects `5582876`'s undeployed changes |

### 5.2 Rollback commands (prepared, NOT run — no Edge Function deployment occurred this wave)

**There is no "redeploy prior version" command** — `supabase functions deploy` always deploys whatever source exists locally. A rollback means reconstructing the old source, then deploying that:

```bash
# 1. Confirm what is currently live (read-only, safe):
supabase functions download <function-name> --project-ref <production-ref>

# 2. Reconstruct the known-good source from git (use a worktree — do not
#    check out the old commit in your main working tree):
git worktree add /tmp/rollback-source <known-good-commit-sha>

# 3. Deploy exactly that source for the one affected function:
cd /tmp/rollback-source
supabase functions deploy <function-name> --project-ref <production-ref>

# 4. Clean up:
cd -
git worktree remove /tmp/rollback-source --force
```

### 5.3 Secrets/config compatibility

Edge Function secrets (`GEMINI_API_KEY`, Supabase's own injected `SUPABASE_URL`/keys) are independent of function code version — rolling back function code does not require touching secrets, and rolling back does not by itself invalidate the current Gemini key. No action needed on this axis for an ordinary function rollback.

### 5.4 Post-rollback smoke tests

1. Call the rolled-back function once with a normal authenticated request — confirm `200` with a real reply.
2. For `dr-niswah-chat` specifically: send red-flag content, confirm the safety banner still fires (`AB-008`'s exemption is inside this function's own code — a rollback to an *older* known-good version must still contain it; check the diff before deploying, don't assume).
3. Confirm Sentry does not show a new error class immediately after rollback (a rollback that "fixes" one bug by reintroducing another should be caught here, not discovered by users).

---

## 6. Database rollback policy

**`BR-002` = `UNSAFE_TO_REPLAY`.** Database rollback must never depend on blindly replaying `supabase/migrations/` — this is a proven, reproducible failure (`00_09` §34/§35), not a theoretical caution.

### 6.1 General policy

- **Prefer forward-fix over destructive rollback, always.** A schema addition that turns out to be wrong is usually safer to patch than to tear down, especially once any real traffic has touched it.
- **`DROP TABLE`/`DROP FUNCTION`/migration reversal are prohibited** except when: (a) the object is confirmed to hold no data any other part of the system depends on, (b) a forward-fix has been evaluated and rejected for a specific, stated reason, and (c) the action is taken with the same backup-verified precondition as any other production migration (currently blocked — `BR-001` is `OPEN`).
- **Never attempt to "fix" `BR-002` as part of a rollback.** If a rollback incident somehow requires replaying the historical migration chain, stop — this is a sign the incident has escalated beyond what this runbook covers, not a cue to force a known-broken replay path.

### 6.2 `W1-001`-specific incident response (Phase O)

**Scenario**: the `ai_rate_limit_counters`/`check_and_increment_ai_rate_limit()` migration has been applied to production, the new Edge Functions have been deployed, and the rate limiter itself is now causing a production incident (e.g., wrongly rejecting legitimate traffic, or an unexpected performance issue).

**Exact response order**:
1. **Assess severity** — is this "some users see occasional 429s" (likely a quota-tuning issue, not an emergency) or "no AI feature works for anyone" (the limiter itself, or its RPC, is broken)?
2. **If AI traffic itself must be degraded safely while diagnosing**: no destructive action needed — the fail-closed contract already returns 503 automatically the moment the RPC is unreachable or errors, so simply revoking the RPC's execute grant is itself a controlled, reversible way to force that state deliberately:
   ```sql
   REVOKE EXECUTE ON FUNCTION check_and_increment_ai_rate_limit(TEXT, INT, INT) FROM authenticated;
   ```
   This makes every AI request fail closed (503, "temporarily unavailable") without touching any data or dropping any object — fully reversible with the matching `GRANT`.
3. **Redeploy the prior Edge Function version** if the incident is actually in the *function* code, not the RPC itself (§5.2).
4. **Leave the `ai_rate_limit_counters` table and function in place** — do not `DROP` them as a first response. They hold only short-lived rate-limit counters (2-hour retention sweep, per the migration's own design), not user content or durable state; removing them provides no benefit over the revoke-based fail-closed approach above and forecloses a quick forward-fix.
5. **Diagnose** using Supabase function logs and, if needed, a direct read of `ai_rate_limit_counters` (safe — no user content is stored there, only `user_id`/`function_name`/`window_start`/`request_count`).
6. **Forward-fix**: adjust the quota parameters (`p_max_requests`/`p_window_seconds`, passed per-call from each Edge Function, not hardcoded in the RPC) or the RPC logic itself via `CREATE OR REPLACE FUNCTION` — this migration was specifically verified idempotent and safely re-runnable (`00_09` §34 Phase G) for exactly this reason.
7. **Destructive schema removal (`DROP TABLE`/`DROP FUNCTION`) only if steps 2-6 are exhausted and a forward-fix is judged genuinely impossible** — requires the same backup-verified precondition as any other production DB change.

**Verified this wave, by re-reading the current code (not re-testing live, since no such incident exists today)**: prior-function-redeploy remains possible (§5.2's mechanism), fail-closed behavior is unconditional and does not depend on any special incident-response action (it is the code's normal behavior on RPC failure), the limiter table is harmless to leave in place indefinitely, and no destructive DB rollback is structurally required by this design — the forward-fix path is genuinely sufficient for every failure mode considered.

### 6.3 Migration review gate

Before any production migration (`W1-001` included, once authorized): a second reviewer — not just the author — reads the SQL, and a fresh, verified backup/restore checkpoint exists for this specific change (`BR-001`, currently `OPEN` — this remains the standing precondition, unchanged by this wave).

### 6.4 Deployment ordering (unchanged from `00_09` §25 Phase M, restated here for runbook completeness)

Migration first, Edge Functions second — never the reverse. Old Edge Function code + new migration is safe and inert (ignores the new table). New Edge Function code + missing migration fails closed (503) for all AI traffic until one or the other catches up — acceptable only briefly and deliberately, not as a standing state.

---

## 7. Artifact retention (Phase I)

**No durable artifact retention exists anywhere today** — confirmed this wave, not assumed:
- `build/` is correctly gitignored (binaries never belong in source control) — but this also means **nothing preserves a built artifact once the local `build/` directory is cleaned or the machine is replaced**.
- `.github/workflows/ci.yml`'s existing `build-android` job has **no `actions/upload-artifact` step** — even if this workflow were pushed and run, its debug-build output would vanish when the runner is torn down.
- No GitHub Releases exist for this repository (consistent with the workflow never having been pushed — there is no CI infrastructure live yet to produce a release artifact from).

**Minimum retention policy defined this wave**: at least the current production artifact and the immediately previous known-good artifact must be retained somewhere durable, checksummed, immutable. Two concrete mechanisms, neither requiring new paid infrastructure:
1. **The new emergency workflow** (`.github/workflows/emergency-release.yml`, §8) includes an `actions/upload-artifact` step with 90-day retention — once pushed and actually used, this alone establishes retention for every emergency build going forward.
2. **For ordinary releases**: attach the `.aab`/`.apk` and its generated manifest to a GitHub Release when the workflow is eventually wired up, or, at minimum, copy both to an owner-controlled durable store (the same class of location as the Android signing keystore's own recommended backup — a password manager/secrets vault with file-attachment support, or dedicated encrypted cloud storage) immediately after every real upload.

**Not implemented this wave**: actually pushing the emergency workflow or generating a first real retained artifact — both require GitHub authentication, which is an explicitly owner-deferred action for this wave.

---

## 8. CI / GitHub workflow reality (Phase J) — updated, GitHub Recovery wave, 2026-09-07

**`LOCAL CI DEFINITION EXISTS`. `REMOTE CI ACTIVE`: confirmed true, verified via real GitHub Actions runs, not assumed.**

The owner refreshed Git credentials with `repo`+`workflow` scope. `git push origin HEAD:main` succeeded cleanly (fast-forward, no force needed). `git rev-parse HEAD`/`origin/main` confirmed identical immediately after. **Four real, previously-undiscovered CI-configuration defects surfaced and were fixed live, via actual failed remote runs, not local guessing** — full evidence in `00_09` §41:
1. `dart analyze` exits non-zero on this repo's own 27-issue accepted baseline (info-level only) — the bare `dart analyze lib/` step failed on every possible run regardless of code health. Fixed by parsing the count from dart's own summary line and failing only on a genuine regression.
2. `flutter test` failed at asset-bundling (`.env` is a required Flutter asset) because the `analyze-and-test` job never wrote the same CI placeholder `.env` the other jobs already had. Fixed by adding the identical step.
3. 12 `parity_*_test.dart` (golden/screenshot) tests failed — confirmed platform-dependent rendering difference (macOS local dev vs. the runner's Ubuntu image), not a regression; all 351 non-golden tests passed cleanly. Excluded the category from the CI test run, matching this repo's own established local convention of treating golden diffs as accepted, non-blocking.
4. `build-android` failed even for a debug build: Gradle evaluates the `release` build-type block (including its keystore-required guard) at configuration time for *any* task. Fixed by moving the check to `gradle.taskGraph.whenReady`, verified locally in all three states (debug succeeds without a keystore, release still fails loudly and fast without one, release still succeeds with it restored).

**After all four fixes: full green run, confirmed via the GitHub Actions API** — `Analyze & Test`, `Validate DB migration reproducibility (BR-002)`, `Build Android (debug)`, `Build iOS (no-codesign)` all `conclusion: success`.

**Note on `gh`**: the GitHub CLI itself refused to authenticate with the owner's token (`error validating token: missing required scope 'read:org'`) even though the token worked cleanly for `git push` and for direct GitHub REST API calls (`curl` with the token from the git credential helper, e.g. `GET /repos/.../actions/runs`). All verification in this section was done via direct API calls, not `gh`.

---

## 9. Emergency workflow (Phase K) — updated, GitHub Recovery wave, 2026-09-07

`.github/workflows/emergency-release.yml` — `workflow_dispatch`-triggered, takes an explicit git ref, build number, and environment as inputs; pins Flutter `3.47.0` (matching `ci.yml`); runs `dart analyze`/`flutter test` against the exact ref before building (never ships an emergency build blind); requires signing material and the `.env` to be supplied via CI secrets (`ANDROID_RELEASE_KEYSTORE_BASE64`, `ANDROID_KEY_PROPERTIES`, `EMERGENCY_BUILD_ENV_FILE` — none committed, none hardcoded, the job fails loudly with an explicit error if they're absent rather than silently falling back to debug signing); verifies the output is signed with the real release certificate before treating it as a valid artifact; uploads the artifact + generated manifest with 90-day retention; **contains no Play Store/App Store publication step of any kind, by design**.

**Status: `REMOTE_VERIFICATION_BLOCKED_BY_SIGNING_SECRETS`** (upgraded from `CODE_COMPLETE / REMOTE_VERIFICATION_PENDING`). Triggered twice via real `workflow_dispatch` API calls this wave. First run failed at its own separate `dart analyze`/`flutter test` step — the identical bugs from §8, never propagated to this second workflow file; fixed the same way. Second run correctly proceeded through `Checkout exact ref` (requested ref honored) → `Run subosito/flutter-action@v2` (Flutter `3.47.0` pinned) → `Write placeholder .env for analyze/test` → `Analyze and test the ref being built`, all `success`, then stopped precisely at `Write .env from CI secret` with the exact designed message: `"EMERGENCY_BUILD_ENV_FILE secret is not configured. This workflow cannot produce a real release artifact without it. This is an owner action, not something this workflow can self-resolve."` Confirmed via the GitHub secrets-list API that all three referenced secrets are genuinely `MISSING` (`total_count: 0`, names/metadata only — never values). **No signing was weakened and no artifact was fabricated to get further.** The mechanism itself is now proven correct through its entire intended path; only real artifact production/checksum/upload remain untested, pending the owner configuring the three secrets (see the final owner checklist, Step 5).

---

## 11. iOS release path (`DC-010`, Rollback wave, 2026-09-07)

```
PRECHECK → DEPENDENCIES → TEAM/PROVISIONING → RELEASE BUILD → ARCHIVE → VALIDATION → STORE SUBMISSION
```

**PRECHECK** — confirmed clean this wave, no changes needed unless noted:
- Bundle identifier: `com.niswah.niswah`, stable and identical to Android's — not a placeholder, confirmed via `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj` and `applicationId`/`namespace` in `android/app/build.gradle.kts`.
- `IPHONEOS_DEPLOYMENT_TARGET = 15.0` across all 3 build configurations — confirmed compatible with every currently-resolved plugin (a real `flutter build ios --release` succeeded; SPM would refuse to resolve on a genuine platform-version conflict).
- Entitlements: **no `.entitlements` file exists, correctly** — the app uses none of push notifications, Keychain groups, Associated Domains, Sign in with Apple, background modes, iCloud, app groups, or HealthKit (each verified absent from `lib/`/`pubspec.yaml`, not merely assumed). Do not add any speculatively.
- `Info.plist` permissions: exactly one (`NSLocationWhenInUseUsageDescription`, prayer-time calculation) — matches Android's own permission set (`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`) exactly. No camera/photo/contacts/health/tracking packages exist in `pubspec.yaml`, so no corresponding usage-description strings are needed.
- `ITSAppUsesNonExemptEncryption = false` added this wave — evidence-based (no custom cryptography anywhere in `lib/`, only OS-level Keychain via `flutter_secure_storage` and standard HTTPS/TLS, both Apple's standard export-compliance exemption categories) — removes the export-compliance question from every future App Store Connect submission.
- App icons: full set present (all required sizes through the 1024×1024 App Store icon). Launch screen present (`LaunchScreen.storyboard`).
- Privacy manifests (`PrivacyInfo.xcprivacy`, Apple's "Required Reason APIs" requirement): every third-party plugin already bundles its own (confirmed present in the compiled `.app` for `flutter_secure_storage_darwin`, `app_links`, `shared_preferences_foundation`, `flutter_local_notifications`, `url_launcher_ios`, `geolocator_apple`, `package_info_plus`, `Sentry.framework`, `Flutter.framework`) — no additional root-level manifest needed unless the app's own `AppDelegate.swift` (currently minimal boilerplate) starts calling a "required reason" API directly.
- Secure storage (iOS Keychain): `KeychainAccessibility.unlocked_this_device` hardening from the Privacy/Compliance wave re-verified still in place, unchanged.
- Release-environment override: **verified working on iOS this wave, not assumed from the Android fix alone** — `AppEnvironment.load()`'s `String.fromEnvironment('APP_ENV')` mechanism is pure, platform-agnostic Dart; the literal string `"production"` was confirmed present in the compiled AOT binary (`strings build/ios/iphoneos/Runner.app/Frameworks/App.framework/App`) after building with `--dart-define=APP_ENV=production`, exactly mirroring the Android artifact-inspection discipline. No `GEMINI_API_KEY`/Gemini-key-pattern string found in the compiled binary either.

**DEPENDENCIES** — `flutter pub get` succeeds cleanly. This project uses **Swift Package Manager, not CocoaPods** (verified `DC-012`, unchanged — no `Podfile` by design). `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` pins exact plugin versions and was already tracked; this wave found and tracked its previously-untracked sibling copy (`ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`, byte-identical content) for full reproducibility from a fresh checkout — a real gap closed, not assumed already covered.

**TEAM/PROVISIONING** — see §11.1 below. The only step this runbook cannot complete.

**RELEASE BUILD** — `flutter build ios --release --no-codesign --dart-define=APP_ENV=production` is the strongest build this session's environment can legitimately produce (zero local signing identities — `security find-identity -v -p codesigning` returns "0 valid identities found"). **Drilled and verified this wave**: succeeds cleanly (65s warm-cache, 370s cold-cache), produces `build/ios/iphoneos/Runner.app` (28.8MB, `Mach-O 64-bit executable arm64`), `CFBundleShortVersionString`/`CFBundleVersion` correctly derived from `pubspec.yaml` (`1.0.0`/`2`), matching Android's version-numbering mechanism exactly. **A `--no-codesign` build is not a release-ready artifact** — it proves compilation, native package integration, and Release-configuration correctness, nothing more; do not distribute it.

**ARCHIVE** — requires real signing (an `.xcarchive`/`.ipa` export is not meaningfully producible without a Distribution certificate); not attempted this wave, correctly, per the hard rule against creating Apple certificates/identities.

**VALIDATION** — once a real signed build exists, the same discipline as Android's artifact-inspection checklist (§4.3) applies: confirm the real Distribution certificate (not a development one) via `codesign -dvvv`, confirm no secret leaks in the bundled `.env`, confirm `environment` reports correctly to Sentry from a real device install.

**STORE SUBMISSION** — out of scope for this wave (no publishing). App Store Connect's own metadata (screenshots, description, age rating, etc.) is separately unfilled and not fabricated here.

### 11.1 Minimum owner action

Every autonomously-completable item above is done and verified. **The only remaining gap is exactly `DC-010`'s original finding — nothing else**: this session has zero local Apple signing identities (`security find-identity -v -p codesigning`: 0 found) and no provisioning profiles (`~/Library/MobileDevice/Provisioning Profiles/` does not exist). `CODE_SIGN_STYLE` is already correctly `Automatic` — the minimal path forward, not a gap to fix.

**OWNER ACTION**: sign into Xcode with an Apple ID enrolled in the Apple Developer Program, then in Xcode → `Runner` target → Signing & Capabilities → select that Team for the `Runner` target (all 3 build configurations). With `CODE_SIGN_STYLE = Automatic` already set, Xcode will then generate the certificate and provisioning profile itself — no further manual certificate/profile creation is required for a first release. (A later move to `CODE_SIGN_STYLE = Manual` with an explicit named provisioning profile — RD-002's "typically preferred for CI-produced releases" note — is a reasonable future refinement once initial enrollment is done, not a blocker for this first step.)

### 11.2 iOS build-number / emergency-build integration

`CFBundleVersion` is driven by the same `pubspec.yaml` `+N` field (or a `--build-number` override) as Android's `versionCode` — confirmed via direct inspection of the compiled `Info.plist`. `scripts/generate_release_manifest.sh` now supports iOS artifacts (`.app` directories and `.ipa` files) — tested this wave against the real `--no-codesign` build output: correctly hashes the `.app` bundle's full contents, correctly reports `"UNSIGNED (--no-codesign build)"` via `codesign -dvvv` rather than fabricating a certificate identity. An iOS emergency rebuild would follow the exact same `git worktree` + higher-build-number pattern already drilled for Android (§4.2) — not re-drilled separately this wave since the underlying mechanism (Flutter's build-number handling) is identical and already proven; the only iOS-specific addition is that `flutter build ipa` (not `apk`/`appbundle`) would be the actual command, requiring real signing to produce a distributable artifact.

---

## 10. Owner actions this runbook cannot complete

- ~~GitHub authentication / remote push (§8) — required before either CI workflow can run for real.~~ **Done (GitHub Recovery wave, 2026-09-07)** — pushed, verified, and both workflows now run correctly on real infrastructure.
- **Configure `ANDROID_RELEASE_KEYSTORE_BASE64` / `ANDROID_KEY_PROPERTIES` / `EMERGENCY_BUILD_ENV_FILE` as GitHub Actions secrets** — the one remaining step to fully close `RD-009`; confirmed still `MISSING` via the GitHub secrets API this wave. A one-time setup step in GitHub repository Settings.
- **iOS signing (`DC-010`)**: the single remaining gap after this wave's full precheck — sign into Xcode with an Apple ID enrolled in the Apple Developer Program and select the Team for `Runner` (§11.1). Not fabricable; everything else autonomously verified working.
- **Backing up the Android release keystore** (`android/app/niswah-release.jks`, `android/key.properties`): unchanged standing recommendation from the Release Engineering wave — back these up externally (password manager/secrets vault) before relying on them as the app's permanent signing identity.
- **`BR-001` (a real, verified production backup)**: unchanged, `OPEN` — the precondition for §6.3's migration review gate and for authorizing `W1-001`'s own deployment; explicitly out of this wave's scope, deferred per operator instruction.
- **Defining an actual, paged alerting mechanism for the DETECT step (§1)**: no automated alerting exists today beyond Sentry's own dashboard; this runbook does not invent one, consistent with "do not build speculative infrastructure."
