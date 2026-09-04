# Release & Deployment Audit — Findings Register (Phase 2A: Static Verification)

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | 2A — Static Verification |
| Audit date | 2026-09-04 |

Evidence key: 🟥 Confirmed by Deployment/Rollback Test · 🟧 Confirmed by Pipeline/Config/Script · 🟨 Likely · 🟦 Requires Controlled Validation · ⬜ N/A / False positive

Findings RD-001, RD-002, RD-003, RD-004, RD-005 are **owned consolidations** of prior-wave findings (Dependencies/Config, and Security for RD-001). They are re-verified here with direct evidence, not re-derived from scratch, and this audit formally adopts the release-readiness verdict for them. Findings RD-006 through RD-010 are new ground assessed by this audit.

---

## RD-001 — Android release build type is signed with the debug keystore (cross-ref: DC-005, SEC-003)

- **Category:** `MOB-01` / `ART-01`
- **Severity:** **RD0 — Critical**
- **Release stage:** Build / Artifact signing
- **Config path:** `android/app/build.gradle.kts`
- **Expected behavior:** `buildTypes { release { signingConfig = signingConfigs.getByName("release") } }` pointing at a real release keystore referenced via `key.properties` (not committed, injected securely at build time).
- **Actual/configured behavior:**
  ```kotlin
  buildTypes {
      release {
          // TODO: Add your own signing config for the release build.
          // Signing with the debug keys for now, so `flutter run --release` works.
          signingConfig = signingConfigs.getByName("debug")
      }
  }
  ```
  This is the unmodified stock Flutter-template placeholder. No `key.properties` file and no `.jks`/`.keystore` file exist anywhere in the repository (confirmed by exhaustive `find`).
- **Evidence:** 🟧 Confirmed by direct read of `android/app/build.gradle.kts` this pass (re-verified verbatim, unchanged from DC-005/SEC-003's original finding) + confirmed absence of `key.properties`/keystore files by search.
- **Production impact:** A release build produced from this repo today is signed with the publicly-known Flutter debug key. Google Play will reject an initial upload signed this way, and even if accepted in error, all subsequent updates would need the same debug key — meaning any developer with the (public, shared) debug keystore could produce an update-compatible malicious build. This is both a release-integrity defect and a store-submission blocker.
- **Rollback impact:** N/A (pre-launch blocker, not a rollback concern) — but note that once *any* real release key is finally introduced, that key becomes permanently load-bearing: losing it means the app can never be updated again under the same listing. No key-custody/backup plan exists yet either (new observation, see RD-010).
- **Launch-blocker status:** **YES — Mandatory NO-GO per template §4 (RD0 definition: "cannot be rolled back/recovered... production release can deploy wrong code").**
- **Confidence:** 🟧 Confirmed by Config (not merely likely — this is a certain, verified fact about the current build wiring).
- **Status:** OPEN

---

## RD-002 — iOS release build has no pinned code-signing identity (cross-ref: DC-010)

- **Category:** `MOB-01`
- **Severity:** **RD1 — High**
- **Release stage:** Build / Artifact signing
- **Config path:** `ios/Runner.xcodeproj/project.pbxproj`
- **Expected behavior:** An explicit `DEVELOPMENT_TEAM` (and, for CI-produced releases, typically `CODE_SIGN_STYLE = Manual` with a named provisioning profile) so that any machine/CI runner with the correct certificate can reproducibly produce the same-identity build.
- **Actual/configured behavior:** All 3 build configurations (Debug/Release/Profile) in `project.pbxproj` use `CODE_SIGN_STYLE = Automatic;` (confirmed at lines 398, 415, 430) with **zero** `DEVELOPMENT_TEAM` entries anywhere in the file.
- **Evidence:** 🟧 Confirmed by direct `grep` of `project.pbxproj` this pass.
- **Production impact:** A release IPA's signing identity depends entirely on whichever Apple Developer account happens to be logged into Xcode on whatever machine runs the build. Two different developers (or a developer today vs. a CI runner set up later) can produce IPAs signed under different developer accounts, breaking update continuity on the App Store and making the build process fundamentally non-reproducible/non-transferable.
- **Rollback impact:** Compounds RD-001's key-custody risk on the iOS side — there is no single, known, recoverable signing identity to fall back to.
- **Launch-blocker status:** YES (Pre-launch blocker per RD1 definition — "core release process is materially unreliable... depends on undocumented/manual assumptions").
- **Confidence:** 🟧 Confirmed by Config.
- **Status:** OPEN

---

## RD-003 — No CI/CD pipeline exists anywhere in the repository (cross-ref: DC-006)

- **Category:** `CI-01` / `BUILD-01`
- **Severity:** **RD1 — High**
- **Release stage:** Entire pipeline (build, test, artifact, deploy)
- **Config path:** N/A (absence is the finding)
- **Expected behavior:** At minimum, an automated pipeline that builds and runs the existing `test/` suite on every push/PR, ideally gated before merge; realistically also a release-build/signing stage.
- **Actual/configured behavior:** No `.github/workflows`, `.gitlab-ci.yml`, `Jenkinsfile`, `bitrise.yml`, `codemagic.yaml`, `.circleci`, or any other CI config exists anywhere in the repo (confirmed by directory search to depth 4, re-verified this pass).
- **Evidence:** 🟧 Confirmed by Config/absence-of-config search.
- **Production impact:** No build is ever verified reproducible before being considered "ready." No automated gate prevents a broken build, a failing test, or a debug-signed artifact from being the one that gets manually uploaded to a store. The substantial existing `test/` suite (dozens of unit/widget/golden/parity tests) currently provides **zero** protective value at release time because nothing runs it automatically or blocks on its failure.
- **Rollback impact:** Without CI-produced, versioned artifacts, there is no known-good prior build to roll back *to* — "rollback" for this app would mean re-deriving a build from an old commit by hand, from a developer's local machine, with no guarantee it matches what actually shipped before.
- **Launch-blocker status:** YES.
- **Confidence:** 🟧 Confirmed by Config.
- **Status:** OPEN

---

## RD-004 — No Flutter/Dart SDK version pinning mechanism (cross-ref: DC-007)

- **Category:** `BUILD-01`
- **Severity:** **RD2 — Medium**
- **Release stage:** Build
- **Config path:** N/A (absence is the finding); `pubspec.yaml` only constrains `sdk: ^3.13.0` (a wide range, not a pin)
- **Expected behavior:** An `.fvmrc`, `.tool-versions` (asdf), or equivalent pinning file so every build machine (developer or future CI) uses an identical Flutter/Dart toolchain version.
- **Actual/configured behavior:** No such file exists. `.metadata` records the Flutter tool revision (`4cf24164269a5ebf0c16a028a00727d0e77bbb05`) that last touched the project, but this is auto-generated bookkeeping, not an enforced pin — nothing reads it to select or validate the active toolchain at build time.
- **Evidence:** 🟧 Confirmed by search (re-verified this pass — no `.fvmrc`/`.fvm`/`.tool-versions` found).
- **Production impact:** Builds made months apart, or on different developers' machines, can silently use different Flutter/Dart SDK versions, which can change generated code, dependency resolution, or even runtime behavior in edge cases — undermining "the exact same commit reliably produces the same build" (template §34 Build Reproducibility Audit).
- **Rollback impact:** Minor — bounded, workaround exists (developers can manually match `.metadata`'s revision).
- **Launch-blocker status:** NO (bounded, explicit-acceptance-eligible per RD2 definition), but should be closed before CI (RD-003) is stood up, since CI needs a pinned toolchain to be meaningful.
- **Confidence:** 🟧 Confirmed by Config.
- **Status:** OPEN

---

## RD-005 — No environment/build separation; single `.env` bundled as a compiled asset drives every build target (cross-ref: DC-001, DC-003)

- **Category:** `ENV-01` / `CFG-01`
- **Severity:** **RD1 — High** *(release-process framing; the Dependencies/Config audit separately and correctly rates the underlying secret-exposure mechanism as DC0/Critical from the security-configuration lens — this finding does not downgrade that rating, it registers the same root defect from the release/environment-separation angle and inherits DC-001's launch-blocking status)*
- **Release stage:** Build / Environment separation
- **Config path:** `pubspec.yaml` (`flutter: assets: - .env`), `.env`, `.env.example`
- **Expected behavior:** Distinct build configurations/flavors (e.g., `dev`/`staging`/`prod`) with environment-appropriate config injected at build time via a mechanism that does not embed secrets verbatim into the shipped binary asset bundle; `.env.example` documents every variable actually required by the code.
- **Actual/configured behavior:** One `.env` file, loaded as a literal Flutter asset, drives every build regardless of intended target. `APP_ENV` is loaded but has no effect on any code path (DC-002). `.env.example` omits `GEMINI_API_KEY`, which `GeminiService` actually requires at runtime for the AI Advisor / Dream Interpreter features (re-confirmed this pass by reading `.env` key names against `.env.example`).
- **Evidence:** 🟧 Confirmed by manifest + code, re-verified this pass (`.env.example` content vs. actual `.env` keys read).
- **Production impact:** There is no way to produce a "staging" or "internal test" build that is meaningfully different from a "production" build — every build is the production build, using whatever local `.env` happens to exist, which also means test/placeholder Supabase credentials could accidentally ship, or production credentials could accidentally leak into a build meant only for internal testing.
- **Rollback impact:** Rotating a compromised key requires a full app rebuild and re-release for every affected build target — there is no runtime/remote config layer to change it faster (see RD-009).
- **Launch-blocker status:** YES (inherited from DC-001/DC-003).
- **Confidence:** 🟧 Confirmed by Config.
- **Status:** OPEN

---

## RD-006 — No build-number increment process; every build currently produces the identical `1.0.0+1` (new finding)

- **Category:** `MOB-01` / `ART-01`
- **Severity:** **RD1 — High**
- **Release stage:** Versioning / Artifact
- **Config path:** `pubspec.yaml` line 20 (`version: 1.0.0+1`)
- **Expected behavior:** A documented or automated process (CI step, script, or at minimum a written release checklist) that increments the `+N` build number for every store submission, since Flutter maps this directly to Android `versionCode` and iOS `CFBundleVersion`.
- **Actual/configured behavior:** `pubspec.yaml` declares a single static value, `1.0.0+1`. Exhaustive search across `*.md`, `*.sh`, `*.yaml`, `*.yml` (excluding `node_modules`/`build`) for any reference to `versionCode`, `CFBundleVersion`, `buildNumber`, or `build-number` found **no automation and no documented manual procedure** — only the declaration itself and this and the master baseline audit's descriptions of it.
- **Production impact:** **Both Google Play and the App Store reject a re-upload whose `versionCode`/`CFBundleVersion` is unchanged from a previously-accepted build**, even if the source code changed. Concretely:
  - If a build is ever successfully submitted at `versionCode 1`, every subsequent submission attempt will be **rejected outright** unless a human remembers to manually edit `pubspec.yaml`'s `+N` before each build. Nothing in the repo prompts, validates, or enforces this.
  - There is no `--build-number` override wired into any script either (Flutter supports overriding at build time via `--build-number`, but no script in the repo uses this flag).
  - This is a certain, mechanical constraint of both platforms' upload validation — not a probabilistic risk.
- **Rollback impact:** Directly limits emergency hotfix speed — a rushed hotfix release could fail at the store-upload step itself (before any review even begins) if the build-number bump is forgotten under pressure, adding an avoidable delay to exactly the situation (an urgent fix) where delay is most costly.
- **Launch-blocker status:** YES for *sustained* releasability (the very first submission is not blocked by this specific finding, but RD-001 blocks that first submission anyway; this finding blocks every submission after the first).
- **Confidence:** 🟧 Confirmed by Config/absence-of-process search.
- **Status:** OPEN

---

## RD-007 — No CHANGELOG, release notes, or app-store metadata exists in the repository; the in-app "Privacy Policy" link is non-functional (new finding)

- **Category:** `MOB-01` / `HOTFIX-01`
- **Severity:** **RD1 — High**
- **Release stage:** Store submission / release documentation
- **Config path:** N/A (absence); `lib/features/auth/presentation/screens/sign_in_screen.dart` lines ~342-366 for the non-functional link
- **Expected behavior:** A `CHANGELOG.md` or equivalent release-notes source, a `fastlane/metadata`-style directory (or any store-listing content: descriptions, screenshots), and — critically for a health-data app — a live, reachable privacy-policy URL wired into the actual app UI and ready to paste into both store consoles at submission time.
- **Actual/configured behavior:**
  - No `CHANGELOG*` file exists anywhere in the repo (confirmed by search, re-verified this pass).
  - No release-notes file, `fastlane/` directory, or store-metadata directory exists.
  - The sign-in screen's consent checkbox displays styled text reading "Privacy Policy" and "Terms of Use" (`_tr('Privacy Policy', 'سياسة الخصوصية')`, `_tr('Terms of Use', 'شروط الاستخدام')`) as plain `TextSpan` children with **no `TapGestureRecognizer`, no `onTap` handler, and no `url_launcher` call** (confirmed by reading the full surrounding widget — `url_launcher` is a dependency in `pubspec.yaml` but is not used at this call site). Users see the words but cannot open any actual policy document from this screen, and no privacy-policy document/URL was found anywhere in the repository.
- **Evidence:** 🟧 Confirmed by exhaustive file search + direct code read this pass.
- **Production impact:**
  1. Both Google Play Console and Apple App Store Connect **require a live, reachable privacy-policy URL** at submission time for any app collecting personal/health data (this app tracks menstrual cycles, pregnancy status, and offers an AI health chat) — this alone is a hard submission blocker for both stores, independent of every other finding in this report.
  2. Absent release notes means the store submission process has nothing prepared to paste into the "What's New" field, and there is no historical record for the team (or a future auditor) to reconstruct what changed between versions once more than one release exists.
- **Rollback impact:** N/A directly, but a missing changelog compounds RD-006/RD-003 — with no version history and no CI-tagged builds, distinguishing "what shipped in the release we need to roll back from" becomes a matter of manual reconstruction.
- **Launch-blocker status:** YES (the privacy-policy-URL gap specifically is a near-certain store-submission blocker for a health-data app; the changelog/metadata gap is a process gap that should be closed before submission but is more bounded).
- **Confidence:** 🟧 Confirmed by Config/code.
- **Status:** OPEN
- **Cross-reference:** Privacy/Compliance audit is the authoritative owner of whether a privacy policy *document* is required and what it must contain; this finding is registered here from the release/store-submission-readiness angle — the two should be reconciled by the same remediation action.

---

## RD-008 — Git history offers no incremental release-provenance trail (new finding)

- **Category:** `ART-01` / `APPROVE-01`
- **Severity:** **RD2 — Medium**
- **Release stage:** Provenance / Approval
- **Config path:** N/A — `git log` output itself is the evidence
- **Expected behavior:** An incremental commit history (or at minimum, a documented reason for a squashed/reset history) that lets a reviewer trace how the current state was assembled, reviewed, and by whom, over time.
- **Actual/configured behavior:** The entire repository history is exactly two commits: `6d59bfe` ("feat: initial clean commit for Niswah mobile app" — a single 426-file, ~92,946-line commit that adds the entire application at once) and `13a9387` ("docs: update README" — a 21-line trim). Both are authored by the same single author (`rayan2099`), directly on `main`, with no PR trail (no `.github/` directory exists to have hosted one, and no evidence of branch-based review is visible from the repo itself). No tags exist.
- **Evidence:** 🟧 Confirmed by `git log --stat --graph --all` this pass.
- **Production impact:** This is not itself a defect in the *shipped code* — a squashed/reset history does not imply the code is wrong. But it does mean:
  - No independent reviewer can use git history to verify this commit is the product of an intentional, reviewed assembly process versus an unreviewed snapshot dropped in at once. The "initial clean commit" commit message and its scale (an entire, fully-featured app arriving in one commit, including a `.claude/scheduled_tasks.lock` file and this very `production-readiness/` audit-template directory) are consistent with the history having been reset/squashed from a prior, unavailable trail — the commit message itself uses the word "clean," suggesting intentional history removal, though the actual reason is **not stated anywhere and cannot be independently confirmed from the repo**.
  - There is no way to identify who reviewed what, when, or whether any change was ever reverted, hotfixed, or contested during development — the audit trail a release process normally relies on for accountability does not exist for anything prior to this snapshot.
  - Going forward, this also means there is no established branching/review discipline for the team to fall back on; the pattern so far is direct-to-`main` commits by one author.
- **Rollback impact:** Indirect — without incremental history, "roll back to the last known-good commit" is a much blunter instrument (only one prior commit exists to roll back to, and it differs from the current commit only by a README edit — there is effectively no meaningfully different "previous version" to roll back to within this repo's own history).
- **Launch-blocker status:** NO on its own (RD2, bounded — the code can still be reviewed as it stands today; this is a process-maturity gap, not a defect in the current artifact) — but it should be explicitly acknowledged and accepted by the release owner, not silently assumed away.
- **Confidence:** 🟧 Confirmed by Config (git history itself).
- **Status:** OPEN

---

## RD-009 — No mechanism exists to mitigate a bad mobile release faster than a full app-store review cycle, beyond one narrow, informally-verified backend kill switch (new finding)

- **Category:** `FLAG-01` / `ROLL-01`
- **Severity:** **RD1 — High**
- **Release stage:** Rollback / Feature flags
- **Config path:** N/A (absence is the primary finding); positive evidence at `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart`, `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart`
- **Expected behavior:** Some combination of: a feature-flag system allowing risky functionality to be disabled remotely without a store release, and/or a documented emergency-disable runbook for backend-dependent features.
- **Actual/configured behavior:** No feature-flag system exists anywhere in `lib/` (confirmed by the master baseline and re-confirmed by this audit's review of the same codebase — no LaunchDarkly/Firebase Remote Config/custom flag service found). One genuine, if informal, mitigation lever was identified: the `dr-niswah-chat` Supabase Edge Function could be disabled or altered via the Supabase dashboard without requiring a client release, and the client code that calls it degrades gracefully rather than crashing — `DrNiswahBackendService.send()` throws a `StateError` on a non-200/malformed response, and the caller in `chat_view_model.dart` (`_sendViaDrNiswahBackend`) wraps that call in a `try`/`catch`, meaning a disabled function surfaces as a handled error state to the user rather than an app crash (verified by direct code read this pass). This was checked and confirmed for **this one feature path only** — it was not exhaustively verified for every other Supabase-backed feature in the app (cycle tracking, community board, private messaging, pregnancy tracking, etc.), each of which would need its own error-handling path individually confirmed before being relied on as a mitigation lever.
- **Evidence:** 🟧 Confirmed by Config/code for the one verified path; 🟨 Likely-but-unverified that the same graceful-degradation pattern extends to other Supabase-backed features (not exhaustively checked in this pass — flagged, not assumed).
- **Production impact:** If a bad release ships a broken *client-side* bug (a crash, a UI regression, an incorrect calculation), the only mitigation path is a fast-follow release, which — given RD-001/RD-002/RD-006 — currently cannot even be legitimately built and submitted at all, let alone quickly. If the bad behavior is *backend-driven* through the `dr-niswah-chat` function specifically, the Supabase-side lever provides a genuine faster mitigation, days faster than a store review cycle — but this is an ad hoc, undocumented capability discovered by code reading, not an intentional, tested, or runbook-documented one, and it does not generalize to other risky features without individual verification.
- **Rollback impact:** This finding *is* the rollback-capability assessment for this system: rollback capability for the mobile client is effectively **absent**, and the one real mitigation lever that exists is narrow, undocumented, and unverified beyond a single feature path.
- **Launch-blocker status:** YES — a production mobile app with no rollback path and no verified emergency-disable capability beyond one narrow, undocumented case is a materially unreliable release posture per RD1's definition.
- **Confidence:** 🟧 for the verified path / 🟨 for generalizing beyond it.
- **Status:** OPEN

---

## RD-010 — No documented release-signing key custody/backup plan (new observation, downstream of RD-001/RD-002)

- **Category:** `MOB-01`
- **Severity:** **RD3 — Low** *(currently moot while RD-001/RD-002 remain open — no real key exists yet to lose — but must be resolved as part of closing RD-001, not after)*
- **Release stage:** Build / Signing
- **Config path:** N/A
- **Expected behavior:** Once a real release keystore/signing identity is introduced (per RD-001/RD-002 remediation), a documented backup/custody plan (who holds the keystore password, where is the `.jks` file backed up, what happens if the sole key-holder is unavailable) should exist, since losing an Android release keystore makes the existing Play Store listing permanently un-updatable under that package name.
- **Actual/configured behavior:** N/A today (no key exists) — flagged now so the eventual remediation of RD-001 does not itself introduce a new single-point-of-failure without a custody plan.
- **Evidence:** ⬜ Not yet applicable — forward-looking observation, not a defect in the current state.
- **Launch-blocker status:** NO (backlog-acceptable per RD3/RD4, but should be included in the RD-001 remediation design rather than treated as a separate later task).
- **Confidence:** N/A (observation).
- **Status:** OPEN (tracked for remediation design)

---

## Static Verification Matrix

| Check ID | Category | Release stage | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| CI-01 | CI | Pipeline | CI/CD pipeline exists and gates release builds | No CI config found anywhere | **FAIL** — RD-003 |
| BUILD-01 | Build | Reproducibility | Pinned toolchain, deterministic build | No `.fvmrc`/equivalent found | **FAIL** — RD-004 |
| ART-01 | Artifact | Provenance | Artifact traceable to commit/build number | No build-number automation; no artifact exists | **FAIL** — RD-006, RD-008 |
| ENV-01 | Environment separation | Build config | Distinct dev/staging/prod build profiles | Single `.env`, no flavors, `APP_ENV` inert | **FAIL** — RD-005 |
| MOB-01 (Android) | Mobile release | Signing | Real release keystore configured | Debug keystore hardcoded, `TODO` unresolved | **FAIL** — RD-001 |
| MOB-01 (iOS) | Mobile release | Signing | Pinned `DEVELOPMENT_TEAM`/manual signing | `Automatic`, no team set | **FAIL** — RD-002 |
| MOB-02 | Mobile release | Store metadata | Changelog, screenshots, privacy-policy URL ready | None found; in-app privacy link non-functional | **FAIL** — RD-007 |
| ROLL-01 | Rollback | Mitigation | Documented rollback/kill-switch path | No formal path; one narrow undocumented ad hoc lever | **FAIL** — RD-009 |
| FLAG-01 | Feature flags | Emergency disable | Flag system for risky features | None exists | **FAIL** — RD-009 |
| APPROVE-01 | Approval | Ownership | Reviewable, incremental change history | 2-commit squashed history, single author | **FAIL** — RD-008 |
| SMOKE-01 | Post-deploy | Verification | Smoke-test plan/script exists | None found | **FAIL** (not separately numbered — contributes to overall NO-GO; see report) |

---

## Finding Register Summary

| Finding ID | Category | Severity | Release stage | Summary | Launch blocker? | Status |
|---|---|---|---|---|---|---|
| RD-001 | MOB/ART | **RD0** | Signing | Android release signed with debug keystore (cross-ref DC-005/SEC-003) | YES | OPEN |
| RD-002 | MOB | RD1 | Signing | iOS `CODE_SIGN_STYLE = Automatic`, no `DEVELOPMENT_TEAM` (cross-ref DC-010) | YES | OPEN |
| RD-003 | CI | RD1 | Pipeline | No CI/CD pipeline exists (cross-ref DC-006) | YES | OPEN |
| RD-004 | BUILD | RD2 | Build | No Flutter/Dart SDK pinning (cross-ref DC-007) | NO | OPEN |
| RD-005 | ENV/CFG | RD1 | Build config | No environment separation; single `.env` bundled as asset (cross-ref DC-001/DC-003) | YES | OPEN |
| RD-006 | MOB/ART | RD1 | Versioning | No build-number increment process; static `1.0.0+1` | YES | OPEN |
| RD-007 | MOB | RD1 | Store submission | No changelog/metadata; privacy-policy link non-functional | YES | OPEN |
| RD-008 | ART/APPROVE | RD2 | Provenance | 2-commit squashed git history, no review trail | NO | OPEN |
| RD-009 | FLAG/ROLL | RD1 | Rollback | No rollback path faster than store review beyond one narrow, unverified-beyond-one-feature ad hoc lever | YES | OPEN |
| RD-010 | MOB | RD3 | Signing | No key-custody plan (forward-looking, tied to RD-001 remediation) | NO | OPEN |

**Totals:** RD0: 1 · RD1: 6 · RD2: 2 · RD3: 1 · RD4: 0
